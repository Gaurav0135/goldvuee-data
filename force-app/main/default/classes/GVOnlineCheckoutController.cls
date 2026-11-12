public with sharing class GVOnlineCheckoutController {
  public class CheckoutResult {
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
  public static CheckoutResult prepareOnlineOrder(
    String shippingAddress,
    String shippingCity,
    String shippingState,
    String shippingPostalCode,
    String shippingCountry
  ) {
    Savepoint sp = Database.setSavepoint();
    try {
      return GVCheckoutEngine.prepare(
        shippingAddress,
        shippingCity,
        shippingState,
        shippingPostalCode,
        shippingCountry
      );
    } catch (Exception e) {
      Database.rollback(sp);
      throw new AuraHandledException(e.getMessage());
    }
  }
  @AuraEnabled
  public static CheckoutResult resumeCheckout() {
    return GVCheckoutEngine.resume();
  }
  @AuraEnabled
  public static void cancelExpiredCheckout(Id paymentId) {
    GVCheckoutEngine.cancelExpired(paymentId);
  }
  @AuraEnabled
  public static void requestReconciliation(Id paymentId) {
    Payment__c pre = GVCheckoutEngine.ownedPayment(paymentId);
    GVCheckoutEngine.lockCustomer(pre.Jewellery_Order__r.Customer__c);
    Payment__c p = [
      SELECT Id, Payment_Status__c, Reconciliation_Requested_At__c
      FROM Payment__c
      WHERE Id = :paymentId
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    if (
      p.Payment_Status__c != 'Pending' ||
      (p.Reconciliation_Requested_At__c != null &&
      p.Reconciliation_Requested_At__c > System.now().addMinutes(-1))
    )
      return;
    p.Reconciliation_Requested_At__c = System.now();
    update as system p;
    System.enqueueJob(new GVGatewayWorker(p.Id, 'reconcile'));
  }
}
