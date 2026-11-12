
/**
 * GOLDVUEE | RAZORPAY PAYMENT TESTS
 *
 * Tests:
 * 1. Successful Razorpay order creation
 * 2. Successful payment lookup
 * 3. Uncaptured payment lookup
 * 4. Invalid amount
 * 5. Invalid payment ID
 * 6. Invalid verification request
 * 7. Razorpay API failure
 *
 * Uses HttpCalloutMock.
 * No real Razorpay transactions occur.
 */
@IsTest
private class GVPaymentVerificationControllerTest {

    // ==========================================
    // MOCK RAZORPAY API
    // ==========================================

    private class RazorpayMock implements HttpCalloutMock {

        private Integer statusCode;
        private String paymentStatus;
        private Boolean captured;

        RazorpayMock(
            Integer code,
            String status,
            Boolean isCaptured
        ) {
            statusCode = code;
            paymentStatus = status;
            captured = isCaptured;
        }

        public HttpResponse respond(HttpRequest req) {

            HttpResponse res = new HttpResponse();

            res.setStatusCode(statusCode);
            res.setHeader(
                'Content-Type',
                'application/json'
            );

            // MOCK CREATE ORDER
            if (
                req.getMethod() == 'POST' &&
                req.getEndpoint().endsWith('/v1/orders')
            ) {
                Map<String, Object> requestData =
                    (Map<String, Object>)
                    JSON.deserializeUntyped(
                        req.getBody()
                    );

                if (statusCode != 200 &&
                    statusCode != 201) {

                    res.setBody(
                        '{"error":{"description":"Test API error"}}'
                    );
                    return res;
                }

                res.setBody(JSON.serialize(
                    new Map<String, Object>{
                        'id' => 'order_GVTest123456',
                        'entity' => 'order',
                        'amount' => requestData.get('amount'),
                        'currency' => 'INR',
                        'status' => 'created',
                        'receipt' => requestData.get('receipt')
                    }
                ));

                return res;
            }

            // MOCK FETCH PAYMENT
            if (
                req.getMethod() == 'GET' &&
                req.getEndpoint().contains('/v1/payments/')
            ) {

                if (statusCode != 200) {
                    res.setBody(
                        '{"error":{"description":"Payment unavailable"}}'
                    );
                    return res;
                }

                res.setBody(JSON.serialize(
                    new Map<String, Object>{
                        'id' => 'pay_GVTest123456',
                        'entity' => 'payment',
                        'order_id' => 'order_GVTest123456',
                        'amount' => 100000,
                        'currency' => 'INR',
                        'status' => paymentStatus,
                        'method' => 'upi',
                        'captured' => captured
                    }
                ));

                return res;
            }

            res.setStatusCode(404);
            res.setBody('{}');

            return res;
        }
    }

    // ==========================================
    // TEST 1: CREATE RAZORPAY ORDER
    // ==========================================

    @IsTest
    static void testCreateRazorpayOrder() {

        Test.setMock(
            HttpCalloutMock.class,
            new RazorpayMock(
                200,
                'captured',
                true
            )
        );

        Test.startTest();

        GVRazorpayService.RazorpayOrder result =
            GVRazorpayService.createOrder(
                1000.00,
                'GVTEST001'
            );

        Test.stopTest();

        System.assertEquals(
            'order_GVTest123456',
            result.razorpayOrderId
        );

        System.assertEquals(
            100000L,
            result.amountPaise
        );

        System.assertEquals(
            'INR',
            result.currencyCode
        );

        System.assertEquals(
            'created',
            result.status
        );

        System.assertEquals(
            'GVTEST001',
            result.receipt
        );
    }

    // ==========================================
    // TEST 2: FETCH CAPTURED PAYMENT
    // ==========================================

    @IsTest
    static void testFetchCapturedPayment() {

        Test.setMock(
            HttpCalloutMock.class,
            new RazorpayMock(
                200,
                'captured',
                true
            )
        );

        Test.startTest();

        GVRazorpayService.RazorpayPaymentDetails result =
            GVRazorpayService.fetchPayment(
                'pay_GVTest123456'
            );

        Test.stopTest();

        System.assertEquals(
            'pay_GVTest123456',
            result.paymentId
        );

        System.assertEquals(
            'order_GVTest123456',
            result.orderId
        );

        System.assertEquals(
            100000L,
            result.amountPaise
        );

        System.assertEquals(
            'captured',
            result.paymentStatus
        );

        System.assertEquals(
            true,
            result.captured
        );

        System.assertEquals(
            'upi',
            result.paymentMethod
        );
    }

    // ==========================================
    // TEST 3: UNCATURED PAYMENT
    // ==========================================

    @IsTest
    static void testUncapturedPayment() {

        Test.setMock(
            HttpCalloutMock.class,
            new RazorpayMock(
                200,
                'authorized',
                false
            )
        );

        Test.startTest();

        GVRazorpayService.RazorpayPaymentDetails result =
            GVRazorpayService.fetchPayment(
                'pay_GVTest123456'
            );

        Test.stopTest();

        System.assertEquals(
            'authorized',
            result.paymentStatus
        );

        System.assertEquals(
            false,
            result.captured
        );
    }

    // ==========================================
    // TEST 4: REJECT INVALID AMOUNT
    // ==========================================

    @IsTest
    static void testInvalidAmount() {

        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            GVRazorpayService.createOrder(
                0,
                'GVTEST002'
            );

        } catch (GVRazorpayService.RazorpayException e) {
            exceptionThrown = true;
        }

        Test.stopTest();

        System.assertEquals(
            true,
            exceptionThrown,
            'Zero amount must be rejected.'
        );
    }

    // ==========================================
    // TEST 5: REJECT INVALID PAYMENT ID
    // ==========================================

    @IsTest
    static void testInvalidPaymentId() {

        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            GVRazorpayService.fetchPayment(
                'INVALID_PAYMENT'
            );

        } catch (GVRazorpayService.RazorpayException e) {
            exceptionThrown = true;
        }

        Test.stopTest();

        System.assertEquals(
            true,
            exceptionThrown,
            'Invalid payment ID must be rejected.'
        );
    }

    // ==========================================
    // TEST 6: REJECT NULL VERIFICATION
    // ==========================================

    @IsTest
    static void testNullPaymentVerification() {

        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            GVPaymentVerificationController.verifyPayment(
                null,
                null
            );

        } catch (GVPaymentVerificationService.VerificationException e) {
            exceptionThrown = true;
        }

        Test.stopTest();

        System.assertEquals(
            true,
            exceptionThrown,
            'Null verification must be rejected.'
        );
    }

    // ==========================================
    // TEST 7: RAZORPAY API FAILURE
    // ==========================================

    @IsTest
    static void testRazorpayApiFailure() {

        Test.setMock(
            HttpCalloutMock.class,
            new RazorpayMock(
                500,
                'failed',
                false
            )
        );

        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            GVRazorpayService.fetchPayment(
                'pay_GVTest123456'
            );

        } catch (GVRazorpayService.RazorpayException e) {
            exceptionThrown = true;
        }

        Test.stopTest();

        System.assertEquals(
            true,
            exceptionThrown,
            'Razorpay API error must be handled.'
        );
    }
}
