@IsTest
private class GVPaymentFinalizationTest {

    // ============================================
    // RAZORPAY TEST REFERENCES
    // ============================================

    private static final String TEST_ORDER_ID =
        'order_GVFinalTest123';

    private static final String TEST_PAYMENT_ID =
        'pay_GVFinalTest123';

    // ============================================
    // 1. MOCK RAZORPAY CAPTURED PAYMENT
    // ============================================

    private class CapturedPaymentMock
        implements HttpCalloutMock {

        public HttpResponse respond(HttpRequest req) {

            System.assertEquals(
                'GET',
                req.getMethod()
            );

            System.assert(
                req.getEndpoint().contains(
                    '/v1/payments/' + TEST_PAYMENT_ID
                ),
                'Unexpected Razorpay API endpoint.'
            );

            HttpResponse res = new HttpResponse();

            res.setStatusCode(200);
            res.setHeader(
                'Content-Type',
                'application/json'
            );

            res.setBody(JSON.serialize(
                new Map<String, Object>{
                    'id' => TEST_PAYMENT_ID,
                    'order_id' => TEST_ORDER_ID,
                    'amount' => 100000,
                    'currency' => 'INR',
                    'status' => 'captured',
                    'captured' => true,
                    'method' => 'upi'
                }
            ));

            return res;
        }
    }

    // ============================================
    // 2. CREATE EXPERIENCE CLOUD CUSTOMER
    // ============================================

