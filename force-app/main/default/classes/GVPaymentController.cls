
/**
 * GOLDVUEE | RAZORPAY PAYMENT CONTROLLER
 *
 * Creates a Razorpay payment order for an
 * existing pending Salesforce payment.
 *
 * Does not capture, verify, or confirm payments.
 */
public with sharing class GVPaymentController {

    public class PaymentException extends Exception {}

    public class PaymentResult {
        @AuraEnabled public Id paymentId;
        @AuraEnabled public Id orderId;
        @AuraEnabled public String razorpayOrderId;
        @AuraEnabled public Long amountPaise;
        @AuraEnabled public String currencyCode;
        @AuraEnabled public String message;
    }

    @AuraEnabled
    public static PaymentResult initiatePayment(Id paymentId) {

        try {
            if (paymentId == null) {
                throw new PaymentException(
                    'Payment ID is required.'
                );
            }

            // STEP 1: IDENTIFY CUSTOMER
            List<User> users = [
                SELECT ContactId
                FROM User
                WHERE Id = :UserInfo.getUserId()
                LIMIT 1
            ];

            if (users.isEmpty() ||
                users[0].ContactId == null) {
                throw new PaymentException(
                    'Please sign in to your GoldVuee account.'
                );
            }

            Id contactId = users[0].ContactId;

            // STEP 2: LOAD PAYMENT AND ORDER
            List<Payment__c> payments = [
                SELECT Id,
                       Jewellery_Order__c,
                       Jewellery_Order__r.Customer__c,
                       Jewellery_Order__r.Order_Status__c,
                       Jewellery_Order__r.Payment_Status__c,
                       Jewellery_Order__r.Grand_Total__c,
                       Payment_Amount__c,
                       Payment_Status__c,
                       Razorpay_Order_ID__c
                FROM Payment__c
                WHERE Id = :paymentId
                WITH SYSTEM_MODE
                LIMIT 1
            ];

            if (payments.isEmpty()) {
                throw new PaymentException(
                    'Payment record not found.'
                );
            }

            Payment__c payment = payments[0];

            // STEP 3: VERIFY OWNERSHIP
            if (
                payment.Jewellery_Order__c == null ||
                payment.Jewellery_Order__r.Customer__c
                    != contactId
            ) {
                throw new PaymentException(
                    'You cannot access this payment.'
                );
            }

            // STEP 4: VALIDATE ORDER STATES
            if (
                payment.Payment_Status__c != 'Pending' ||
                payment.Jewellery_Order__r.Payment_Status__c
                    != 'Pending' ||
                payment.Jewellery_Order__r.Order_Status__c
                    != 'pending'
            ) {
                throw new PaymentException(
                    'This order is not awaiting payment.'
                );
            }

            Decimal amount = payment.Payment_Amount__c;
            Decimal orderTotal =
                payment.Jewellery_Order__r.Grand_Total__c;

            if (
                amount == null ||
                amount < 1 ||
                amount != amount.setScale(2) ||
                orderTotal == null ||
                amount != orderTotal
            ) {
                throw new PaymentException(
                    'Order amount verification failed.'
                );
            }

            // STEP 5: VERIFY ACTIVE RESERVATIONS
            List<Stock_Reservation__c> reservations = [
                SELECT Id,
                       Reservation_Status__c,
                       Expires_At__c
                FROM Stock_Reservation__c
                WHERE Jewellery_Order__c =
                    :payment.Jewellery_Order__c
            ];

            if (reservations.isEmpty()) {
                throw new PaymentException(
                    'No inventory reservation found.'
                );
            }

            for (Stock_Reservation__c reservation :
                reservations) {

                if (
                    reservation.Reservation_Status__c
                        != 'Active' ||
                    reservation.Expires_At__c == null ||
                    reservation.Expires_At__c <=
                        System.now()
                ) {
                    throw new PaymentException(
                        'Your stock reservation has expired. ' +
                        'Please restart checkout.'
                    );
                }
            }

            // STEP 6: REUSE EXISTING RAZORPAY ORDER
            if (!String.isBlank(
                payment.Razorpay_Order_ID__c
            )) {
                return buildResult(
                    payment,
                    (amount * 100).longValue(),
                    'Existing Razorpay order retrieved.'
                );
            }

            // STEP 7: CREATE RAZORPAY ORDER
            // Callout occurs BEFORE Salesforce DML.
            String receipt = String.valueOf(payment.Id);

            GVRazorpayService.RazorpayOrder
                razorpayOrder =
                GVRazorpayService.createOrder(
                    amount,
                    receipt
                );

            // STEP 8: RECHECK AND LOCK PAYMENT
           
            List<Payment__c> lockedPayments = [
                SELECT Id,
                    Jewellery_Order__c,
                    Payment_Status__c,
                    Razorpay_Order_ID__c,
                    Payment_Amount__c,
                    Jewellery_Order__r.Customer__c,
                    Jewellery_Order__r.Order_Status__c,
                    Jewellery_Order__r.Payment_Status__c,
                    Jewellery_Order__r.Grand_Total__c
                FROM Payment__c
                WHERE Id = :paymentId
                WITH SYSTEM_MODE
                LIMIT 1
                FOR UPDATE
            ];


            if (lockedPayments.isEmpty()) {
                throw new PaymentException(
                    'Payment is no longer available.'
                );
            }

            Payment__c lockedPayment = lockedPayments[0];

            if (
                lockedPayment.Jewellery_Order__r.Customer__c
                    != contactId ||
                lockedPayment.Payment_Status__c != 'Pending' ||
                lockedPayment.Jewellery_Order__r.Payment_Status__c
                    != 'Pending' ||
                lockedPayment.Jewellery_Order__r.Order_Status__c
                    != 'pending' ||
                lockedPayment.Payment_Amount__c != amount ||
                lockedPayment.Jewellery_Order__r.Grand_Total__c
                    != amount
            ) {
                throw new PaymentException(
                    'Payment changed during initialization.'
                );
            }

            // Another request may have saved its order first.
            if (!String.isBlank(
                lockedPayment.Razorpay_Order_ID__c
            )) {
                return buildResult(
                    lockedPayment,
                    (amount * 100).longValue(),
                    'Existing Razorpay order retrieved.'
                );
            }

            // STEP 9: SAVE RAZORPAY ORDER ID
            lockedPayment.Razorpay_Order_ID__c =
                razorpayOrder.razorpayOrderId;

            update lockedPayment;

            return buildResult(
                lockedPayment,
                razorpayOrder.amountPaise,
                'Razorpay payment initialized.'
            );

        } catch (PaymentException e) {
            throw new AuraHandledException(
                e.getMessage()
            );

        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'GV PAYMENT ERROR: ' +
                e.getMessage() + ' | ' +
                e.getStackTraceString()
            );

            throw new AuraHandledException(
                'Unable to initialize Razorpay payment.'
            );
        }
    }

    private static PaymentResult buildResult(
        Payment__c payment,
        Long amountPaise,
        String message
    ) {
        PaymentResult result = new PaymentResult();

        result.paymentId = payment.Id;
        result.orderId = payment.Jewellery_Order__c;
        result.razorpayOrderId =
            payment.Razorpay_Order_ID__c;
        result.amountPaise = amountPaise;
        result.currencyCode = 'INR';
        result.message = message;

        return result;
    }
}
