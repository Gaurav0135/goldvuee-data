/** Public ingress only publishes raw signed bytes. The existing event runs as the configured integration user. */
@RestResource(urlMapping='/goldvuee/payment-links/*')
global without sharing class GVPaymentWebhook {
  @HttpPost
  global static void receive() {
    RestRequest req = RestContext.request;
    RestResponse res = RestContext.response;
    String signature = req.headers.get('X-Razorpay-Signature');
    if (req.requestBody == null || req.requestBody.size() > 100000) {
      res.statusCode = 400;
      return;
    }
    if (
      String.isBlank(signature) ||
      !Pattern.matches('^[a-fA-F0-9]{64}$', signature)
    ) {
      res.statusCode = 401;
      return;
    }
    Database.SaveResult result = EventBus.publish(
      new GoldVuee_Payment_Verification__e(
        Source__c = 'HostedLink',
        Raw_Body__c = req.requestBody.toString(),
        Razorpay_Signature__c = signature
      )
    );
    res.statusCode = result.isSuccess() ? 202 : 503;
  }
  public static void deliver(List<GoldVuee_Payment_Verification__e> events) {
    try {
      process(events);
    } catch (Exception error) {
      throw new EventBus.RetryableException(
        'Hosted payment verification could not complete. Retrying delivery.'
      );
    }
  }
  public static void process(List<GoldVuee_Payment_Verification__e> events) {
    List<GV_Payment_Config__c> configs = [
      SELECT Webhook_Secret__c
      FROM GV_Payment_Config__c
      WHERE Name = 'Hosted Test Mode'
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (
      configs.isEmpty() ||
      String.isBlank(configs[0].Webhook_Secret__c) ||
      configs[0].Webhook_Secret__c.contains('*')
    )
      throw new GVCheckoutService.CheckoutException(
        'Webhook signing secret unavailable to integration user.'
      );
    for (GoldVuee_Payment_Verification__e event : events) {
      if (event.Source__c != 'HostedLink')
        continue;
      if (
        !valid(
          event.Raw_Body__c,
          event.Razorpay_Signature__c,
          configs[0].Webhook_Secret__c
        )
      )
        continue;
      Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
        event.Raw_Body__c
      );
      Map<String, Object> payload = (Map<String, Object>) body.get('payload');
      if (body.get('event') == 'payment.failed') {
        recordFailedAttempt(payload);
        continue;
      }
      if (body.get('event') != 'payment_link.paid')
        continue;
      Map<String, Object> link = (Map<String, Object>) ((Map<String, Object>) payload.get(
          'payment_link'
        ))
        .get('entity');
      Map<String, Object> payment = (Map<String, Object>) ((Map<String, Object>) payload.get(
          'payment'
        ))
        .get('entity');
      String reference = (String) link.get('reference_id');
      if (String.isBlank(reference))
        continue;
      List<Payment__c> ps = [
        SELECT
          Id,
          Payment_Amount__c,
          Gateway_Response__c,
          Razorpay_Order_ID__c,
          Transaction_ID__c
        FROM Payment__c
        WHERE Id = :reference
        WITH SYSTEM_MODE
      ];
      if (ps.isEmpty())
        continue;
      Payment__c p = ps[0];
      GVCheckoutService.Attempt a = GVCheckoutService.attempt(p);
      if (
        a.linkId != (String) link.get('id') ||
        link.get('status') != 'paid' ||
        link.get('currency') != 'INR' ||
        GVCheckoutService.numberValue(link.get('amount')) !=
        p.Payment_Amount__c * 100 ||
        GVCheckoutService.numberValue(link.get('amount_paid')) !=
        p.Payment_Amount__c * 100 ||
        link.get('accept_partial') != false
      )
        continue;
      // Paid webhook's authenticated link order ID binds the payment entity to the stored link.
      if (String.isBlank(a.gatewayOrderId)) {
        a.gatewayOrderId = (String) link.get('order_id');
        if (
          String.isBlank(a.gatewayOrderId) ||
          payment.get('order_id') != a.gatewayOrderId
        )
          continue;
        p.Gateway_Response__c = JSON.serialize(a);
        p.Razorpay_Order_ID__c = a.gatewayOrderId;
        update as system p;
      }
      GVCheckoutService.captured(p.Id, a.linkId, payment);
    }
  }
  private static void recordFailedAttempt(Map<String, Object> payload) {
    Map<String, Object> evidence = (Map<String, Object>) ((Map<String, Object>) payload.get(
        'payment'
      ))
      .get('entity');
    String gatewayOrderId = (String) evidence.get('order_id');
    if (
      String.isBlank(gatewayOrderId) ||
      evidence.get('status') != 'failed' ||
      evidence.get('currency') != 'INR'
    )
      return;
    List<Payment__c> payments = [
      SELECT
        Id,
        Payment_Status__c,
        Payment_Amount__c,
        Gateway_Response__c,
        Razorpay_Order_ID__c,
        Transaction_ID__c
      FROM Payment__c
      WHERE Razorpay_Order_ID__c = :gatewayOrderId
      WITH SYSTEM_MODE
      LIMIT 2
      FOR UPDATE
    ];
    if (payments.size() != 1 || payments[0].Payment_Status__c != 'Pending')
      return;
    Payment__c p = payments[0];
    GVCheckoutService.Attempt a = GVCheckoutService.attempt(p);
    if (
      String.isBlank(a.linkId) ||
      a.gatewayOrderId != gatewayOrderId ||
      GVCheckoutService.numberValue(evidence.get('amount')) !=
      p.Payment_Amount__c * 100
    )
      return;
    if (a.lastFailurePaymentId == (String) evidence.get('id'))
      return;
    a.lastFailurePaymentId = (String) evidence.get('id');
    a.lastFailureState = 'failed';
    p.Gateway_Response__c = JSON.serialize(a);
    p.Failure_Reason__c = 'A gateway payment attempt failed. The hosted link remains open for a safe retry; no stock was deducted.';
    update as system p;
  }
  @TestVisible
  private static Boolean valid(String body, String signature, String secret) {
    try {
      return !String.isBlank(signature) &&
        Crypto.verifyHMac(
          'HmacSHA256',
          Blob.valueOf(body),
          Blob.valueOf(secret),
          EncodingUtil.convertFromHex(signature)
        );
    } catch (Exception e) {
      return false;
    }
  }
}
