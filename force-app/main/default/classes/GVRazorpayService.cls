/**
 * GOLDVUEE | RAZORPAY PAYMENT SERVICE
 *
 * Razorpay Test Mode Integration
 *
 * Features:
 * 1. Create Razorpay payment orders
 * 2. Fetch Razorpay payment details
 * 3. Validate API responses
 * 4. Secure Salesforce Named Credential callouts
 *
 * Named Credential: GV_Razorpay_Test
 *
 * IMPORTANT:
 * - Never expose Razorpay Key Secret to LWC.
 * - Payment amounts must come from Salesforce.
 * - Creating an order does not confirm payment.
 * - Verify captured payment before confirming orders.
 */
public with sharing class GVRazorpayService {
  /** Receipt lookup recovers a timed-out creation; it never creates another order. */
  public static String findOrder(String receipt, Decimal amount) {
    Map<String, Object> data = getJson(
      '/v1/orders?receipt=' +
        EncodingUtil.urlEncode(receipt, 'UTF-8') +
        '&count=100'
    );
    String found;
    for (Object item : (List<Object>) data.get('items')) {
      Map<String, Object> row = (Map<String, Object>) item;
      if (String.valueOf(row.get('receipt')) != receipt)
        continue;
      if (
        Decimal.valueOf(String.valueOf(row.get('amount'))) != (amount * 100) ||
        String.valueOf(row.get('currency')) != 'INR' ||
        found != null
      )
        throw new RazorpayException(
          'Ambiguous gateway receipt requires review.'
        );
      found = String.valueOf(row.get('id'));
    }
    return found;
  }
  public static RazorpayPaymentDetails capturedForOrder(String orderId) {
    if (!Pattern.matches('^order_[A-Za-z0-9]+$', orderId))
      throw new RazorpayException('Invalid gateway order.');
    Map<String, Object> data = getJson('/v1/orders/' + orderId + '/payments');
    List<Object> attempts = (List<Object>) data.get('items');
    // This endpoint returns all attempts. Reject a response whose reported count is incomplete.
    if (
      data.get('count') != null &&
      Decimal.valueOf(String.valueOf(data.get('count'))) != attempts.size()
    )
      throw new RazorpayException('Payment attempts require review.');
    for (Object item : attempts) {
      Map<String, Object> row = (Map<String, Object>) item;
      if (String.valueOf(row.get('status')) == 'captured')
        return fetchPayment(String.valueOf(row.get('id')));
    }
    for (Object item : attempts) {
      Map<String, Object> row = (Map<String, Object>) item;
      if (
        String.valueOf(row.get('order_id')) != orderId ||
        String.valueOf(row.get('status')) != 'failed'
      )
        throw new RazorpayException('Payment outcome is still uncertain.');
    }
    return null;
  }
  private static Map<String, Object> getJson(String path) {
    HttpRequest req = new HttpRequest();
    req.setEndpoint('callout:GV_Razorpay_Test' + path);
    req.setMethod('GET');
    req.setTimeout(30000);
    HttpResponse res = new Http().send(req);
    if (res.getStatusCode() != 200)
      throw new RazorpayException('Gateway reconciliation unavailable.');
    Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(
      res.getBody()
    );
    if (data == null || !(data.get('items') instanceof List<Object>))
      throw new RazorpayException('Invalid gateway collection.');
    return data;
  }

  // ==========================================
  // CONFIGURATION
  // ==========================================

  private static final String BASE_ENDPOINT = 'callout:GV_Razorpay_Test';

  private static final String ORDERS_ENDPOINT = BASE_ENDPOINT + '/v1/orders';

  public class RazorpayException extends Exception {
  }

  // ==========================================
  // RESPONSE CLASSES
  // ==========================================

  public class RazorpayOrder {
    public String razorpayOrderId;
    public Long amountPaise;
    public String currencyCode;
    public String status;
    public String receipt;
  }

  public class RazorpayPaymentDetails {
    public String paymentId;
    public String orderId;
    public Long amountPaise;
    public String currencyCode;
    public String paymentStatus;
    public String paymentMethod;
    public Boolean captured;
  }

  // ==========================================
  // 1. CREATE RAZORPAY ORDER
  // ==========================================

  /**
   * Creates an order using Razorpay Orders API.
   *
   * @param amountINR Trusted Salesforce amount in INR.
   * @param receipt Unique Salesforce payment reference.
   */
  public static RazorpayOrder createOrder(Decimal amountINR, String receipt) {
    // STEP 1: VALIDATE AMOUNT

    if (
      amountINR == null ||
      amountINR < 1 ||
      amountINR != amountINR.setScale(2)
    ) {
      throw new RazorpayException('Invalid payment amount.');
    }

    // STEP 2: VALIDATE RECEIPT

    if (String.isBlank(receipt) || receipt.length() > 40) {
      throw new RazorpayException('Invalid Razorpay receipt reference.');
    }

    // STEP 3: CONVERT INR TO PAISE

    Long amountPaise = (amountINR * 100).longValue();

    // STEP 4: PREPARE REQUEST

    HttpRequest request = new HttpRequest();

    request.setEndpoint(ORDERS_ENDPOINT);
    request.setMethod('POST');

    request.setHeader('Content-Type', 'application/json');

    request.setHeader('Accept', 'application/json');

    request.setTimeout(30000);

    Map<String, Object> payload = new Map<String, Object>{
      'amount' => amountPaise,
      'currency' => 'INR',
      'receipt' => receipt
    };

    request.setBody(JSON.serialize(payload));

    // STEP 5: SEND REQUEST

    HttpResponse response;

    try {
      response = new Http().send(request);
    } catch (System.CalloutException e) {
      System.debug(
        LoggingLevel.ERROR,
        'GOLDVUEE RAZORPAY CREATE ORDER ERROR: ' + e.getMessage()
      );

      throw new RazorpayException('Unable to connect to Razorpay.');
    }

    // STEP 6: VALIDATE HTTP RESPONSE

    if (response.getStatusCode() != 200 && response.getStatusCode() != 201) {
      System.debug(
        LoggingLevel.ERROR,
        'GOLDVUEE RAZORPAY ORDER ERROR | HTTP ' + response.getStatusCode()
      );

      throw new RazorpayException(
        'Razorpay could not create the payment order.'
      );
    }

    // STEP 7: PARSE RESPONSE

    Map<String, Object> data;

    try {
      data = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
    } catch (Exception e) {
      throw new RazorpayException('Invalid Razorpay order response.');
    }

    if (
      data == null ||
      data.get('id') == null ||
      data.get('amount') == null ||
      data.get('currency') == null ||
      data.get('status') == null ||
      data.get('receipt') == null
    ) {
      throw new RazorpayException('Incomplete Razorpay order response.');
    }

    // STEP 8: BUILD RESULT

    RazorpayOrder result = new RazorpayOrder();

    try {
      result.razorpayOrderId = String.valueOf(data.get('id'));

      result.amountPaise = Decimal.valueOf(String.valueOf(data.get('amount')))
        .longValue();

      result.currencyCode = String.valueOf(data.get('currency'));

      result.status = String.valueOf(data.get('status'));

      result.receipt = String.valueOf(data.get('receipt'));
    } catch (Exception e) {
      throw new RazorpayException('Unable to parse Razorpay order details.');
    }

    // STEP 9: VERIFY RAZORPAY RESPONSE

    if (
      !result.razorpayOrderId.startsWith('order_') ||
      result.amountPaise != amountPaise ||
      result.currencyCode != 'INR' ||
      result.status != 'created' ||
      result.receipt != receipt
    ) {
      throw new RazorpayException('Razorpay order response validation failed.');
    }

    return result;
  }

  // ==========================================
  // 2. FETCH RAZORPAY PAYMENT
  // ==========================================

  /**
   * Fetches a payment from Razorpay.
   *
   * Uses:
   * GET /v1/payments/{paymentId}
   *
   * Returns verified gateway response fields.
   *
   * Does NOT update Salesforce records.
   */
  public static RazorpayPaymentDetails fetchPayment(String razorpayPaymentId) {
    // STEP 1: VALIDATE PAYMENT ID

    if (
      String.isBlank(razorpayPaymentId) ||
      !Pattern.matches('^pay_[A-Za-z0-9]+$', razorpayPaymentId)
    ) {
      throw new RazorpayException('Invalid Razorpay Payment ID.');
    }

    // STEP 2: PREPARE REQUEST

    HttpRequest request = new HttpRequest();

    request.setEndpoint(BASE_ENDPOINT + '/v1/payments/' + razorpayPaymentId);

    request.setMethod('GET');

    request.setHeader('Accept', 'application/json');

    request.setTimeout(30000);

    // STEP 3: SEND REQUEST

    HttpResponse response;

    try {
      response = new Http().send(request);
    } catch (System.CalloutException e) {
      System.debug(
        LoggingLevel.ERROR,
        'GOLDVUEE RAZORPAY FETCH PAYMENT ERROR: ' + e.getMessage()
      );

      throw new RazorpayException(
        'Unable to retrieve payment details from Razorpay.'
      );
    }

    // STEP 4: VALIDATE RESPONSE

    if (response.getStatusCode() != 200) {
      System.debug(
        LoggingLevel.ERROR,
        'GOLDVUEE RAZORPAY PAYMENT LOOKUP ERROR | HTTP ' +
        response.getStatusCode()
      );

      throw new RazorpayException('Unable to verify payment with Razorpay.');
    }

    // STEP 5: PARSE JSON

    Map<String, Object> data;

    try {
      data = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
    } catch (Exception e) {
      throw new RazorpayException('Invalid Razorpay payment response.');
    }

    // STEP 6: CHECK REQUIRED FIELDS

    if (
      data == null ||
      data.get('id') == null ||
      data.get('order_id') == null ||
      data.get('amount') == null ||
      data.get('currency') == null ||
      data.get('status') == null ||
      data.get('captured') == null
    ) {
      throw new RazorpayException('Incomplete Razorpay payment response.');
    }

    // STEP 7: BUILD PAYMENT DETAILS

    RazorpayPaymentDetails result = new RazorpayPaymentDetails();

    try {
      result.paymentId = String.valueOf(data.get('id'));

      result.orderId = String.valueOf(data.get('order_id'));

      result.amountPaise = Decimal.valueOf(String.valueOf(data.get('amount')))
        .longValue();

      result.currencyCode = String.valueOf(data.get('currency'));

      result.paymentStatus = String.valueOf(data.get('status'));

      result.paymentMethod = data.get('method') == null
        ? null
        : String.valueOf(data.get('method'));

      result.captured =
        String.valueOf(data.get('captured')).toLowerCase() == 'true';
    } catch (Exception e) {
      throw new RazorpayException('Unable to read Razorpay payment details.');
    }

    // STEP 8: VERIFY PAYMENT ID

    if (
      result.paymentId != razorpayPaymentId ||
      !result.orderId.startsWith('order_')
    ) {
      throw new RazorpayException('Razorpay payment reference mismatch.');
    }

    return result;
  }
}
