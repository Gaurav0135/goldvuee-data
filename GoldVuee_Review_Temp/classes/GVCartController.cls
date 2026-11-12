/**
 * ============================================================
 * GOLDVUEE | SHOPPING CART CONTROLLER
 * ============================================================
 *
 * Used by:
 * - gvProductDetails
 * - gvShoppingCart (upcoming)
 *
 * Features:
 * 1. Identify the logged-in customer's Contact.
 * 2. Find or create an active Shopping Cart.
 * 3. Add jewellery to the cart.
 * 4. Merge quantities for duplicate products.
 * 5. Retrieve cart items and total.
 * 6. Update cart item quantities.
 * 7. Remove items from the cart.
 *
 * Security:
 * - Customer ID comes from the logged-in User.
 * - No customer ID is accepted from the browser.
 * - All cart queries are scoped to the customer.
 * - USER_MODE enforces Salesforce permissions.
 * - Product prices are calculated on the server.
 *
 * ============================================================
 */

public with sharing class GVCartController {

    // ========================================================
    // 1. CART RESPONSE WRAPPER
    // ========================================================
    // Sends the cart and its items to Lightning Web Components.

    public class CartResponse {

        @AuraEnabled
        public Id cartId { get; set; }

        @AuraEnabled
        public Decimal totalAmount { get; set; }

        @AuraEnabled
        public Integer itemCount { get; set; }

        @AuraEnabled
        public List<Cart_Item__c> items { get; set; }

        public CartResponse() {
            totalAmount = 0;
            itemCount = 0;
            items = new List<Cart_Item__c>();
        }
    }


    // ========================================================
    // 2. IDENTIFY THE LOGGED-IN CUSTOMER
    // ========================================================
    // Experience Cloud customer users have a ContactId.
    //
    // Never accept a Contact ID directly from the frontend.
    // This prevents customers from selecting someone else's
    // cart by changing a browser parameter.

    private static Id getCustomerContactId() {

        // This query reads only the current user's ContactId.
        // It does not retrieve another customer's identity.
        User currentUser = [
            SELECT ContactId
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];

        if (currentUser.ContactId == null) {
            throw new AuraHandledException(
                'Please sign in with your GoldVuee customer account.'
            );
        }

        return currentUser.ContactId;
    }


    // ========================================================
    // 3. FIND THE CUSTOMER'S ACTIVE CART
    // ========================================================

    private static Shopping_Cart__c findActiveCart(
        Id customerContactId
    ) {

        List<Shopping_Cart__c> carts = [
            SELECT
                Id,
                Name,
                Customer__c,
                Cart_Status__c,
                Total_Amount__c
            FROM Shopping_Cart__c
            WHERE
                Customer__c = :customerContactId
                AND Cart_Status__c = 'Active'
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 2
        ];

        if (carts.size() > 1) {
            throw new AuraHandledException(
                'Multiple active shopping bags were found. Please contact support.'
            );
        }

        return carts.isEmpty() ? null : carts[0];
    }


    // ========================================================
    // 4. FIND OR CREATE AN ACTIVE CART
    // ========================================================

    private static Shopping_Cart__c getOrCreateCart(
        Id customerContactId
    ) {

        Shopping_Cart__c cart =
            findActiveCart(customerContactId);

        if (cart != null) {
            return cart;
        }

        // Name is Auto Number, so Salesforce generates it.
        Shopping_Cart__c newCart = new Shopping_Cart__c(
            Customer__c = customerContactId,
            Cart_Status__c = 'Active'
        );

        Database.insert(
            newCart,
            AccessLevel.USER_MODE
        );

        return newCart;
    }


    // ========================================================
    // 5. VALIDATE PRODUCT AND STOCK
    // ========================================================
    // Product information is always read from Salesforce.

    private static Jewellery_Product__c getValidProduct(
        Id productId
    ) {

        if (productId == null) {
            throw new AuraHandledException(
                'Please select a jewellery product.'
            );
        }

        List<Jewellery_Product__c> products = [
            SELECT
                Id,
                Name,
                Active__c,
                Price__c,
                Discount_Price__c
            FROM Jewellery_Product__c
            WHERE
                Id = :productId
                AND Active__c = true
            WITH USER_MODE
            LIMIT 1
        ];

        if (products.isEmpty()) {
            throw new AuraHandledException(
                'This jewellery product is unavailable.'
            );
        }

        return products[0];
    }


    // ========================================================
    // PRIVATE INVENTORY AVAILABILITY READ
    // ========================================================
    // Cart availability is advisory only; checkout revalidates with
    // FOR UPDATE locks. This narrow system-mode query keeps internal
    // inventory fields private from the Experience Cloud customer.
    // Call only AFTER getCustomerContactId() and getValidProduct().
    private without sharing class InventoryAvailabilityReader {
        private Decimal available(Id authorizedProductId) {
            if (authorizedProductId == null) return 0;

            List<Jewellery_Product__c> stockRows = [
                SELECT Stock_Quantity__c, Reserved_Quantity__c
                FROM Jewellery_Product__c
                WHERE Id = :authorizedProductId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (stockRows.isEmpty()) return 0;

            Decimal onHand = stockRows[0].Stock_Quantity__c == null
                ? 0 : stockRows[0].Stock_Quantity__c;
            Decimal reserved = stockRows[0].Reserved_Quantity__c == null
                ? 0 : stockRows[0].Reserved_Quantity__c;
            Decimal availableStock = onHand - reserved;
            return availableStock > 0 ? availableStock : 0;
        }
    }

    // ========================================================
    // 6. CALCULATE ACTUAL SELLING PRICE
    // ========================================================
    // The browser never supplies the product price.
    //
    // A valid discount must be:
    // - Greater than zero
    // - Lower than the original price

    private static Decimal getSellingPrice(
        Jewellery_Product__c product
    ) {

        Decimal originalPrice = product.Price__c;
        Decimal discountPrice = product.Discount_Price__c;

        if (
            originalPrice == null ||
            originalPrice <= 0
        ) {
            throw new AuraHandledException(
                'This product does not have a valid price.'
            );
        }

        if (
            discountPrice != null &&
            discountPrice > 0 &&
            discountPrice < originalPrice
        ) {
            return discountPrice;
        }

        return originalPrice;
    }


    // ========================================================
    // 7. VALIDATE REQUESTED QUANTITY
    // ========================================================

    private static void validateQuantity(
        Integer quantity,
        Decimal stockQuantity
    ) {

        if (quantity == null || quantity < 1) {
            throw new AuraHandledException(
                'Quantity must be at least 1.'
            );
        }

        if (
            stockQuantity == null ||
            quantity > stockQuantity
        ) {
            throw new AuraHandledException(
                'Requested quantity exceeds available stock.'
            );
        }
    }


    // ========================================================
    // 8. ADD PRODUCT TO CART
    // ========================================================
    //
    // If the product is already in the cart:
    // Increase its quantity.
    //
    // Otherwise:
    // Create a new Cart Item.
    //
    // Return the updated cart for immediate UI refresh.

    @AuraEnabled
    public static CartResponse addToCart(
        Id productId,
        Integer quantity
    ) {

        // Step 1: Identify customer.
        Id customerId = getCustomerContactId();

        // Step 2: Validate product.
        Jewellery_Product__c product =
            getValidProduct(productId);

        // Step 3: Validate available quantity (physical minus reserved).
        Decimal availableStock =
            (new InventoryAvailabilityReader()).available(product.Id);
        validateQuantity(quantity, availableStock);

        // Step 4: Calculate Salesforce selling price.
        Decimal sellingPrice =
            getSellingPrice(product);

        // Step 5: Find or create customer's cart.
        Shopping_Cart__c cart =
            getOrCreateCart(customerId);

        // Step 6: Check whether product already exists.
        List<Cart_Item__c> existingItems = [
            SELECT
                Id,
                Quantity__c,
                Jewellery_Product__c
            FROM Cart_Item__c
            WHERE
                Shopping_Cart__c = :cart.Id
                AND Jewellery_Product__c = :productId
            WITH USER_MODE
            LIMIT 1
        ];

        if (!existingItems.isEmpty()) {

            // Product already exists: increase quantity.
            Cart_Item__c existingItem =
                existingItems[0];

            Integer newQuantity =
                Integer.valueOf(existingItem.Quantity__c)
                + quantity;

            validateQuantity(newQuantity, availableStock);

            existingItem.Quantity__c = newQuantity;

            // Refresh the price using current Salesforce data.
            existingItem.Unit_Price__c = sellingPrice;

            Database.update(
                existingItem,
                AccessLevel.USER_MODE
            );

        } else {

            // Product is not in the cart: create item.
            Cart_Item__c newItem = new Cart_Item__c(
                Shopping_Cart__c = cart.Id,
                Jewellery_Product__c = productId,
                Quantity__c = quantity,
                Unit_Price__c = sellingPrice
            );

            Database.insert(
                newItem,
                AccessLevel.USER_MODE
            );
        }

        // Return the updated cart.
        return getCart();
    }


    // ========================================================
    // 9. GET CUSTOMER'S CART
    // ========================================================
    //
    // This method is read-only.
    // It does not create a cart if none exists.
    //
    // Returns:
    // - Cart ID
    // - Cart total
    // - Total quantity of items
    // - Cart item records

    @AuraEnabled
    public static CartResponse getCart() {

        Id customerId = getCustomerContactId();

        CartResponse response = new CartResponse();

        Shopping_Cart__c cart =
            findActiveCart(customerId);

        // A customer may not have created a cart yet.
        if (cart == null) {
            return response;
        }

        response.cartId = cart.Id;

        response.totalAmount =
            cart.Total_Amount__c == null
                ? 0
                : cart.Total_Amount__c;

        response.items = [
            SELECT
                Id,
                Name,
                Shopping_Cart__c,
                Jewellery_Product__c,
                Jewellery_Product__r.Name,
                Jewellery_Product__r.Main_Image_URL__c,
                Quantity__c,
                Unit_Price__c,
                Line_Total__c
            FROM Cart_Item__c
            WHERE
                Shopping_Cart__c = :cart.Id
            WITH USER_MODE
            ORDER BY CreatedDate ASC
        ];

        Integer totalQuantity = 0;

        for (Cart_Item__c item : response.items) {
            totalQuantity +=
                Integer.valueOf(item.Quantity__c);
        }

        response.itemCount = totalQuantity;

        return response;
    }


    // ========================================================
    // 10. UPDATE CART ITEM QUANTITY
    // ========================================================

    
    // ========================================================
    // 10. UPDATE CART ITEM QUANTITY
    // ========================================================
    // Security:
    // - Identify the logged-in customer.
    // - Verify that the cart item belongs to that customer.
    // - Validate the requested quantity against stock.
    // - Recalculate the selling price on the server.
    // - Update only the necessary fields.
    // ========================================================

    @AuraEnabled
    public static CartResponse updateCartItem(
        Id cartItemId,
        Integer quantity
    ) {

        // STEP 1: Identify the logged-in customer.
        Id customerId = getCustomerContactId();

        // STEP 2: Validate input.
        if (cartItemId == null) {
            throw new AuraHandledException(
                'A valid cart item is required.'
            );
        }

        if (quantity == null || quantity < 1) {
            throw new AuraHandledException(
                'Quantity must be at least 1.'
            );
        }

        // STEP 3: Find only an item from this customer's
        // active shopping cart.
        List<Cart_Item__c> items = [
            SELECT
                Id,
                Jewellery_Product__c
            FROM Cart_Item__c
            WHERE
                Id = :cartItemId
                AND Shopping_Cart__r.Customer__c = :customerId
                AND Shopping_Cart__r.Cart_Status__c = 'Active'
            WITH USER_MODE
            LIMIT 1
        ];

        if (items.isEmpty()) {
            throw new AuraHandledException(
                'Cart item not found or access denied.'
            );
        }

        // STEP 4: Get product from Salesforce.
        Jewellery_Product__c product =
            getValidProduct(
                items[0].Jewellery_Product__c
            );

        // STEP 5: Check current inventory.
        validateQuantity(
            quantity,
            (new InventoryAvailabilityReader()).available(product.Id)
        );

        // STEP 6: Calculate the current selling price.
        Decimal sellingPrice =
            getSellingPrice(product);

        // STEP 7: Create a minimal update record.
        // This avoids including fields retrieved by SOQL
        // that are not intended to be updated.
        Cart_Item__c itemToUpdate = new Cart_Item__c(
            Id = cartItemId,
            Quantity__c = quantity,
            Unit_Price__c = sellingPrice
        );

        // STEP 8: Save using customer permissions.
        // USER_MODE enforces object and field security.
        try {

            Database.update(
                itemToUpdate,
                AccessLevel.USER_MODE
            );

        } catch (DmlException e) {

            throw new AuraHandledException(
                'Unable to update cart quantity. ' +
                'Please verify Cart Item Edit permission ' +
                'and field access for Quantity and Unit Price.'
            );

        }

        // STEP 9: Return refreshed cart and totals.
        return getCart();
    }



    // ========================================================
    // 11. REMOVE CART ITEM
    // ========================================================

    @AuraEnabled
    public static CartResponse removeCartItem(
        Id cartItemId
    ) {

        Id customerId = getCustomerContactId();

        if (cartItemId == null) {
            throw new AuraHandledException(
                'A valid cart item is required.'
            );
        }

        // Only allow removal from the current customer's cart.
        List<Cart_Item__c> items = [
            SELECT Id
            FROM Cart_Item__c
            WHERE
                Id = :cartItemId
                AND Shopping_Cart__r.Customer__c = :customerId
                AND Shopping_Cart__r.Cart_Status__c = 'Active'
            WITH USER_MODE
            LIMIT 1
        ];

        if (items.isEmpty()) {
            throw new AuraHandledException(
                'Cart item not found.'
            );
        }

        Database.delete(
            items[0],
            AccessLevel.USER_MODE
        );

        return getCart();
    }
}