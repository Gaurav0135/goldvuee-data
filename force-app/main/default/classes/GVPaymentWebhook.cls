/** Signed raw events are verified in the existing integration-user subscriber, never in guest context. */
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
    String raw = req.requestBody.toString();
    if (
      raw.length() >
      GoldVuee_Payment_Verification__e.Raw_Body__c.getDescribe().getLength()
    ) {
      res.statusCode = 400;
      return;
    }
    Database.SaveResult saved = EventBus.publish(
      new GoldVuee_Payment_Verification__e(
        Source__c = 'HostedLink',
        Raw_Body__c = raw,
        Razorpay_Signature__c = signature
      )
    );
    res.statusCode = saved.isSuccess() ? 202 : 503;
  }
  public static void deliver(List<GoldVuee_Payment_Verification__e> events) {
    try {
      process(events);
    } catch (Exception error) {
      throw new EventBus.RetryableException(
        'Payment verification could not complete; retry signed event delivery.'
      );
    }
  }
  public static void process(List<GoldVuee_Payment_Verification__e> events) {
    List<GV_Payment_Config__c> config = [
      SELECT Webhook_Secret__c
      FROM GV_Payment_Config__c
      WHERE Name = 'RazorpayTest'
      WITH SYSTEM_MODE
      LIMIT 2
    ];
    if (
      config.size() != 1 ||
      String.isBlank(config[0].Webhook_Secret__c) ||
      config[0].Webhook_Secret__c.contains('*')
    )
      throw new GVCheckoutService.CheckoutException(
        'Integration signing configuration is unavailable.'
      );
    for (GoldVuee_Payment_Verification__e event : events) {
      if (
        event.Source__c != 'HostedLink' ||
        !valid(
          event.Raw_Body__c,
          event.Razorpay_Signature__c,
          config[0].Webhook_Secret__c
        )
      )
        continue;
      Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
        event.Raw_Body__c
      );
      String kind = (String) body.get('event');
      Map<String, Object> payload = (Map<String, Object>) body.get('payload');
      if (payload == null)
        continue;
      if (kind == 'payment.failed') {
        failed(entity(payload, 'payment'));
        continue;
      }
      if (
        !new Set<String>{
            'payment_link.paid',
            'payment_link.cancelled',
            'payment_link.expired'
          }
          .contains(kind)
      )
        continue;
      Map<String, Object> link = entity(payload, 'payment_link');
      if (link == null)
        continue;
      String reference = (String) link.get('reference_id');
      if (
        String.isBlank(reference) ||
        !Pattern.matches('^[A-Za-z0-9]{15}(?:[A-Za-z0-9]{3})?$', reference)
      )
        continue;
      List<Payment__c> rows = [
        SELECT Id, Jewellery_Order__r.Customer__c
        FROM Payment__c
        WHERE Id = :reference
        WITH SYSTEM_MODE
      ];
      if (rows.isEmpty())
        continue;
      GVCheckoutService.lockCustomer(rows[0].Jewellery_Order__r.Customer__c);
      Payment__c p = [
        SELECT
          Id,
          Payment_Status__c,
          Payment_Amount__c,
          Gateway_Response__c,
          Razorpay_Order_ID__c,
          Transaction_ID__c
        FROM Payment__c
        WHERE Id = :reference
        WITH SYSTEM_MODE
        FOR UPDATE
      ];
      GVCheckoutService.Attempt a = GVCheckoutService.attempt(p);
      if (
        a.linkId != link.get('id') ||
        String.isBlank(a.linkId) ||
        link.get('currency') != 'INR' ||
        link.get('accept_partial') != false ||
        GVCheckoutService.numberValue(link.get('amount')) !=
        p.Payment_Amount__c * 100
      )
        continue;
      if (kind == 'payment_link.paid') {
        if (
          link.get('status') != 'paid' ||
          GVCheckoutService.numberValue(link.get('amount_paid')) !=
          p.Payment_Amount__c * 100
        )
          continue;
        Map<String, Object> payment = entity(payload, 'payment');
        if (payment == null || payment.get('order_id') != link.get('order_id'))
          continue;
        if (String.isBlank(a.gatewayOrderId)) {
          a.gatewayOrderId = (String) link.get('order_id');
          p.Gateway_Response__c = JSON.serialize(a);
          p.Razorpay_Order_ID__c = a.gatewayOrderId;
          update as system p;
        }
        GVCheckoutService.captured(p.Id, a.linkId, payment);
      } else if (
        p.Payment_Status__c == 'Pending' &&
        GVCheckoutService.numberValue(link.get('amount_paid')) == 0
      ) {
        // New expiry-policy links require a current order-payment read, not an out-of-order event alone.
        if (a.expirySeconds == 120) {
          GVRazorpayController.reconcileForAdmin(p.Id);
          continue;
        }
        String state = kind == 'payment_link.expired' ? 'Expired' : 'Cancelled';
        if (link.get('status') != state.toLowerCase())
          continue;
        a.state = state;
        p.Payment_Status__c = 'Failed';
        p.Gateway_Response__c = JSON.serialize(a);
        p.Failure_Reason__c =
          'Signed gateway event verified ' +
          state.toLowerCase() +
          ' with zero paid.';
        update as system p;
      }
    }
  }
  private static Map<String, Object> entity(
    Map<String, Object> payload,
    String name
  ) {
    Map<String, Object> wrapper = (Map<String, Object>) payload.get(name);
    return wrapper == null ? null : (Map<String, Object>) wrapper.get('entity');
  }
  private static void failed(Map<String, Object> evidence) {
    if (
      evidence == null ||
      evidence.get('status') != 'failed' ||
      evidence.get('currency') != 'INR'
    )
      return;
    String gatewayOrder = (String) evidence.get('order_id');
    if (String.isBlank(gatewayOrder))
      return;
    List<Payment__c> owners = [
      SELECT Id, Jewellery_Order__r.Customer__c
      FROM Payment__c
      WHERE Razorpay_Order_ID__c = :gatewayOrder
      WITH SYSTEM_MODE
      LIMIT 2
    ];
    if (owners.size() != 1)
      return;
    GVCheckoutService.lockCustomer(owners[0].Jewellery_Order__r.Customer__c);
    Payment__c p = [
      SELECT
        Id,
        Payment_Status__c,
        Payment_Amount__c,
        Gateway_Response__c,
        Razorpay_Order_ID__c,
        Transaction_ID__c
      FROM Payment__c
      WHERE Id = :owners[0].Id
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    GVCheckoutService.Attempt a = GVCheckoutService.attempt(p);
    if (
      p.Payment_Status__c != 'Pending' ||
      a.gatewayOrderId != gatewayOrder ||
      a.linkId == null ||
      GVCheckoutService.numberValue(evidence.get('amount')) !=
      p.Payment_Amount__c * 100 ||
      a.lastFailurePaymentId == evidence.get('id')
    )
      return;
    a.lastFailurePaymentId = (String) evidence.get('id');
    a.lastFailureState = 'failed';
    p.Gateway_Response__c = JSON.serialize(a);
    p.Failure_Reason__c = 'A gateway transaction failed. The existing hosted link is available for safe retry.';
    update as system p;
  }
  @TestVisible
  private static Boolean valid(String body, String signature, String secret) {
    try {
      return !String.isBlank(signature) &&
        Pattern.matches('^[a-fA-F0-9]{64}$', signature) &&
        Crypto.verifyHMac(
          'HmacSHA256',
          Blob.valueOf(body),
          Blob.valueOf(secret),
          EncodingUtil.convertFromHex(signature)
        );
    } catch (Exception invalid) {
      return false;
    }
  }
}
