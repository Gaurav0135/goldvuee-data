
/**
 * GOLDVUEE | ONLINE CHECKOUT CONTROLLER
 *
 * Razorpay Test Mode
 *
 * Responsibilities:
 * 1. Validate authenticated customer
 * 2. Validate delivery information
 * 3. Lock active shopping cart
 * 4. Safely reuse a pending online order
 * 5. Validate products, prices and stock
 * 6. Create jewellery order and order items
 * 7. Reserve inventory
 * 8. Create pending payment
 *
 * This controller does NOT capture or confirm payments.
 */
public with sharing class GVOnlineCheckoutController {

    public class CheckoutException extends Exception {}

    public class CheckoutResult {
        @AuraEnabled public Id orderId;
        @AuraEnabled public Id paymentId;
        @AuraEnabled public String orderNumber;
        @AuraEnabled public Decimal grandTotal;
        @AuraEnabled public String orderStatus;
        @AuraEnabled public String paymentStatus;
        @AuraEnabled public String message;
    }

    @AuraEnabled
    public static CheckoutResult prepareOnlineOrder(
        String shippingAddress,
        String shippingCity,
        String shippingState,
        String shippingPostalCode,
        String shippingCountry
    ) {

        Savepoint sp = Database.setSavepoint();

        try {

            // ============================================
            // STEP 1: VALIDATE CUSTOMER
            // ============================================

            List<User> users = [
                SELECT Id, ContactId
                FROM User
                WHERE Id = :UserInfo.getUserId()
                LIMIT 1
            ];

            if (
                users.isEmpty() ||
                users[0].ContactId == null
            ) {
                throw new CheckoutException(
                    'Please sign in to your GoldVuee account.'
                );
            }

            Id contactId = users[0].ContactId;

            // ============================================
            // STEP 2: VALIDATE SHIPPING
            // ============================================

            shippingAddress = clean(shippingAddress);
            shippingCity = clean(shippingCity);
            shippingState = clean(shippingState);
            shippingPostalCode = clean(shippingPostalCode);
            shippingCountry = clean(shippingCountry);

            if (
                String.isBlank(shippingAddress) ||
                String.isBlank(shippingCity) ||
                String.isBlank(shippingState) ||
                String.isBlank(shippingPostalCode) ||
                String.isBlank(shippingCountry)
            ) {
                throw new CheckoutException(
                    'Please complete all delivery fields.'
                );
            }

            if (
                shippingAddress.length() > 32768 ||
                shippingCity.length() > 50 ||
                shippingState.length() > 50 ||
                shippingPostalCode.length() > 20 ||
                shippingCountry.length() > 100
            ) {
                throw new CheckoutException(
                    'One or more delivery fields are too long.'
                );
            }

            if (
                shippingCountry.toLowerCase() != 'india' ||
                !Pattern.matches(
                    '^[1-9][0-9]{5}$',
                    shippingPostalCode
                )
            ) {
                throw new CheckoutException(
                    'Enter a valid Indian delivery address.'
                );
            }

            // ============================================
            // STEP 3: LOCK ACTIVE SHOPPING CART
            // ============================================

            List<Shopping_Cart__c> carts = [
                SELECT Id,
                       Customer__c,
                       Cart_Status__c
                FROM Shopping_Cart__c
                WHERE Customer__c = :contactId
                AND Cart_Status__c = 'Active'
                LIMIT 2
                FOR UPDATE
            ];

            if (carts.size() != 1) {
                throw new CheckoutException(
                    'Please refresh your shopping bag.'
                );
            }

            Shopping_Cart__c cart = carts[0];

            // Recover an expired, never-initialized Razorpay checkout safely.
            // If Razorpay initialized or the hold is still live, keep it intact.
            GVAbandonedCheckoutService.recoverExpiredCheckout(
                cart.Id, contactId
            );

            // ============================================
            // STEP 4: REUSE EXISTING PENDING ONLINE ORDER
            // ============================================

            List<Jewellery_Order__c> existingOrders = [
                SELECT Id,
                       Name,
                       Customer__c,
                       Shopping_Cart__c,
                       Order_Status__c,
                       Payment_Status__c,
                       Grand_Total__c,
                       Shipping_Address__c,
                       Shipping_City__c,
                       Shipping_State__c,
                       Shipping_Postal_Code__c,
                       Shipping_Country__c
                FROM Jewellery_Order__c
                WHERE Shopping_Cart__c = :cart.Id
                AND Order_Status__c NOT IN ('Cancelled', 'Canceled', 'Abandoned')
                WITH SYSTEM_MODE
                LIMIT 2
                FOR UPDATE
            ];

            if (!existingOrders.isEmpty()) {

                if (existingOrders.size() != 1) {
                    throw new CheckoutException(
                        'Multiple orders exist for this bag. ' +
                        'Please contact support.'
                    );
                }

                Jewellery_Order__c existingOrder =
                    existingOrders[0];

                // Confirm ownership and state.

                if (
                    existingOrder.Customer__c != contactId ||
                    existingOrder.Order_Status__c != 'pending' ||
                    existingOrder.Payment_Status__c != 'Pending'
                ) {
                    throw new CheckoutException(
                        'This shopping bag already has an order. ' +
                        'Please check your account.'
                    );
                }

                // Do not silently reuse a pending order
                // with a different delivery address.

                if (
                    existingOrder.Shipping_Address__c !=
                        shippingAddress ||
                    existingOrder.Shipping_City__c !=
                        shippingCity ||
                    existingOrder.Shipping_State__c !=
                        shippingState ||
                    existingOrder.Shipping_Postal_Code__c !=
                        shippingPostalCode ||
                    existingOrder.Shipping_Country__c !=
                        shippingCountry
                ) {
                    throw new CheckoutException(
                        'This bag has a pending order with ' +
                        'different delivery details. ' +
                        'Please resolve the existing order.'
                    );
                }

                // Verify active reservations.

                List<Stock_Reservation__c> reservations = [
                    SELECT Id,
                           Jewellery_Product__c,
                           Reserved_Quantity__c,
                           Reservation_Status__c,
                           Expires_At__c
                    FROM Stock_Reservation__c
                    WHERE Jewellery_Order__c =
                        :existingOrder.Id
                    WITH SYSTEM_MODE
                    FOR UPDATE
                ];

                if (reservations.isEmpty()) {
                    throw new CheckoutException(
                        'The existing order has no stock reservation.'
                    );
                }

                Map<Id, Decimal> reservedQuantities =
                    new Map<Id, Decimal>();

                // An expired reservation can be recovered only
                // when Razorpay has never initialized for this order.
                Boolean needsReservationRenewal = false;

                for (
                    Stock_Reservation__c reservation :
                    reservations
                ) {

                    if (
                        reservation.Jewellery_Product__c == null ||
                        reservation.Reserved_Quantity__c == null ||
                        reservation.Reserved_Quantity__c <= 0 ||
                        !new Set<String>{
                            'Active', 'Expired', 'Released'
                        }.contains(reservation.Reservation_Status__c)
                    ) {
                        throw new CheckoutException(
                            'Existing inventory reservation needs support.'
                        );
                    }

                    // Ignore historical released/expired holds when
                    // measuring the currently reserved quantity.
                    if (reservation.Reservation_Status__c == 'Active') {
                        if (
                            reservation.Expires_At__c == null ||
                            reservation.Expires_At__c <= System.now()
                        ) {
                            needsReservationRenewal = true;
                        } else {
                            Id productId =
                                reservation.Jewellery_Product__c;

                            Decimal previous =
                                reservedQuantities.containsKey(productId)
                                    ? reservedQuantities.get(productId)
                                    : 0;

                            reservedQuantities.put(
                                productId,
                                previous +
                                reservation.Reserved_Quantity__c
                            );
                        }
                    }
                }

                // Verify that reserved products still
                // match the existing order items.

                List<Jewellery_Order_Item__c> existingItems = [
                    SELECT Jewellery_Product__c,
                           Quantity__c
                    FROM Jewellery_Order_Item__c
                    WHERE Jewellery_Order__c =
                        :existingOrder.Id
                    WITH SYSTEM_MODE
                ];

                Map<Id, Decimal> orderedQuantities =
                    new Map<Id, Decimal>();

                for (
                    Jewellery_Order_Item__c item :
                    existingItems
                ) {

                    if (
                        item.Jewellery_Product__c == null ||
                        item.Quantity__c == null ||
                        item.Quantity__c <= 0
                    ) {
                        throw new CheckoutException(
                            'Existing order contains invalid items.'
                        );
                    }

                    Id productId =
                        item.Jewellery_Product__c;

                    Decimal previous =
                        orderedQuantities.containsKey(productId)
                            ? orderedQuantities.get(productId)
                            : 0;

                    orderedQuantities.put(
                        productId,
                        previous + item.Quantity__c
                    );
                }

                if (orderedQuantities.isEmpty()) {
                    throw new CheckoutException(
                        'Existing order has no valid items.'
                    );
                }

                if (orderedQuantities != reservedQuantities) {
                    needsReservationRenewal = true;
                }

                // Ensure the cart has not changed
                // since the pending order was prepared.

                List<Cart_Item__c> currentCartItems = [
                    SELECT Jewellery_Product__c,
                           Quantity__c
                    FROM Cart_Item__c
                    WHERE Shopping_Cart__c = :cart.Id
                ];

                Map<Id, Decimal> currentCartQuantities =
                    new Map<Id, Decimal>();

                for (
                    Cart_Item__c item :
                    currentCartItems
                ) {

                    if (
                        item.Jewellery_Product__c == null ||
                        item.Quantity__c == null ||
                        item.Quantity__c <= 0
                    ) {
                        throw new CheckoutException(
                            'Shopping bag contains invalid items.'
                        );
                    }

                    Id productId =
                        item.Jewellery_Product__c;

                    Decimal previous =
                        currentCartQuantities.containsKey(productId)
                            ? currentCartQuantities.get(productId)
                            : 0;

                    currentCartQuantities.put(
                        productId,
                        previous + item.Quantity__c
                    );
                }

                if (
                    currentCartQuantities != orderedQuantities
                ) {
                    throw new CheckoutException(
                        'Your shopping bag changed after ' +
                        'the online order was created. ' +
                        'Please resolve the pending order.'
                    );
                }

                // Verify the pending payment record.

                List<Payment__c> existingPayments = [
                    SELECT Id,
                           Jewellery_Order__c,
                           Payment_Amount__c,
                           Payment_Status__c,
                           Razorpay_Order_ID__c,
                           Transaction_ID__c
                    FROM Payment__c
                    WHERE Jewellery_Order__c =
                        :existingOrder.Id
                    WITH SYSTEM_MODE
                    LIMIT 2
                ];

                if (
                    existingPayments.size() != 1 ||
                    existingPayments[0].Payment_Status__c
                        != 'Pending' ||
                    existingPayments[0].Payment_Amount__c
                        != existingOrder.Grand_Total__c ||
                    !String.isBlank(
                        existingPayments[0].Transaction_ID__c
                    )
                ) {
                    throw new CheckoutException(
                        'The existing payment requires reconciliation.'
                    );
                }

                // If the gateway order is not created and no
                // transaction exists, safely release expired holds
                // and reserve the same order items for a fresh 15 min.
                // This preserves the order/payment IDs and does not
                // create a second charge or duplicate jewellery order.
                if (needsReservationRenewal) {
                    if (
                        !String.isBlank(
                            existingPayments[0].Razorpay_Order_ID__c
                        )
                    ) {
                        throw new CheckoutException(
                            'This payment requires gateway reconciliation ' +
                            'before its inventory reservation can be renewed.'
                        );
                    }

                    for (Stock_Reservation__c reservation : reservations) {
                        if (reservation.Reservation_Status__c == 'Active') {
                            GVInventoryService.releaseReservation(
                                reservation.Id
                            );
                        }
                    }

                    for (Id productId : orderedQuantities.keySet()) {
                        GVInventoryService.reserveStock(
                            productId,
                            orderedQuantities.get(productId),
                            existingOrder.Id
                        );
                    }
                }

                // Return the existing pending payment.
                // No additional jewellery order is created.

                CheckoutResult resumed = new CheckoutResult();

                resumed.orderId = existingOrder.Id;
                resumed.paymentId = existingPayments[0].Id;
                resumed.orderNumber = existingOrder.Name;
                resumed.grandTotal =
                    existingOrder.Grand_Total__c;
                resumed.orderStatus =
                    existingOrder.Order_Status__c;
                resumed.paymentStatus =
                    existingPayments[0].Payment_Status__c;
                resumed.message =
                    'Existing pending GoldVuee order resumed.';

                return resumed;
            }

            // ============================================
            // STEP 5: LOAD CART ITEMS
            // ============================================

            List<Cart_Item__c> items = [
                SELECT Id,
                       Jewellery_Product__c,
                       Quantity__c
                FROM Cart_Item__c
                WHERE Shopping_Cart__c = :cart.Id
            ];

            if (items.isEmpty()) {
                throw new CheckoutException(
                    'Your shopping bag is empty.'
                );
            }

            Set<Id> productIds = new Set<Id>();

            Map<Id, Decimal> quantities =
                new Map<Id, Decimal>();

            for (Cart_Item__c item : items) {

                Decimal qty = item.Quantity__c;

                if (
                    item.Jewellery_Product__c == null ||
                    qty == null ||
                    qty <= 0 ||
                    qty != qty.setScale(0)
                ) {
                    throw new CheckoutException(
                        'Invalid cart item.'
                    );
                }

                Id productId =
                    item.Jewellery_Product__c;

                productIds.add(productId);

                Decimal previousQty =
                    quantities.containsKey(productId)
                        ? quantities.get(productId)
                        : 0;

                quantities.put(
                    productId,
                    previousQty + qty
                );
            }

            // ============================================
            // STEP 6: VALIDATE PRODUCT PRICE AND INVENTORY
            // ============================================

            Map<Id, Jewellery_Product__c> products =
                new Map<Id, Jewellery_Product__c>([
                    SELECT Id,
                           Name,
                           Active__c,
                           Price__c,
                           Discount_Price__c,
                           Stock_Quantity__c,
                           Reserved_Quantity__c
                    FROM Jewellery_Product__c
                    WHERE Id IN :productIds
                    FOR UPDATE
                ]);

            if (
                products.size() != productIds.size()
            ) {
                throw new CheckoutException(
                    'Some products are unavailable.'
                );
            }

            List<Id> sortedIds =
                new List<Id>(productIds);

            sortedIds.sort();

            Map<Id, Decimal> prices =
                new Map<Id, Decimal>();

            Decimal subtotal = 0;

            for (Id productId : sortedIds) {

                Jewellery_Product__c product =
                    products.get(productId);

                Decimal stock =
                    product.Stock_Quantity__c == null
                        ? 0
                        : product.Stock_Quantity__c;

                Decimal reserved =
                    product.Reserved_Quantity__c == null
                        ? 0
                        : product.Reserved_Quantity__c;

                Decimal qty =
                    quantities.get(productId);

                if (
                    product.Active__c != true ||
                    stock - reserved < qty
                ) {
                    throw new CheckoutException(
                        'Insufficient available stock for ' +
                        product.Name
                    );
                }

                if (
                    product.Price__c == null ||
                    product.Price__c <= 0
                ) {
                    throw new CheckoutException(
                        'Invalid price for ' +
                        product.Name
                    );
                }

                Decimal price = product.Price__c;

                if (
                    product.Discount_Price__c != null &&
                    product.Discount_Price__c > 0 &&
                    product.Discount_Price__c < price
                ) {
                    price = product.Discount_Price__c;
                }

                prices.put(productId, price);

                subtotal += price * qty;
            }

            if (subtotal < 1) {
                throw new CheckoutException(
                    'Invalid online payment amount.'
                );
            }

            // ============================================
            // STEP 7: CREATE PENDING JEWELLERY ORDER
            // ============================================

            Jewellery_Order__c orderRecord =
                new Jewellery_Order__c(
                    Customer__c = contactId,
                    Shopping_Cart__c = cart.Id,
                    Order_Date__c = System.now(),
                    Order_Status__c = 'pending',
                    Payment_Status__c = 'Pending',
                    Shipping_Address__c = shippingAddress,
                    Shipping_City__c = shippingCity,
                    Shipping_State__c = shippingState,
                    Shipping_Postal_Code__c =
                        shippingPostalCode,
                    Shipping_Country__c =
                        shippingCountry,
                    Subtotal__c = subtotal,
                    Discount_Amount__c = 0,
                    Tax_Amount__c = 0,
                    Shipping_Charges__c = 0
                );

            Database.insert(
                orderRecord,
                true,
                AccessLevel.SYSTEM_MODE
            );

            // ============================================
            // STEP 8: CREATE JEWELLERY ORDER ITEMS
            // ============================================

            List<Jewellery_Order_Item__c> orderItems =
                new List<Jewellery_Order_Item__c>();

            for (Cart_Item__c item : items) {

                orderItems.add(
                    new Jewellery_Order_Item__c(
                        Jewellery_Order__c =
                            orderRecord.Id,
                        Jewellery_Product__c =
                            item.Jewellery_Product__c,
                        Quantity__c =
                            item.Quantity__c,
                        Unit_Price__c =
                            prices.get(
                                item.Jewellery_Product__c
                            ),
                        Discount_Amount__c = 0
                    )
                );
            }

            Database.insert(
                orderItems,
                true,
                AccessLevel.SYSTEM_MODE
            );

            // ============================================
            // STEP 9: RESERVE STOCK
            // ============================================

            for (Id productId : sortedIds) {

                GVInventoryService.reserveStock(
                    productId,
                    quantities.get(productId),
                    orderRecord.Id
                );
            }

            // ============================================
            // STEP 10: VALIDATE SAVED TOTAL
            // ============================================

            Jewellery_Order__c savedOrder = [
                SELECT Id,
                       Name,
                       Grand_Total__c,
                       Order_Status__c,
                       Payment_Status__c
                FROM Jewellery_Order__c
                WHERE Id = :orderRecord.Id
                LIMIT 1
            ];

            Decimal total = subtotal.setScale(2);

            if (
                savedOrder.Grand_Total__c == null ||
                savedOrder.Grand_Total__c != total
            ) {
                throw new CheckoutException(
                    'Order total does not match checkout pricing.'
                );
            }

            // ============================================
            // STEP 11: CREATE PENDING PAYMENT
            // ============================================

            Payment__c payment = new Payment__c(
                Jewellery_Order__c = orderRecord.Id,
                Payment_Amount__c = total,
                Payment_Status__c = 'Pending'
            );

            Database.insert(
                payment,
                true,
                AccessLevel.SYSTEM_MODE
            );

            // ============================================
            // STEP 12: RETURN RESULT
            // ============================================

            CheckoutResult result =
                new CheckoutResult();

            result.orderId = savedOrder.Id;
            result.paymentId = payment.Id;
            result.orderNumber = savedOrder.Name;
            result.grandTotal = total;
            result.orderStatus =
                savedOrder.Order_Status__c;
            result.paymentStatus = 'Pending';
            result.message =
                'Online order prepared. Payment is pending.';

            return result;

        } catch (Exception e) {

            Database.rollback(sp);

            if (
                e instanceof CheckoutException ||
                e instanceof GVInventoryService.InventoryException
            ) {
                throw new AuraHandledException(
                    e.getMessage()
                );
            }

            System.debug(
                LoggingLevel.ERROR,
                'GV ONLINE CHECKOUT ERROR: ' +
                e.getMessage() +
                ' | ' +
                e.getStackTraceString()
            );

            throw new AuraHandledException(
                'Unable to prepare online checkout.'
            );
        }
    }

    // ============================================
    // HELPER
    // ============================================

    private static String clean(String value) {
        return value == null
            ? ''
            : value.trim();
    }
}
