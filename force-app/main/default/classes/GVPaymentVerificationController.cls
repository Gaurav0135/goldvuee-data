/** Retired API deny shell. Separate reviewed destructive deployment removes this metadata. */
public without sharing class GVPaymentVerificationController {
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
  @AuraEnabled
  public static String requestSignatureVerification(
    Id paymentId,
    String razorpayPaymentId,
    String razorpaySignature
  ) {
    throw new AuraHandledException(
      'This checkout API is retired. Open the GoldVuee checkout page.'
    );
  }
  @AuraEnabled
  public static String signatureVerificationState(
    Id paymentId,
    String razorpayPaymentId
  ) {
    throw new AuraHandledException(
      'This checkout API is retired. Open the GoldVuee checkout page.'
    );
  }
  @AuraEnabled
  public static VerificationResult verifyPayment(
    Id paymentId,
    String razorpayPaymentId
  ) {
    throw new AuraHandledException(
      'This checkout API is retired. Open the GoldVuee checkout page.'
    );
  }
}
