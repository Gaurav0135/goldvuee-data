/** Retired endpoint. Configure /goldvuee/payment-links/ for signed hosted-link events. */
@RestResource(urlMapping='/goldvuee/razorpay/*')
global without sharing class GVRazorpayWebhook {
  @HttpPost
  global static void receive() {
    RestContext.response.statusCode = 410;
  }
}
