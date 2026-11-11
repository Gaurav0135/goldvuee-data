
/*
 * GOLDVUEE - RAZORPAY TEST PAYMENT ORDER
 *
 * Creates a real Razorpay Test Mode order
 * for INR 1.00.
 *
 * Uses Named Credential: GV_Razorpay_Test
 *
 * Does not modify jewellery orders,
 * shopping carts, payments or inventory.
 */

try {

    // 1. Set demo payment amount.
    Integer amountPaise = 100;

    // 2. Generate unique receipt.
    String receiptNumber =
        'GV-DEMO-' +
        String.valueOf(
            System.now().getTime()
        );

    // 3. Prepare Razorpay request body.
    Map<String, Object> requestBody =
        new Map<String, Object>();

    requestBody.put(
        'amount',
        amountPaise
    );

    requestBody.put(
        'currency',
        'INR'
    );

    requestBody.put(
        'receipt',
        receiptNumber
    );

    // 4. Prepare HTTP request.
    HttpRequest request = new HttpRequest();

    // request.setEndpoint(
    //     'callout:GV_Razorpay_Test/orders'
    // );

    request.setEndpoint(
    'callout:GV_Razorpay_Test/v1/orders'
    );

    request.setMethod('POST');

    request.setHeader(
        'Content-Type',
        'application/json'
    );

    request.setTimeout(30000);

    request.setBody(
        JSON.serialize(requestBody)
    );

    // 5. Call Razorpay Test Mode API.
    Http http = new Http();

    HttpResponse response =
        http.send(request);

    System.debug(
        LoggingLevel.ERROR,
        'GOLDVUEE_HTTP_STATUS=' +
        response.getStatusCode()
    );

    // 6. Process Razorpay response.
    if (
        response.getStatusCode() == 200 ||
        response.getStatusCode() == 201
    ) {

        Map<String, Object> result =
            (Map<String, Object>)
            JSON.deserializeUntyped(
                response.getBody()
            );

        String razorpayOrderId =
            (String) result.get('id');

        System.debug(
            LoggingLevel.ERROR,
            'GOLDVUEE_DEMO_ORDER_ID=' +
            razorpayOrderId
        );

        System.debug(
            LoggingLevel.ERROR,
            'GOLDVUEE_DEMO_AMOUNT_PAISE=' +
            String.valueOf(amountPaise)
        );

        System.debug(
            LoggingLevel.ERROR,
            'GOLDVUEE_DEMO_CURRENCY=INR'
        );

        System.debug(
            LoggingLevel.ERROR,
            'GOLDVUEE_DEMO_SUCCESS'
        );

    } else {

        System.debug(
            LoggingLevel.ERROR,
            'GOLDVUEE_DEMO_FAILED'
        );

        System.debug(
            LoggingLevel.ERROR,
            'GOLDVUEE_RESPONSE=' +
            response.getBody()
        );
    }

} catch (Exception e) {

    System.debug(
        LoggingLevel.ERROR,
        'GOLDVUEE_ERROR=' +
        e.getMessage()
    );

    System.debug(
        LoggingLevel.ERROR,
        'GOLDVUEE_ERROR_TYPE=' +
        e.getTypeName()
    );
}
