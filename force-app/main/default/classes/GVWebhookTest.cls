@IsTest
private class GVWebhookTest {
  @IsTest
  static void rejectsMissingConfigurationAndBody() {
    RestContext.request = new RestRequest();
    RestContext.response = new RestResponse();
    RestContext.request.requestBody = Blob.valueOf('{}');
    GVRazorpayWebhook.receive();
    System.assertEquals(401, RestContext.response.statusCode);
    RestContext.request.requestBody = null;
    GVRazorpayWebhook.receive();
    System.assertEquals(400, RestContext.response.statusCode);
  }
  @IsTest
  static void rejectsForgedSignature() {
    insert as system new GV_Payment_Config__c(
      Name = 'RazorpayTest',
      Webhook_Secret__c = 'unit-test-webhook-secret'
    );
    RestContext.request = new RestRequest();
    RestContext.response = new RestResponse();
    RestContext.request.requestBody = Blob.valueOf('{}');
    RestContext.request.addHeader('X-Razorpay-Signature', '0'.repeat(64));
    Test.startTest();
    GVRazorpayWebhook.receive();
    System.assertEquals(202, RestContext.response.statusCode);
    Test.getEventBus().deliver();
    Test.stopTest();
    System.assertEquals(
      0,
      [SELECT COUNT() FROM GV_Webhook_Receipt__c WITH SYSTEM_MODE]
    );
    System.assert(
      !GVPaymentVerificationEventHandler.validHmac(
        '{}',
        '0'.repeat(64),
        'unit-test-webhook-secret'
      )
    );
  }
}
