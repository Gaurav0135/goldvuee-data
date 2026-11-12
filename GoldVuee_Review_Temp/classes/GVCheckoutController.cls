
/**
 * GOLDVUEE | CASH ON DELIVERY CHECKOUT
 *
 * Creates:
 * 1. Confirmed COD order
 * 2. Order items
 * 3. Inventory reservations and sale movements
 * 4. Converted shopping cart
 *
 * Payment remains Pending until cash is collected.
 *
 * Requires GVInventoryService with:
 * reserveStock() and commitReservation().
 */
public with sharing class GVCheckoutController {

    public class CheckoutException extends Exception {}

    public class CheckoutResult {
        @AuraEnabled public Id orderId;
        @AuraEnabled public String orderNumber;
        @AuraEnabled public Decimal grandTotal;
        @AuraEnabled public String orderStatus;
        @AuraEnabled public String paymentStatus;
        @AuraEnabled public String paymentMethod;
        @AuraEnabled public String message;
    }

    @AuraEnabled
    public static CheckoutResult placeOrder(
        String shippingAddress,
        String shippingCity,
        String shippingState,
        String shippingPostalCode,
        String shippingCountry
    ) {
        String stage = 'START';
        Savepoint sp = Database.setSavepoint();

        try {

            // ============================================
            // STEP 1: IDENTIFY CUSTOMER
            // ============================================

            stage = 'CUSTOMER LOOKUP';

            Id currentUserId = UserInfo.getUserId();

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
                throw new CheckoutException(
                    'Please sign in to your GoldVuee customer account.'
                );
            }

            Id contactId = users[0].ContactId;

            // ============================================
            // STEP 2: VALIDATE SHIPPING
            // ============================================

            stage = 'SHIPPING VALIDATION';

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
                    'Enter a valid Indian address and six-digit PIN code.'
                );
            }

            // ============================================
            // STEP 3: FIND CUSTOMER CART
            // ============================================

            stage = 'CART LOOKUP';

            List<Shopping_Cart__c> carts = [
                SELECT Id, Customer__c, Cart_Status__c
                FROM Shopping_Cart__c
                WHERE Customer__c = :contactId
                AND Cart_Status__c = 'Active'
                LIMIT 2
                FOR UPDATE
            ];

            if (carts.size() != 1) {
                throw new CheckoutException(
                    'Expected one active shopping bag. Please refresh your cart.'
                );
            }

            Shopping_Cart__c cart = carts[0];

            // Recover an expired, never-initialized Razorpay checkout safely.
            // If Razorpay initialized or the hold is still live, keep it intact.
            GVAbandonedCheckoutService.recoverExpiredCheckout(
                cart.Id, contactId
            );

            // ============================================
            // STEP 4: PREVENT DUPLICATE ORDERS
            // ============================================

            stage = 'DUPLICATE ORDER CHECK';

            List<Jewellery_Order__c> existing = [
                SELECT Id,
                       Name,
                       Grand_Total__c,
                       Order_Status__c,
                       Payment_Status__c,
                       Customer__c
                FROM Jewellery_Order__c
                WHERE Shopping_Cart__c = :cart.Id
                AND Order_Status__c NOT IN ('Cancelled', 'Canceled', 'Abandoned')
                LIMIT 1
            ];

            if (!existing.isEmpty()) {

                Jewellery_Order__c previous = existing[0];

                if (
                    previous.Customer__c == contactId &&
                    previous.Order_Status__c == 'Confirmed' &&
                    previous.Payment_Status__c == 'Pending'
                ) {
                    return buildResult(
                        previous,
                        'This COD order has already been confirmed.'
                    );
                }

                throw new CheckoutException(
                    'An order already exists for this shopping bag.'
                );
            }

            // ============================================
            // STEP 5: LOAD CART ITEMS
            // ============================================

            stage = 'CART ITEMS LOOKUP';

            List<Cart_Item__c> items = [
                SELECT Id,
                       Jewellery_Product__c,
                       Quantity__c
                FROM Cart_Item__c
                WHERE Shopping_Cart__c = :cart.Id
                ORDER BY Id
            ];

            if (items.isEmpty()) {
                throw new CheckoutException(
                    'Your shopping bag is empty.'
                );
            }

            Set<Id> productIds = new Set<Id>();

            Map<Id, Decimal> requestedQuantities =
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
                        'The shopping bag contains an invalid item.'
                    );
                }

                Id productId = item.Jewellery_Product__c;

                productIds.add(productId);

                Decimal previousQty =
                    requestedQuantities.containsKey(productId)
                    ? requestedQuantities.get(productId)
                    : 0;

                requestedQuantities.put(
                    productId,
                    previousQty + qty
                );
            }

            // ============================================
            // STEP 6: VALIDATE PRODUCTS AND STOCK
            // ============================================

            stage = 'PRODUCT VALIDATION';

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

            if (products.size() != productIds.size()) {
                throw new CheckoutException(
                    'One or more jewellery products are unavailable.'
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

                Decimal qty =
                    requestedQuantities.get(productId);

                Decimal stock =
                    product.Stock_Quantity__c == null
                    ? 0
                    : product.Stock_Quantity__c;

                Decimal reserved =
                    product.Reserved_Quantity__c == null
                    ? 0
                    : product.Reserved_Quantity__c;

                if (product.Active__c != true) {
                    throw new CheckoutException(
                        product.Name + ' is unavailable.'
                    );
                }

                if (stock - reserved < qty) {
                    throw new CheckoutException(
                        'Insufficient available stock for ' +
                        product.Name + '.'
                    );
                }

                if (
                    product.Price__c == null ||
                    product.Price__c <= 0
                ) {
                    throw new CheckoutException(
                        'Invalid selling price for ' +
                        product.Name + '.'
                    );
                }

                Decimal sellingPrice =
                    product.Price__c;

                if (
                    product.Discount_Price__c != null &&
                    product.Discount_Price__c > 0 &&
                    product.Discount_Price__c < sellingPrice
                ) {
                    sellingPrice =
                        product.Discount_Price__c;
                }

                prices.put(productId, sellingPrice);

                subtotal += sellingPrice * qty;
            }

            if (subtotal <= 0) {
                throw new CheckoutException(
                    'Invalid order amount.'
                );
            }

            // ============================================
            // STEP 7: CREATE CONFIRMED COD ORDER
            // ============================================

            stage = 'ORDER INSERT';

            Jewellery_Order__c orderRecord =
                new Jewellery_Order__c(
                    Customer__c = contactId,
                    Shopping_Cart__c = cart.Id,
                    Order_Date__c = System.now(),
                    Order_Status__c = 'Confirmed',
                    Payment_Status__c = 'Pending',
                    Shipping_Address__c = shippingAddress,
                    Shipping_City__c = shippingCity,
                    Shipping_State__c = shippingState,
                    Shipping_Postal_Code__c = shippingPostalCode,
                    Shipping_Country__c = shippingCountry,
                    Subtotal__c = subtotal,
                    Discount_Amount__c = 0,
                    Tax_Amount__c = 0,
                    Shipping_Charges__c = 0
                );

            // Save COD payment method when the
            // field exists on Jewellery_Order__c.

            Map<String, Schema.SObjectField> orderFields =
                Jewellery_Order__c.SObjectType
                    .getDescribe()
                    .fields.getMap();

            if (
                orderFields.containsKey('Payment_Method__c') &&
                orderFields.get('Payment_Method__c')
                    .getDescribe().isCreateable()
            ) {
                orderRecord.put(
                    'Payment_Method__c',
                    'COD'
                );
            }

            Database.insert(
                orderRecord,
                true,
                AccessLevel.SYSTEM_MODE
            );

            // ============================================
            // STEP 8: CREATE ORDER ITEMS
            // ============================================

            stage = 'ORDER ITEMS INSERT';

            List<Jewellery_Order_Item__c> orderItems =
                new List<Jewellery_Order_Item__c>();

            for (Cart_Item__c item : items) {

                orderItems.add(
                    new Jewellery_Order_Item__c(
                        Jewellery_Order__c = orderRecord.Id,
                        Jewellery_Product__c =
                            item.Jewellery_Product__c,
                        Quantity__c = item.Quantity__c,
                        Unit_Price__c =
                            prices.get(item.Jewellery_Product__c),
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
            // STEP 9: RESERVE AND COMMIT INVENTORY
            // ============================================

            stage = 'INVENTORY COMMIT';

            for (Id productId : sortedIds) {

                Id reservationId =
                    GVInventoryService.reserveStock(
                        productId,
                        requestedQuantities.get(productId),
                        orderRecord.Id
                    );

                GVInventoryService.commitReservation(
                    reservationId
                );
            }

            // ============================================
            // STEP 10: CONVERT SHOPPING CART
            // ============================================

            stage = 'CART CONVERSION';

            Database.update(
                new Shopping_Cart__c(
                    Id = cart.Id,
                    Cart_Status__c = 'Converted'
                ),
                true,
                AccessLevel.SYSTEM_MODE
            );

            // ============================================
            // STEP 11: RETURN ORDER CONFIRMATION
            // ============================================

            stage = 'ORDER CONFIRMATION';

            Jewellery_Order__c saved = [
                SELECT Id,
                       Name,
                       Grand_Total__c,
                       Order_Status__c,
                       Payment_Status__c,
                       Customer__c
                FROM Jewellery_Order__c
                WHERE Id = :orderRecord.Id
                LIMIT 1
            ];

            return buildResult(
                saved,
                'Your Cash on Delivery order was confirmed successfully.'
            );

        } catch (Exception e) {

            Database.rollback(sp);

            System.debug(
                LoggingLevel.ERROR,
                'GV COD CHECKOUT FAILED | Stage=' + stage +
                ' | Type=' + e.getTypeName() +
                ' | Message=' + e.getMessage() +
                ' | Stack=' + e.getStackTraceString()
            );

            if (
                e instanceof CheckoutException ||
                e instanceof GVInventoryService.InventoryException
            ) {
                throw new AuraHandledException(
                    e.getMessage()
                );
            }

            // Detailed diagnostics stay in the server debug log.
            // Do not return exception types, query details or data to guests.
            throw new AuraHandledException(
                'Unable to place your order. Please try again or contact support.'
            );
        }
    }

    // ================================================
    // RESULT HELPER
    // ================================================

    private static CheckoutResult buildResult(
        Jewellery_Order__c orderRecord,
        String message
    ) {
        CheckoutResult result = new CheckoutResult();

        result.orderId = orderRecord.Id;
        result.orderNumber = orderRecord.Name;
        result.grandTotal = orderRecord.Grand_Total__c;
        result.orderStatus = orderRecord.Order_Status__c;
        result.paymentStatus = orderRecord.Payment_Status__c;
        result.paymentMethod = 'COD';
        result.message = message;

        return result;
    }

    private static String clean(String input) {
        return input == null ? '' : input.trim();
    }
}
