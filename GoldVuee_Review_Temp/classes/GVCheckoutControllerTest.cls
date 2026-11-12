
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

        String uniqueKey = String.valueOf(
            Crypto.getRandomLong()
        ).replace('-', '');

        UserRole ownerRole = new UserRole(
            Name = 'GV Test Owner Role',
            DeveloperName = 'GV_Test_Owner_Role'
        );

        insert ownerRole;

        User owner = new User(
            ProfileId = UserInfo.getProfileId(),
            UserRoleId = ownerRole.Id,
            FirstName = 'GoldVuee',
            LastName = 'TestOwner',
            Alias = 'gvowner',
            Email = 'owner@example.com',
            Username = 'gvowner' + uniqueKey +
                '@example.com',
            CommunityNickname = 'gvowner' + uniqueKey,
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );

        insert owner;

        List<Profile> profiles = [
            SELECT Id, Name
            FROM Profile
            WHERE UserType IN (
                'CSPLitePortal',
                'CustomerSuccess',
                'PowerCustomerSuccess'
            )
            AND Name LIKE '%GoldVuee%'
            LIMIT 1
        ];

        System.assert(
            !profiles.isEmpty(),
            'GoldVuee Customer Profile not found.'
        );

        User customer;

        System.runAs(owner) {

            Account account = new Account(
                Name = 'GoldVuee Test Account'
            );

            insert account;

            Contact contact = new Contact(
                FirstName = 'GoldVuee',
                LastName = 'TestCustomer',
                AccountId = account.Id
            );

            insert contact;

            customer = new User(
                ProfileId = profiles[0].Id,
                ContactId = contact.Id,
                FirstName = 'GoldVuee',
                LastName = 'TestCustomer',
                Alias = 'gvtest',
                Email = 'customer@example.com',
                Username = 'gvcustomer' + uniqueKey +
                    '@example.com',
                CommunityNickname =
                    'gvcustomer' + uniqueKey,
                TimeZoneSidKey = 'Asia/Kolkata',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US'
            );

            insert customer;
        }

        return customer;
    }

    private static Jewellery_Product__c createProduct(
        Decimal stock
    ) {

        // Active jewellery requires a category, SKU, code and weight.
        // Match the actual Jewellery_Product__c required-field metadata
        // and GV_Product_Business_Validation rule.
        Jewellery_Category__c category =
            new Jewellery_Category__c(
                Name = 'GoldVuee COD Test Category',
                Active__c = true
            );
        insert category;

        Jewellery_Product__c product =
            new Jewellery_Product__c(
                Name = 'GoldVuee Test Necklace',
                Product_Code__c = 'GV-COD-TEST-001',
                SKU__c = 'GV-COD-SKU-001',
                Category__c = category.Id,
                Weight__c = 10.000,
                Active__c = true,
                Price__c = 10000,
                Discount_Price__c = 9000,
                Stock_Quantity__c = stock,
                Reserved_Quantity__c = 0
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
                'Confirmed',
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

            System.assertEquals(
                1,
                [SELECT COUNT()
                 FROM Inventory_Movement__c
                 WHERE Jewellery_Order__c = :result.orderId
                   AND Movement_Type__c = 'Sale'],
                'COD checkout should create exactly one sale movement.'
            );

            System.assertEquals(
                1,
                [SELECT COUNT()
                 FROM Stock_Reservation__c
                 WHERE Jewellery_Order__c = :result.orderId
                   AND Reservation_Status__c = 'Committed'],
                'COD reservation must be committed once.'
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
