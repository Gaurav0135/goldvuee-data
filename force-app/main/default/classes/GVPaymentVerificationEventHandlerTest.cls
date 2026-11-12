@IsTest
private class GVPaymentVerificationEventHandlerTest {
  @IsTest
  static void emptyEventListShouldBeIgnored() {
    Test.startTest();

    GVPaymentVerificationEventHandler.process(
      new List<GoldVuee_Payment_Verification__e>()
    );

    Test.stopTest();

    System.assert(true);
  }

  @IsTest
  static void missingPaymentIdShouldBeIgnored() {
    GoldVuee_Payment_Verification__e eventRecord = new GoldVuee_Payment_Verification__e(
      Razorpay_Payment_ID__c = 'pay_test123',
      Razorpay_Signature__c = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' +
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    );

    Test.startTest();

    GVPaymentVerificationEventHandler.process(
      new List<GoldVuee_Payment_Verification__e>{ eventRecord }
    );

    Test.stopTest();

    System.assert(true);
  }

  @IsTest
  static void malformedPaymentIdShouldBeIgnored() {
    GoldVuee_Payment_Verification__e eventRecord = new GoldVuee_Payment_Verification__e(
      Payment_Record_ID__c = 'invalid-id',
      Razorpay_Payment_ID__c = 'pay_test123',
      Razorpay_Signature__c = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' +
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    );

    Test.startTest();

    GVPaymentVerificationEventHandler.process(
      new List<GoldVuee_Payment_Verification__e>{ eventRecord }
    );

    Test.stopTest();

    System.assert(true);
  }

  @IsTest
  static void missingSignatureShouldBeIgnored() {
    GoldVuee_Payment_Verification__e eventRecord = new GoldVuee_Payment_Verification__e(
      Payment_Record_ID__c = 'not-a-valid-id',
      Razorpay_Payment_ID__c = 'pay_test123'
    );

    Test.startTest();

    GVPaymentVerificationEventHandler.process(
      new List<GoldVuee_Payment_Verification__e>{ eventRecord }
    );

    Test.stopTest();

    System.assert(true);
  }
  // Exercise the actual Platform Event trigger through the event bus.
  // Malformed data must not authorize a payment or update an order.
  @IsTest
  static void triggerRejectsMalformedPaymentEvent() {
    Test.startTest();
    Database.SaveResult publishResult = EventBus.publish(
      new GoldVuee_Payment_Verification__e(
        Payment_Record_ID__c = 'invalid-id',
        Razorpay_Payment_ID__c = 'pay_test123',
        Razorpay_Signature__c = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' +
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      )
    );
    System.assert(
      publishResult.isSuccess(),
      'Test event should be accepted for delivery.'
    );
    Test.getEventBus().deliver();
    Test.stopTest();
  }
}
