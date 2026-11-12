
/**
 * GOLDVUEE | INTERNAL PAYMENT VERIFICATION SERVICE
 *
 * Razorpay Test Mode
 *
 * Responsibilities:
 * 1. Identify authenticated customer
 * 2. Check payment ownership
 * 3. Fetch payment from Razorpay
 * 4. Validate captured payment and amount
 * 5. Prevent duplicate confirmations
 * 6. Commit reserved inventory
 * 7. Update Payment and Jewellery Order
 * 8. Convert shopping cart
 *
 * Security:
 * - Runs in system context.
 * - Customer ownership is verified explicitly.
 * - Razorpay secret stays in Named Credential.
 *
 * Production readiness:
 * Checkout HMAC is verified by the server-side event subscriber
 * before finalization. Webhook reconciliation is still pending.
 */
public without sharing class GVPaymentVerificationService {

    public class VerificationException extends Exception {}

    public class Result {
        public Boolean success;
        public Id orderId;
        public String orderNumber;
        public String paymentStatus;
        public String orderStatus;
        public String message;
    }

    // ============================================
    // MAIN VERIFICATION METHOD
    // ============================================

    public static Result verify(
        Id paymentId,
        String razorpayPaymentId,
        Id currentUserId
    ) {

        // STEP 1: VALIDATE INPUT

        if (
            paymentId == null ||
            currentUserId == null ||
            currentUserId != UserInfo.getUserId() ||
            String.isBlank(razorpayPaymentId) ||
            !Pattern.matches(
                '^pay_[A-Za-z0-9]+$',
                razorpayPaymentId
            )
        ) {
            throw new VerificationException(
                'Invalid payment verification request.'
            );
        }

        // STEP 2: IDENTIFY CUSTOMER

        List<User> users = [
            SELECT Id, ContactId
            FROM User
            WHERE Id = :currentUserId
            LIMIT 1
        ];

        if (
            users.isEmpty() ||
            users[0].ContactId == null
        ) {
            throw new VerificationException(
                'Please sign in to your GoldVuee account.'
            );
        }

        Id contactId = users[0].ContactId;

        // STEP 3: PRECHECK PAYMENT OWNERSHIP

                
          
        List<Payment__c> prechecks = [
            SELECT Id,
                Jewellery_Order__c,
                Jewellery_Order__r.Customer__c,
                Jewellery_Order__r.Name,
                Jewellery_Order__r.Payment_Status__c,
                Jewellery_Order__r.Order_Status__c,
                Razorpay_Order_ID__c,
                Razorpay_Verified_Payment_ID__c,
                Payment_Status__c,
                Transaction_ID__c
            FROM Payment__c
            WHERE Id = :paymentId
            WITH SYSTEM_MODE
            LIMIT 1
        ];


        if (
            prechecks.isEmpty() ||
            prechecks[0].Jewellery_Order__c == null ||
            prechecks[0].Jewellery_Order__r.Customer__c
                != contactId
        ) {
            throw new VerificationException(
                'Payment not found or access denied.'
            );
        }

        Payment__c precheck = prechecks[0];
                
        // Return the existing confirmed result for a
        // retry of the same authenticated transaction.

        if (
            precheck.Payment_Status__c == 'Success' &&
            precheck.Transaction_ID__c == razorpayPaymentId &&
            precheck.Jewellery_Order__r.Payment_Status__c == 'Paid' &&
            precheck.Jewellery_Order__r.Order_Status__c == 'Confirmed'
        ) {
            Result existingResult = new Result();

            existingResult.success = true;
            existingResult.orderId =
                precheck.Jewellery_Order__c;
            existingResult.orderNumber =
                precheck.Jewellery_Order__r.Name;
            existingResult.paymentStatus = 'Paid';
            existingResult.orderStatus = 'Confirmed';
            existingResult.message =
                'Payment was already verified.';

            return existingResult;
        }

        // A completed payment with a different transaction
        // must never be verified as a new payment.
        if (precheck.Payment_Status__c == 'Success') {
            throw new VerificationException(
                'This order has already been paid.'
            );
        }








        if (
            String.isBlank(
                precheck.Razorpay_Order_ID__c
            )
        ) {
            throw new VerificationException(
                'Razorpay order has not been initialized.'
            );
        }

        // Signature was checked using the server-side secret by
        // the Automated Process platform-event subscriber.
        // A captured payment ID alone MUST NOT finalize an order.
        if (
            precheck.Razorpay_Verified_Payment_ID__c !=
                razorpayPaymentId
        ) {
            throw new VerificationException(
                'Razorpay checkout signature is not yet verified.'
            );
        }

        // STEP 4: FETCH PAYMENT FROM RAZORPAY
        // No Salesforce DML before this callout.

        GVRazorpayService.RazorpayPaymentDetails gateway =
            GVRazorpayService.fetchPayment(
                razorpayPaymentId
            );

        // STEP 5: VERIFY GATEWAY RESPONSE

        if (
            gateway == null ||
            gateway.paymentId != razorpayPaymentId ||
            gateway.orderId !=
                precheck.Razorpay_Order_ID__c ||
            gateway.currencyCode != 'INR' ||
            gateway.paymentStatus != 'captured' ||
            gateway.captured != true
        ) {
            throw new VerificationException(
                'Razorpay payment is not captured ' +
                'or does not match this GoldVuee order.'
            );
        }

        String methodValue =
            mapPaymentMethod(
                gateway.paymentMethod
            );

        // STEP 6: START DATABASE TRANSACTION

        Savepoint sp = Database.setSavepoint();

        try {

            // ====================================
            // LOCK PAYMENT RECORD
            // ====================================

                    
            
            List<Payment__c> payments = [
                SELECT Id,
                    Jewellery_Order__c,
                    Payment_Amount__c,
                    Payment_Status__c,
                    Payment_Method__c,
                    Razorpay_Order_ID__c,
                    Razorpay_Verified_Payment_ID__c,
                    Transaction_ID__c
                FROM Payment__c
                WHERE Id = :paymentId
                WITH SYSTEM_MODE
                LIMIT 1
                FOR UPDATE
            ];


            if (payments.isEmpty()) {
                throw new VerificationException(
                    'Payment record not found.'
                );
            }

            Payment__c payment = payments[0];

            // ====================================
            // LOCK JEWELLERY ORDER
            // ====================================

            List<Jewellery_Order__c> orders = [
                SELECT Id,
                       Name,
                       Customer__c,
                       Shopping_Cart__c,
                       Grand_Total__c,
                       Order_Status__c,
                       Payment_Status__c
                FROM Jewellery_Order__c
                WHERE Id = :payment.Jewellery_Order__c
                WITH SYSTEM_MODE
                LIMIT 1
                FOR UPDATE
            ];

            if (orders.isEmpty()) {
                throw new VerificationException(
                    'Jewellery order not found.'
                );
            }

            Jewellery_Order__c orderRecord =
                orders[0];

            // ====================================
            // RECHECK OWNERSHIP AFTER LOCKING
            // ====================================

            if (
                orderRecord.Customer__c != contactId ||
                payment.Jewellery_Order__c !=
                    precheck.Jewellery_Order__c ||
                payment.Razorpay_Order_ID__c !=
                    gateway.orderId ||
                payment.Razorpay_Verified_Payment_ID__c !=
                    gateway.paymentId
            ) {
                throw new VerificationException(
                    'Payment ownership or reference mismatch.'
                );
            }

            // ====================================
            // VERIFY PAYMENT AMOUNT
            // ====================================

            Decimal amount =
                payment.Payment_Amount__c;

            if (
                amount == null ||
                amount < 1 ||
                amount != amount.setScale(2) ||
                orderRecord.Grand_Total__c != amount ||
                (amount * 100).longValue() !=
                    gateway.amountPaise
            ) {
                throw new VerificationException(
                    'Razorpay payment amount mismatch.'
                );
            }

            // ====================================
            // PREVENT DUPLICATE CONFIRMATIONS
            // ====================================

            if (
                payment.Payment_Status__c == 'Success' &&
                orderRecord.Payment_Status__c == 'Paid' &&
                orderRecord.Order_Status__c == 'Confirmed' &&
                payment.Transaction_ID__c ==
                    gateway.paymentId
            ) {
                return buildResult(
                    orderRecord,
                    'Payment was already verified.'
                );
            }

            if (
                payment.Payment_Status__c != 'Pending' ||
                orderRecord.Payment_Status__c != 'Pending' ||
                orderRecord.Order_Status__c != 'pending'
            ) {
                throw new VerificationException(
                    'This order is not awaiting payment.'
                );
            }

            // ====================================
            // PREVENT REUSE OF PAYMENT TRANSACTION
            // ====================================

            List<Payment__c> duplicates = [
                SELECT Id
                FROM Payment__c
                WHERE Transaction_ID__c =
                    :gateway.paymentId
                AND Id != :payment.Id
                WITH SYSTEM_MODE
                LIMIT 1
            ];

            if (!duplicates.isEmpty()) {
                throw new VerificationException(
                    'This Razorpay transaction is already assigned.'
                );
            }

            // ====================================
            // LOAD INVENTORY RESERVATIONS
            // ====================================

            List<Stock_Reservation__c> reservations = [
                SELECT Id,
                       Jewellery_Product__c,
                       Reserved_Quantity__c,
                       Reservation_Status__c,
                       Expires_At__c
                FROM Stock_Reservation__c
                WHERE Jewellery_Order__c =
                    :orderRecord.Id
                AND Reservation_Status__c = 'Active'
                WITH SYSTEM_MODE
                FOR UPDATE
            ];

            if (reservations.isEmpty()) {
                throw new VerificationException(
                    'No stock reservation found.'
                );
            }

            Map<Id, Decimal> reservedQuantities =
                new Map<Id, Decimal>();

            // ====================================
            // VALIDATE RESERVED INVENTORY
            // ====================================

            for (
                Stock_Reservation__c reservation :
                reservations
            ) {

                if (
                    reservation.Jewellery_Product__c == null ||
                    reservation.Reserved_Quantity__c == null ||
                    reservation.Reserved_Quantity__c <= 0 ||
                    reservation.Reservation_Status__c
                        != 'Active' ||
                    reservation.Expires_At__c == null ||
                    reservation.Expires_At__c <=
                        System.now()
                ) {
                    throw new VerificationException(
                        'Stock reservation is invalid or expired. ' +
                        'Payment requires reconciliation.'
                    );
                }

                Id productId =
                    reservation.Jewellery_Product__c;

                Decimal previousQuantity =
                    reservedQuantities.containsKey(productId)
                    ? reservedQuantities.get(productId)
                    : 0;

                reservedQuantities.put(
                    productId,
                    previousQuantity +
                    reservation.Reserved_Quantity__c
                );
            }

            // ====================================
            // LOAD ORDER ITEMS
            // ====================================

            List<Jewellery_Order_Item__c> orderItems = [
                SELECT Jewellery_Product__c,
                       Quantity__c
                FROM Jewellery_Order_Item__c
                WHERE Jewellery_Order__c =
                    :orderRecord.Id
                WITH SYSTEM_MODE
            ];

            Map<Id, Decimal> orderedQuantities =
                new Map<Id, Decimal>();

            for (
                Jewellery_Order_Item__c item :
                orderItems
            ) {

                if (
                    item.Jewellery_Product__c == null ||
                    item.Quantity__c == null ||
                    item.Quantity__c <= 0
                ) {
                    throw new VerificationException(
                        'Invalid jewellery order item.'
                    );
                }

                Id productId =
                    item.Jewellery_Product__c;

                Decimal previousQuantity =
                    orderedQuantities.containsKey(productId)
                    ? orderedQuantities.get(productId)
                    : 0;

                orderedQuantities.put(
                    productId,
                    previousQuantity +
                    item.Quantity__c
                );
            }

            // ====================================
            // COMPARE ORDER AND RESERVED QUANTITY
            // ====================================

            if (
                orderedQuantities.isEmpty() ||
                orderedQuantities != reservedQuantities
            ) {
                throw new VerificationException(
                    'Order items and stock reservations do not match.'
                );
            }

            // ====================================
            // COMMIT INVENTORY
            // ====================================

            for (
                Stock_Reservation__c reservation :
                reservations
            ) {
                GVInventoryService.commitReservation(
                    reservation.Id
                );
            }

            // ====================================
            // UPDATE PAYMENT
            // ====================================

            payment.Payment_Status__c = 'Success';
            payment.Payment_Method__c = methodValue;
            payment.Transaction_ID__c =
                gateway.paymentId;
            payment.Payment_Date__c = System.now();

            payment.Gateway_Response__c =
                JSON.serialize(
                    new Map<String, Object>{
                        'payment_id' =>
                            gateway.paymentId,
                        'order_id' =>
                            gateway.orderId,
                        'status' =>
                            gateway.paymentStatus,
                        'amount_paise' =>
                            gateway.amountPaise,
                        'method' =>
                            gateway.paymentMethod
                    }
                );

            Database.update(
                payment,
                true,
                AccessLevel.SYSTEM_MODE
            );

            // ====================================
            // CONFIRM JEWELLERY ORDER
            // ====================================

            orderRecord.Payment_Status__c = 'Paid';
            orderRecord.Order_Status__c = 'Confirmed';

            Database.update(
                orderRecord,
                true,
                AccessLevel.SYSTEM_MODE
            );

            // ====================================
            // CONVERT SHOPPING CART
            // ====================================

            if (
                orderRecord.Shopping_Cart__c != null
            ) {

                List<Shopping_Cart__c> carts = [
                    SELECT Id,
                           Cart_Status__c
                    FROM Shopping_Cart__c
                    WHERE Id =
                        :orderRecord.Shopping_Cart__c
                    WITH SYSTEM_MODE
                    LIMIT 1
                    FOR UPDATE
                ];

                if (
                    carts.isEmpty() ||
                    carts[0].Cart_Status__c != 'Active'
                ) {
                    throw new VerificationException(
                        'Shopping cart is no longer active.'
                    );
                }

                carts[0].Cart_Status__c =
                    'Converted';

                Database.update(
                    carts[0],
                    true,
                    AccessLevel.SYSTEM_MODE
                );
            }

            // ====================================
            // RETURN SUCCESS
            // ====================================

            return buildResult(
                orderRecord,
                'GoldVuee payment verified successfully.'
            );

        } catch (Exception e) {

            Database.rollback(sp);

            System.debug(
                LoggingLevel.ERROR,
                'GOLDVUEE PAYMENT SERVICE FAILURE | ' +
                'Type: ' + e.getTypeName() +
                ' | Message: ' + e.getMessage() +
                ' | Line: ' + e.getLineNumber()
            );

            throw e;
        }
    }

    // ============================================
    // MAP RAZORPAY METHOD TO SALESFORCE PICKLIST
    // ============================================

    private static String mapPaymentMethod(
        String method
    ) {

        if (method == 'upi') {
            return 'UPI';
        }

        if (method == 'card') {
            return 'Card';
        }

        if (method == 'netbanking') {
            return 'Net Banking';
        }

        if (method == 'wallet') {
            return 'Wallet';
        }

        throw new VerificationException(
            'Unsupported Razorpay payment method.'
        );
    }

    // ============================================
    // BUILD RESULT
    // ============================================

    private static Result buildResult(
        Jewellery_Order__c orderRecord,
        String message
    ) {

        Result result = new Result();

        result.success = true;
        result.orderId = orderRecord.Id;
        result.orderNumber = orderRecord.Name;
        result.paymentStatus =
            orderRecord.Payment_Status__c;
        result.orderStatus =
            orderRecord.Order_Status__c;
        result.message = message;

        return result;
    }
}
