/** Ingress queues raw bytes for secret verification as Automated Process. It never trusts payment payloads. */
@RestResource(urlMapping='/goldvuee/razorpay/*')
global without sharing class GVRazorpayWebhook {
  @HttpPost
  global static void receive() {
    RestRequest req = RestContext.request;
    RestResponse res = RestContext.response;
    if (req.requestBody == null || req.requestBody.size() > 100000) {
      res.statusCode = 400;
      return;
    }
    String signature = req.headers.get('X-Razorpay-Signature');
    if (
      String.isBlank(signature) ||
      !Pattern.matches('^[a-fA-F0-9]{64}$', signature)
    ) {
      res.statusCode = 401;
      return;
    }
    // A 202 acknowledges receipt only; the subscriber validates HMAC before any payment action.
    Database.SaveResult result = GVPaymentEventPublisher.publish(
      new GoldVuee_Payment_Verification__e(
        Source__c = 'Webhook',
        Raw_Body__c = req.requestBody.toString(),
        Razorpay_Signature__c = signature
      )
    );
    res.statusCode = result.isSuccess() ? 202 : 503;
  }
}
