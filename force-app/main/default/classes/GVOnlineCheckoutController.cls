public with sharing class GVOnlineCheckoutController {
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
    public CheckoutResult order;
  }

  /** Read-only customer snapshot. Browser statuses never authorize inventory writes. */
  @AuraEnabled
  public static RecoveryResult checkoutRecovery(Id paymentId) {
    RecoveryResult result = new RecoveryResult();
    CheckoutResult restored;
    if (paymentId == null) {
      restored = GVCheckoutEngine.resume();
      if (restored == null) {
        result.state = 'Ready';
        return result;
      }
      paymentId = restored.paymentId;
    }
    Payment__c p = GVCheckoutEngine.ownedPayment(paymentId);
    result.order = restored == null ? new CheckoutResult() : restored;
    result.order.paymentId = p.Id;
    result.order.cartId = p.Jewellery_Order__r.Shopping_Cart__c;
    result.order.orderId = p.Jewellery_Order__c;
    result.order.orderNumber = p.Jewellery_Order__r.Name;
    result.order.grandTotal = p.Jewellery_Order__r.Grand_Total__c;
    result.order.orderStatus = p.Jewellery_Order__r.Order_Status__c;
    result.order.paymentStatus = p.Jewellery_Order__r.Payment_Status__c;
    if (
      p.Payment_Status__c == 'Success' &&
      p.Jewellery_Order__r.Payment_Status__c == 'Paid' &&
      p.Jewellery_Order__r.Order_Status__c == 'Confirmed'
    ) {
      result.state = 'Confirmed';
      return result;
    }
    if (p.Jewellery_Order__r.Order_Status__c == 'Cancelled') {
      result.state = 'Cancelled';
      return result;
    }
    result.state = 'Uncertain';
    result.message = 'Verifying your payment. Please do not pay again yet.';
    if (
      p.Payment_Status__c != 'Pending' ||
      p.Jewellery_Order__r.Order_Status__c != 'pending' ||
      p.Jewellery_Order__r.Payment_Status__c != 'Pending'
    )
      return result;
    if (
      !String.isBlank(p.Transaction_ID__c) ||
      (!String.isBlank(p.Reconciliation_State__c) &&
      p.Reconciliation_State__c.toLowerCase().contains('captured'))
    ) {
      result.state = 'Review';
      result.message = 'Payment received. Your order is under review; please do not pay again.';
      return result;
    }
    // Only a payment that has never queued initialization can be cancelled immediately.
    result.canCancel =
      String.isBlank(p.Razorpay_Order_ID__c) &&
      String.isBlank(p.Initialization_Job__c) &&
      (String.isBlank(p.Initialization_State__c) ||
      p.Initialization_State__c == 'New');
    Boolean live = true;
    try {
      GVCheckoutEngine.reservationIds(p.Jewellery_Order__c, true);
    } catch (Exception e) {
      live = false;
    }
    if (result.canCancel) {
      result.state = live ? 'Interrupted' : 'Expired';
      result.canRetry = live;
      result.message = live
        ? 'Your previous checkout is waiting.'
        : 'Your checkout reservation has expired. Cancel it to update your bag.';
      return result;
    }
    Payment__c timing = [
      SELECT Last_Checked_At__c, Reconciliation_Requested_At__c
      FROM Payment__c
      WHERE Id = :p.Id
      WITH SYSTEM_MODE
    ];
    if (
      live &&
      p.Reconciliation_State__c == 'Unpaid - verified' &&
      timing.Last_Checked_At__c != null &&
      timing.Last_Checked_At__c > System.now().addMinutes(-1) &&
      (timing.Reconciliation_Requested_At__c == null ||
      timing.Last_Checked_At__c >= timing.Reconciliation_Requested_At__c)
    ) {
      result.state = 'Interrupted';
      result.canRetry = true;
      result.message = 'Your payment was not completed. You can resume secure payment.';
    }
    return result;
  }

  /** Fail closed once a gateway job could exist. A lookup alone cannot revoke a live gateway order. */
  @AuraEnabled
  public static RecoveryResult cancelUnpaidCheckout(Id paymentId) {
    Payment__c pre = GVCheckoutEngine.ownedPayment(paymentId);
    GVCheckoutEngine.lockCustomer(pre.Jewellery_Order__r.Customer__c);
    List<Shopping_Cart__c> carts = [
      SELECT Id
      FROM Shopping_Cart__c
      WHERE
        Id IN (
          SELECT Shopping_Cart__c
          FROM Jewellery_Order__c
          WHERE Id = :pre.Jewellery_Order__c
        )
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    Jewellery_Order__c orderRecord = [
      SELECT Id, Order_Status__c, Payment_Status__c
      FROM Jewellery_Order__c
      WHERE Id = :pre.Jewellery_Order__c
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    Payment__c payment = [
      SELECT
        Id,
        Payment_Status__c,
        Transaction_ID__c,
        Razorpay_Order_ID__c,
        Initialization_State__c,
        Initialization_Job__c
      FROM Payment__c
      WHERE Id = :paymentId
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    RecoveryResult result = checkoutRecovery(paymentId);
    if (result.state == 'Confirmed' || result.state == 'Cancelled')
      return result;
    if (
      !result.canCancel ||
      carts.isEmpty() ||
      payment.Payment_Status__c != 'Pending' ||
      orderRecord.Order_Status__c != 'pending' ||
      orderRecord.Payment_Status__c != 'Pending' ||
      !String.isBlank(payment.Transaction_ID__c) ||
      !String.isBlank(payment.Razorpay_Order_ID__c) ||
      !String.isBlank(payment.Initialization_Job__c) ||
      (!String.isBlank(payment.Initialization_State__c) &&
      payment.Initialization_State__c != 'New')
    ) {
      result.canRetry = false;
      result.state = result.state == 'Review' ? 'Review' : 'Uncertain';
      result.message = 'We cannot safely cancel this payment yet. Your bag remains reserved. Please check My Orders or contact GoldVuee support.';
      return result;
    }
    Set<Id> ids = GVCheckoutEngine.reservationIds(orderRecord.Id, false);
    Savepoint sp = Database.setSavepoint();
    try {
      GVInventoryService.change(ids, false);
      orderRecord.Order_Status__c = 'Cancelled';
      payment.Payment_Status__c = 'Failed';
      update as system orderRecord;
      update as system payment;
    } catch (Exception e) {
      Database.rollback(sp);
      throw e;
    }
    return checkoutRecovery(paymentId);
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
      SELECT
        Id,
        Payment_Status__c,
        Reconciliation_Requested_At__c,
        Last_Checked_At__c
      FROM Payment__c
      WHERE Id = :paymentId
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    if (
      p.Payment_Status__c != 'Pending' ||
      (p.Reconciliation_Requested_At__c != null &&
      p.Reconciliation_Requested_At__c > System.now().addMinutes(-1) &&
      (p.Last_Checked_At__c == null ||
      p.Last_Checked_At__c < p.Reconciliation_Requested_At__c))
    )
      return;
    p.Reconciliation_Requested_At__c = System.now();
    update as system p;
    System.enqueueJob(new GVGatewayWorker(p.Id, 'reconcile'));
  }
}
