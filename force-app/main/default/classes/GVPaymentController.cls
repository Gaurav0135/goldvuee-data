/** Retired API deny shell. Separate reviewed destructive deployment removes this metadata. */
public without sharing class GVPaymentController {
  public class PaymentResult {
    @AuraEnabled
    public Id paymentId;
    @AuraEnabled
    public Id orderId;
    @AuraEnabled
    public String razorpayOrderId;
    @AuraEnabled
    public Long amountPaise;
    @AuraEnabled
    public String currencyCode;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public String state;
  }
  @AuraEnabled
  public static PaymentResult initiatePayment(Id paymentId) {
    throw new AuraHandledException(
      'This checkout API is retired. Open the GoldVuee checkout page.'
    );
  }
  @AuraEnabled
  public static PaymentResult paymentState(Id paymentId) {
    throw new AuraHandledException(
      'This checkout API is retired. Open the GoldVuee checkout page.'
    );
  }
}
