/** Retired API deny shell. Separate reviewed destructive deployment removes this metadata. */
public without sharing class GVOnlineCheckoutController {
  public class RecoveryResult {
    @AuraEnabled
    public String state;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public Boolean canCancel = false;
    @AuraEnabled
    public Boolean canRetry = false;
    @AuraEnabled
    public Boolean canRecover = false;
    @AuraEnabled
    public CheckoutResult order;
  }
  public class CheckoutResult {
    @AuraEnabled
    public Id cartId;
    @AuraEnabled
    public List<Jewellery_Order_Item__c> items;
    @AuraEnabled
    public Id orderId;
    @AuraEnabled
    public Id paymentId;
    @AuraEnabled
    public String orderNumber;
    @AuraEnabled
    public Decimal grandTotal;
    @AuraEnabled
    public String orderStatus;
    @AuraEnabled
    public String paymentStatus;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public String shippingAddress;
    @AuraEnabled
    public String shippingCity;
    @AuraEnabled
    public String shippingState;
    @AuraEnabled
    public String shippingPostalCode;
    @AuraEnabled
    public String shippingCountry;
    @AuraEnabled
    public String reconciliationState;
  }
  @AuraEnabled
  public static CheckoutResult beginCheckout() {
    throw new AuraHandledException(
      'This checkout API is retired. Open the GoldVuee checkout page.'
    );
  }
  @AuraEnabled
  public static RecoveryResult checkoutRecovery(Id paymentId) {
    throw new AuraHandledException(
      'This checkout API is retired. Open the GoldVuee checkout page.'
    );
  }
  @AuraEnabled
  public static RecoveryResult cancelUnpaidCheckout(Id paymentId) {
    throw new AuraHandledException(
      'This checkout API is retired. Open the GoldVuee checkout page.'
    );
  }
  @AuraEnabled
  public static CheckoutResult prepareOnlineOrder(
    String shippingAddress,
    String shippingCity,
    String shippingState,
    String shippingPostalCode,
    String shippingCountry
  ) {
    throw new AuraHandledException(
      'This checkout API is retired. Open the GoldVuee checkout page.'
    );
  }
  @AuraEnabled
  public static CheckoutResult resumeCheckout() {
    throw new AuraHandledException(
      'This checkout API is retired. Open the GoldVuee checkout page.'
    );
  }
  @AuraEnabled
  public static void cancelExpiredCheckout(Id paymentId) {
    throw new AuraHandledException(
      'This checkout API is retired. Open the GoldVuee checkout page.'
    );
  }
  @AuraEnabled
  public static void requestReconciliation(Id paymentId) {
    throw new AuraHandledException(
      'This checkout API is retired. Open the GoldVuee checkout page.'
    );
  }
}
