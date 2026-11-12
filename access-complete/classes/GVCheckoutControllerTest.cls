/**
 * GOLDVUEE | CHECKOUT CONTROLLER TESTS
 *
 * Tests:
 * 1. Successful customer checkout
 * 2. Inventory deduction
 * 3. Order item creation
 * 4. Payment status initialization
 * 5. Cart conversion
 * 6. Duplicate checkout prevention
 * 7. Empty cart rejection
 * 8. Insufficient stock rejection
 *
 * Uses SeeAllData=false for isolated test data.
 */
@IsTest
private class GVCheckoutControllerTest {

    // =====================================================
    // TEST DATA HELPERS
    // =====================================================

    private static User createCustomerUser() {

        Profile customerProfile = [
            SELECT Id
            FROM Profile
            WHERE UserType IN ('CSPLitePortal', 'PowerCustomerSuccess')
            LIMIT 1
        ];

        Account accountRecord = new Account(
            Name = 'GoldVuee Test Customer'
        );
        insert accountRecord;

        Contact contactRecord = new Contact(
            FirstName = 'GoldVuee',
            LastName = 'Checkout Test',
            AccountId = accountRecord.Id
        );
        insert contactRecord;

        User runningUser = [
            SELECT Id, UserRoleId
            FROM User
            WHERE Id = :UserInfo.getUserId()
        ];

        // A role is required for the owner of the
        // account associated with an external user.
        // Existing org configuration must provide
        // an appropriate account owner.

        User customer = new User(
            FirstName = 'GoldVuee',
            LastName = 'Customer',
            Alias = 'gvcust',
            Email = 'checkout.test@example.com',
            Username = 'gv.checkout.' +
                String.valueOf(System.now().getTime()) +
                '@example.com',
            CommunityNickname = 'gvcheckout' +
                String.valueOf(System.now().getTime()),
            ProfileId = customerProfile.Id,
            ContactId = contactRecord.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_IN',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );

        insert customer;

        return customer;
    }

    private static Jewellery_Product__c createProduct(
        Decimal stock
    ) {

        Jewellery_Product__c product =
            new Jewellery_Product__c(
                Name = 'GoldVuee Test Necklace',
                Active__c = true,
                Price__c = 10000,
                Discount_Price__c = 9000,
                Stock_Quantity__c = stock
            );

        insert product;

        return product;
    }

    private static Shopping_Cart__c createCart(
        Id contactId
    ) {

        Shopping_Cart__c cart =
            new Shopping_Cart__c(
                Customer__c = contactId,
                Cart_Status__c = 'Active'
            );

        insert cart;

        return cart;
    }

    private static Cart_Item__c createCartItem(
        Id cartId,
        Id productId,
        Decimal quantity
    ) {

        Cart_Item__c item = new Cart_Item__c(
            Shopping_Cart__c = cartId,
            Jewellery_Product__c = productId,
            Quantity__c = quantity,
            Unit_Price__c = 9000
        );

        insert item;

        return item;
    }

    private static GVCheckoutController.CheckoutResult
        checkout() {

        return GVCheckoutController.placeOrder(
            '123 Gold Street',
            'Jabalpur',
            'Madhya Pradesh',
            '482001',
            'India'
        );
    }

    // =====================================================
    // TEST 1: SUCCESSFUL CHECKOUT
    // =====================================================

    @IsTest
    static void testSuccessfulCheckout() {

        User customer = createCustomerUser();

        Jewellery_Product__c product =
            createProduct(10);

        Shopping_Cart__c cart =
            createCart(customer.ContactId);

        createCartItem(cart.Id, product.Id, 2);

        System.runAs(customer) {

            Test.startTest();

            GVCheckoutController.CheckoutResult result =
                checkout();

            Test.stopTest();

            System.assertNotEquals(
                null,
                result.orderId,
                'Checkout must create an order.'
            );

            Jewellery_Order__c orderRecord = [
                SELECT Id,
                       Subtotal__c,
                       Grand_Total__c,
                       Order_Status__c,
                       Payment_Status__c
                FROM Jewellery_Order__c
                WHERE Id = :result.orderId
                LIMIT 1
            ];

            System.assertEquals(
                18000,
                orderRecord.Subtotal__c
            );

            System.assertEquals(
                18000,
                orderRecord.Grand_Total__c
            );

            System.assertEquals(
                'pending',
                orderRecord.Order_Status__c
            );

            System.assertEquals(
                'Pending',
                orderRecord.Payment_Status__c
            );

            List<Jewellery_Order_Item__c> orderItems = [
                SELECT Quantity__c,
                       Unit_Price__c,
                       Line_Total__c
                FROM Jewellery_Order_Item__c
                WHERE Jewellery_Order__c = :result.orderId
            ];

            System.assertEquals(
                1,
                orderItems.size()
            );

            System.assertEquals(
                2,
                orderItems[0].Quantity__c
            );

            System.assertEquals(
                9000,
                orderItems[0].Unit_Price__c
            );

            System.assertEquals(
                18000,
                orderItems[0].Line_Total__c
            );

            Jewellery_Product__c updatedProduct = [
                SELECT Stock_Quantity__c
                FROM Jewellery_Product__c
                WHERE Id = :product.Id
            ];

            System.assertEquals(
                8,
                updatedProduct.Stock_Quantity__c
            );

            Shopping_Cart__c updatedCart = [
                SELECT Cart_Status__c
                FROM Shopping_Cart__c
                WHERE Id = :cart.Id
            ];

            System.assertEquals(
                'Converted',
                updatedCart.Cart_Status__c
            );
        }
    }

    // =====================================================
    // TEST 2: DUPLICATE CHECKOUT
    // =====================================================

    @IsTest
    static void testDuplicateCheckoutRejected() {

        User customer = createCustomerUser();

        Jewellery_Product__c product =
            createProduct(5);

        Shopping_Cart__c cart =
            createCart(customer.ContactId);

        createCartItem(cart.Id, product.Id, 1);

        System.runAs(customer) {

            checkout();

            Boolean rejected = false;

            try {
                checkout();
            } catch (AuraHandledException ex) {
                rejected = true;
            }

            System.assertEquals(
                true,
                rejected,
                'A converted cart must not checkout twice.'
            );
        }
    }

    // =====================================================
    // TEST 3: EMPTY CART
    // =====================================================

    @IsTest
    static void testEmptyCartRejected() {

        User customer = createCustomerUser();

        createCart(customer.ContactId);

        System.runAs(customer) {

            Boolean rejected = false;

            try {
                checkout();
            } catch (AuraHandledException ex) {
                rejected = true;
            }

            System.assertEquals(
                true,
                rejected,
                'An empty cart must be rejected.'
            );
        }
    }

    // =====================================================
    // TEST 4: INSUFFICIENT INVENTORY
    // =====================================================

    @IsTest
    static void testInsufficientStockRejected() {

        User customer = createCustomerUser();

        Jewellery_Product__c product =
            createProduct(1);

        Shopping_Cart__c cart =
            createCart(customer.ContactId);

        createCartItem(cart.Id, product.Id, 3);

        System.runAs(customer) {

            Boolean rejected = false;

            try {
                checkout();
            } catch (AuraHandledException ex) {
                rejected = true;
            }

            System.assertEquals(
                true,
                rejected,
                'Checkout must reject insufficient stock.'
            );

            Integer orderCount = [
                SELECT COUNT()
                FROM Jewellery_Order__c
                WHERE Shopping_Cart__c = :cart.Id
            ];

            System.assertEquals(
                0,
                orderCount,
                'Failed checkout must not create an order.'
            );

            Jewellery_Product__c unchangedProduct = [
                SELECT Stock_Quantity__c
                FROM Jewellery_Product__c
                WHERE Id = :product.Id
            ];

            System.assertEquals(
                1,
                unchangedProduct.Stock_Quantity__c,
                'Failed checkout must not deduct inventory.'
            );
        }
    }
}