    private static User createCustomer() {

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

    // ============================================
    // 3. MAIN PAYMENT FINALIZATION TEST
    // ============================================

    @IsTest
    static void testCapturedPaymentAndDuplicate() {

        // STEP 1: CREATE CUSTOMER
        // Separate setup-object DML using runAs.

        User customer;

        System.runAs(
            new User(Id = UserInfo.getUserId())
        ) {
            customer = createCustomer();
        }

        Id contactId = [
            SELECT ContactId
            FROM User
            WHERE Id = :customer.Id
            LIMIT 1
        ].ContactId;

        System.assertNotEquals(
            null,
            contactId,
            'Customer must have a Contact.'
        );

        // ========================================
        // STEP 2: CREATE JEWELLERY CATEGORY
        // ========================================

        Jewellery_Category__c category =
            new Jewellery_Category__c(
                Name = 'GoldVuee Test Rings',
                Active__c = true
            );

        Database.insert(
            category,
            true,
            AccessLevel.SYSTEM_MODE
        );

        // ========================================
        // STEP 3: CREATE VALID TEST PRODUCT
        // ========================================

        Jewellery_Product__c product =
            new Jewellery_Product__c(
                Name = 'GoldVuee Test Ring',

                // REQUIRED PRODUCT FIELDS
                Product_Code__c = 'GV-TEST-RING-001',
                SKU__c = 'GV-TEST-SKU-001',
                Weight__c = 5,
                Category__c = category.Id,

                // PRICING
                Price__c = 1000,
                Active__c = true,

                // INVENTORY
                Stock_Quantity__c = 10,
                Reserved_Quantity__c = 0
            );

        Database.insert(
            product,
            true,
            AccessLevel.SYSTEM_MODE
        );

        // ========================================
        // STEP 4: CREATE SHOPPING CART
        // ========================================

        Shopping_Cart__c cart =
            new Shopping_Cart__c(
                Customer__c = contactId,
                Cart_Status__c = 'Active'
            );


        Database.insert(
            cart,
            true,
            AccessLevel.SYSTEM_MODE
        );

        // ========================================
        // STEP 5: CREATE PENDING ORDER
        // ========================================

        Jewellery_Order__c orderRecord =
            new Jewellery_Order__c(
                Customer__c = contactId,
                Shopping_Cart__c = cart.Id,

                Order_Date__c = System.now(),
                Order_Status__c = 'pending',
                Payment_Status__c = 'Pending',

                Subtotal__c = 1000,
                Discount_Amount__c = 0,
                Tax_Amount__c = 0,
                Shipping_Charges__c = 0,

                Shipping_Address__c =
                    '123 GoldVuee Test Street',
                Shipping_City__c = 'Indore',
                Shipping_State__c = 'Madhya Pradesh',
                Shipping_Postal_Code__c = '452001',
                Shipping_Country__c = 'India'
            );

        Database.insert(
            orderRecord,
            true,
            AccessLevel.SYSTEM_MODE
        );

        // ========================================
        // STEP 6: CREATE ORDER ITEM
        // ========================================

        Jewellery_Order_Item__c orderItem =
            new Jewellery_Order_Item__c(
                Jewellery_Order__c = orderRecord.Id,
                Jewellery_Product__c = product.Id,
                Quantity__c = 1,
                Unit_Price__c = 1000,
                Discount_Amount__c = 0
            );

        Database.insert(
            orderItem,
            true,
            AccessLevel.SYSTEM_MODE
        );

        // ========================================
        // STEP 7: RESERVE INVENTORY
        // ========================================

        Id reservationId =
            GVInventoryService.reserveStock(
                product.Id,
                1,
                orderRecord.Id
            );

        System.assertNotEquals(
            null,
            reservationId,
            'Reservation must be created.'
        );

        Jewellery_Product__c beforePayment = [
            SELECT Stock_Quantity__c,
                   Reserved_Quantity__c
            FROM Jewellery_Product__c
            WHERE Id = :product.Id
        ];

        System.assertEquals(
            10,
            beforePayment.Stock_Quantity__c,
            'Physical stock must remain unchanged.'
        );

        System.assertEquals(
            1,
            beforePayment.Reserved_Quantity__c,
            'One item must be reserved.'
        );

        // ========================================
        // STEP 8: CREATE PENDING PAYMENT
        // ========================================

        Payment__c payment = new Payment__c(
            Jewellery_Order__c = orderRecord.Id,
            Payment_Amount__c = 1000,
            Payment_Status__c = 'Pending',
            Razorpay_Order_ID__c = TEST_ORDER_ID
        );

        Database.insert(
            payment,
            true,
            AccessLevel.SYSTEM_MODE
        );

        // ========================================
        // STEP 9: CONFIGURE MOCK RAZORPAY API
        // ========================================

        Test.setMock(
            HttpCalloutMock.class,
            new CapturedPaymentMock()
        );

        // ========================================
        // STEP 10: VERIFY PAYMENT AS CUSTOMER
        // ========================================

        System.runAs(customer) {

            Test.startTest();

            GVPaymentVerificationController.VerificationResult
                result =
                GVPaymentVerificationController.verifyPayment(
                    payment.Id,
                    TEST_PAYMENT_ID
                );

            System.assertEquals(
                true,
                result.success,
                'Payment should be verified.'
            );

            System.assertEquals(
                'Paid',
                result.paymentStatus
            );

            System.assertEquals(
                'Confirmed',
                result.orderStatus
            );

            // ====================================
            // STEP 11: TEST DUPLICATE VERIFICATION
            // ====================================

            GVPaymentVerificationController.VerificationResult
                duplicateResult =
                GVPaymentVerificationController.verifyPayment(
                    payment.Id,
                    TEST_PAYMENT_ID
                );

            System.assertEquals(
                true,
                duplicateResult.success,
                'Duplicate verification must be safe.'
            );

            Test.stopTest();
        }

        // ========================================
        // STEP 12: CHECK PAYMENT RECORD
        // ========================================

        Payment__c savedPayment = [
            SELECT Payment_Status__c,
                   Payment_Method__c,
                   Transaction_ID__c,
                   Payment_Date__c
            FROM Payment__c
            WHERE Id = :payment.Id
        ];

        System.assertEquals(
            'Success',
            savedPayment.Payment_Status__c
        );

        System.assertEquals(
            'UPI',
            savedPayment.Payment_Method__c
        );

        System.assertEquals(
            TEST_PAYMENT_ID,
            savedPayment.Transaction_ID__c
        );

        System.assertNotEquals(
            null,
            savedPayment.Payment_Date__c
        );

        // ========================================
        // STEP 13: CHECK ORDER
        // ========================================

        Jewellery_Order__c savedOrder = [
            SELECT Order_Status__c,
                   Payment_Status__c,
                   Grand_Total__c
            FROM Jewellery_Order__c
            WHERE Id = :orderRecord.Id
        ];

        System.assertEquals(
            'Confirmed',
            savedOrder.Order_Status__c
        );

        System.assertEquals(
            'Paid',
            savedOrder.Payment_Status__c
        );

        System.assertEquals(
            1000,
            savedOrder.Grand_Total__c,
            'Order total must be correct.'
        );

        // ========================================
        // STEP 14: VERIFY PHYSICAL INVENTORY
        // ========================================

        Jewellery_Product__c savedProduct = [
            SELECT Stock_Quantity__c,
                   Reserved_Quantity__c
            FROM Jewellery_Product__c
            WHERE Id = :product.Id
        ];

        System.assertEquals(
            9,
            savedProduct.Stock_Quantity__c,
            'Physical inventory must decrease once.'
        );

        System.assertEquals(
            0,
            savedProduct.Reserved_Quantity__c,
            'Reserved quantity must be cleared.'
        );

        // ========================================
        // STEP 15: VERIFY RESERVATION STATUS
        // ========================================

        Stock_Reservation__c savedReservation = [
            SELECT Reservation_Status__c
            FROM Stock_Reservation__c
            WHERE Id = :reservationId
        ];

        System.assertEquals(
            'Committed',
            savedReservation.Reservation_Status__c
        );

        // ========================================
        // STEP 16: VERIFY CART CONVERSION
        // ========================================

        Shopping_Cart__c savedCart = [
            SELECT Cart_Status__c
            FROM Shopping_Cart__c
            WHERE Id = :cart.Id
        ];

        System.assertEquals(
            'Converted',
            savedCart.Cart_Status__c
        );

        // ========================================
        // STEP 17: VERIFY NO DOUBLE DEDUCTION
        // ========================================

        Integer movementCount = [
            SELECT COUNT()
            FROM Inventory_Movement__c
            WHERE Jewellery_Order__c = :orderRecord.Id
            AND Movement_Type__c = 'Sale'
        ];

        System.assertEquals(
            1,
            movementCount,
            'Inventory must be deducted exactly once.'
        );
    }
}