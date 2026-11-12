/**
 * GOLDVUEE | PAYMENT VERIFICATION CONTROLLER
 *
 * Customer-facing entry point.
 * Delegates sensitive payment operations
 * to GVPaymentVerificationService.
 */
public with sharing class GVPaymentVerificationController {
  public class VerificationResult {
    @AuraEnabled
    public Boolean success;
    @AuraEnabled
    public Id orderId;
    @AuraEnabled
    public String orderNumber;
    @AuraEnabled
    public String paymentStatus;
    @AuraEnabled
    public String orderStatus;
    @AuraEnabled
    public String message;
  }

  // Verify authenticated ownership of an existing Salesforce payment.
  // Never grant customers access to the encrypted Razorpay secret.
  private static Payment__c customerPayment(Id paymentId) {
    if (paymentId == null) {
      throw new AuraHandledException('Missing payment ID.');
    }

    List<User> users = [
      SELECT ContactId
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];
    if (users.isEmpty() || users[0].ContactId == null) {
      throw new AuraHandledException('Sign in to your GoldVuee account.');
    }

    List<Payment__c> matches = [
      SELECT
        Id,
        Payment_Status__c,
        Transaction_ID__c,
        Razorpay_Order_ID__c,
        Razorpay_Verified_Payment_ID__c,
        Jewellery_Order__r.Customer__c
      FROM Payment__c
      WHERE Id = :paymentId
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    if (
      matches.isEmpty() ||
      matches[0].Jewellery_Order__r == null ||
      matches[0].Jewellery_Order__r.Customer__c != users[0].ContactId
    ) {
      throw new AuraHandledException('Payment not found or access denied.');
    }
    return matches[0];
  }

  @AuraEnabled
  public static String requestSignatureVerification(
    Id paymentId,
    String razorpayPaymentId,
    String razorpaySignature
  ) {
    Payment__c payment = customerPayment(paymentId);

    if (
      !Pattern.matches(
        '^pay_[A-Za-z0-9]+$',
        String.valueOf(razorpayPaymentId)
      ) ||
      !Pattern.matches(
        '^[a-fA-F0-9]{64}$',
        String.valueOf(razorpaySignature)
      ) ||
      String.isBlank(payment.Razorpay_Order_ID__c)
    ) {
      throw new AuraHandledException('Invalid Razorpay checkout response.');
    }

    if (
      payment.Payment_Status__c == 'Success' &&
      payment.Transaction_ID__c == razorpayPaymentId
    ) {
      return 'CONFIRMED';
    }

    if (payment.Payment_Status__c != 'Pending') {
      throw new AuraHandledException('Payment is not awaiting confirmation.');
    }

    if (payment.Razorpay_Verified_Payment_ID__c == razorpayPaymentId) {
      return 'VERIFIED';
    }

    // Subscriber runs as Automated Process and verifies the HMAC
    // against the secret stored in the encrypted configuration.
    GoldVuee_Payment_Verification__e verificationEvent = new GoldVuee_Payment_Verification__e(
      Payment_Record_ID__c = String.valueOf(paymentId),
      Razorpay_Payment_ID__c = razorpayPaymentId,
      Razorpay_Signature__c = razorpaySignature
    );

    Database.SaveResult outcome = GVPaymentEventPublisher.publish(
      verificationEvent
    );

    if (!outcome.isSuccess()) {
      throw new AuraHandledException(
        'Unable to queue Razorpay signature verification: ' +
        outcome.getErrors()[0].getStatusCode()
      );
    }
    return 'WAITING';
  }

  @AuraEnabled
  public static String signatureVerificationState(
    Id paymentId,
    String razorpayPaymentId
  ) {
    Payment__c payment = customerPayment(paymentId);

    if (
      !Pattern.matches('^pay_[A-Za-z0-9]+$', String.valueOf(razorpayPaymentId))
    ) {
      throw new AuraHandledException('Invalid Razorpay payment reference.');
    }

    if (
      payment.Payment_Status__c == 'Success' &&
      payment.Transaction_ID__c == razorpayPaymentId
    ) {
      return 'CONFIRMED';
    }

    if (payment.Payment_Status__c != 'Pending') {
      return 'FAILED';
    }

    if (payment.Razorpay_Verified_Payment_ID__c == razorpayPaymentId) {
      return 'VERIFIED';
    }

    return 'WAITING';
  }

  @AuraEnabled
  public static VerificationResult verifyPayment(
    Id paymentId,
    String razorpayPaymentId
  ) {
    try {
      GVPaymentVerificationService.Result serviceResult = GVPaymentVerificationService.verify(
        paymentId,
        razorpayPaymentId,
        UserInfo.getUserId()
      );

      VerificationResult result = new VerificationResult();

      result.success = serviceResult.success;
      result.orderId = serviceResult.orderId;
      result.orderNumber = serviceResult.orderNumber;
      result.paymentStatus = serviceResult.paymentStatus;
      result.orderStatus = serviceResult.orderStatus;
      result.message = serviceResult.message;

      return result;
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'GOLDVUEE PAYMENT VERIFICATION ERROR | ' +
          e.getTypeName() +
          ': ' +
          e.getMessage()
      );

      // Preserve original exceptions during tests.
      if (Test.isRunningTest()) {
        throw e;
      }

      throw new AuraHandledException(
        'Unable to complete payment confirmation. ' +
        'Please check your order before retrying.'
      );
    }
  }
}
