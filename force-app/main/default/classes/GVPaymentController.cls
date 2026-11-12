/** Initialization ownership is persisted before the one authorized callout worker is enqueued. */
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
    Payment__c pre = GVCheckoutEngine.ownedPayment(paymentId);
    if (!String.isBlank(pre.Transaction_ID__c) ||
        (pre.Reconciliation_State__c != null && pre.Reconciliation_State__c.toLowerCase().contains('captured'))) {
      throw new AuraHandledException('A payment has already been received. Check payment status; do not pay again.');
    }
    GVCheckoutEngine.lockCustomer(pre.Jewellery_Order__r.Customer__c);
    Payment__c payment = [
      SELECT
        Id,
        Jewellery_Order__c,
        Payment_Amount__c,
        Payment_Status__c,
        Razorpay_Order_ID__c,
        Initialization_State__c
      FROM Payment__c
      WHERE Id = :paymentId
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    if (
      payment.Payment_Status__c != 'Pending' ||
      pre.Jewellery_Order__r.Order_Status__c != 'pending' ||
      pre.Jewellery_Order__r.Payment_Status__c != 'Pending' ||
      payment.Payment_Amount__c != pre.Jewellery_Order__r.Grand_Total__c
    )
      throw new AuraHandledException('This order is not awaiting payment.');
    GVCheckoutEngine.reservationIds(payment.Jewellery_Order__c, true);
    if (
      String.isBlank(payment.Razorpay_Order_ID__c) &&
      (String.isBlank(payment.Initialization_State__c) ||
      payment.Initialization_State__c == 'New')
    ) {
      payment.Initialization_State__c = 'Queued';
      payment.Last_Checked_At__c = System.now();
      payment.Initialization_Job__c = System.enqueueJob(
        new GVGatewayWorker(payment.Id, 'initialize')
      );
      update as system payment;
    }
    return result(payment);
  }
  @AuraEnabled
  public static PaymentResult paymentState(Id paymentId) {
    return result(GVCheckoutEngine.ownedPayment(paymentId));
  }
  private static PaymentResult result(Payment__c p) {
    PaymentResult r = new PaymentResult();
    r.paymentId = p.Id;
    r.orderId = p.Jewellery_Order__c;
    r.razorpayOrderId = p.Razorpay_Order_ID__c;
    r.amountPaise = (p.Payment_Amount__c * 100).longValue();
    r.currencyCode = 'INR';
    r.state = p.Payment_Status__c == 'Success'
      ? 'Confirmed'
      : (String.isBlank(p.Razorpay_Order_ID__c)
          ? p.Initialization_State__c
          : 'Ready');
    if (p.isSet('Reconciliation_State__c')) {
      if (p.Reconciliation_State__c == 'Expired - stock released')
        r.state = 'Expired';
      if (
        p.Payment_Status__c != 'Success' &&
        (!String.isBlank(p.Transaction_ID__c) ||
        (p.Reconciliation_State__c != null && p.Reconciliation_State__c.toLowerCase().contains('captured')))
      )
        r.state = 'Review';
      if (p.Payment_Status__c == 'Failed')
        r.state = 'Cancelled';
      r.message = String.isBlank(p.Reconciliation_State__c)
        ? 'Payment initialization ' + r.state
        : p.Reconciliation_State__c;
    } else
      r.message = 'Payment initialization ' + r.state;
    return r;
  }
}
