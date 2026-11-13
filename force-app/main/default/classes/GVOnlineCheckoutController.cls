
/**
 * GOLDVUEE | ONLINE CHECKOUT CONTROLLER
 *
 * Reservation-free checkout recovery.
 *
 * - New checkout attempts do not require stock reservations.
 * - Uninitialized payments can be cancelled safely.
 * - Existing Razorpay orders require gateway verification.
 * - Captured payments are protected.
 * - Legacy reservations are handled during safe cancellation.
 */
public with sharing class GVOnlineCheckoutController {

  @AuraEnabled
  public static CheckoutResult beginCheckout() {
    Savepoint sp = Database.setSavepoint();

    try {
      return GVCheckoutEngine.beginCheckout();
    } catch (Exception e) {
      Database.rollback(sp);
      throw new AuraHandledException(e.getMessage());
    }
  }

  public class RecoveryResult {
    @AuraEnabled public String state;
    @AuraEnabled public String message;
    @AuraEnabled public Boolean canCancel = false;
    @AuraEnabled public Boolean canRetry = false;
    @AuraEnabled public Boolean canRecover = false;
    @AuraEnabled public CheckoutResult order;
  }

  public class CheckoutResult {
    @AuraEnabled public Id cartId;
    @AuraEnabled public List<Jewellery_Order_Item__c> items;
    @AuraEnabled public Id orderId;
    @AuraEnabled public Id paymentId;
    @AuraEnabled public String orderNumber;
    @AuraEnabled public Decimal grandTotal;
    @AuraEnabled public String orderStatus;
    @AuraEnabled public String paymentStatus;
    @AuraEnabled public String message;
    @AuraEnabled public String shippingAddress;
    @AuraEnabled public String shippingCity;
    @AuraEnabled public String shippingState;
    @AuraEnabled public String shippingPostalCode;
    @AuraEnabled public String shippingCountry;
    @AuraEnabled public String reconciliationState;
  }

  // ==========================================
  // CHECKOUT RECOVERY
  // ==========================================

  @AuraEnabled
  public static RecoveryResult checkoutRecovery(Id paymentId) {
    RecoveryResult result = new RecoveryResult();

    CheckoutResult restored;

    if (paymentId == null) {
      restored = GVCheckoutEngine.resume();

      if (restored == null) {
        result.state = 'Ready';
        result.message = 'Ready for checkout.';
        return result;
      }

      paymentId = restored.paymentId;
    }

    Payment__c p = GVCheckoutEngine.ownedPayment(paymentId);

    result.order = restored == null
      ? new CheckoutResult()
      : restored;

    result.order.paymentId = p.Id;
    result.order.cartId =
      p.Jewellery_Order__r.Shopping_Cart__c;
    result.order.orderId = p.Jewellery_Order__c;
    result.order.orderNumber =
      p.Jewellery_Order__r.Name;
    result.order.grandTotal =
      p.Jewellery_Order__r.Grand_Total__c;
    result.order.orderStatus =
      p.Jewellery_Order__r.Order_Status__c;
    result.order.paymentStatus =
      p.Jewellery_Order__r.Payment_Status__c;

    // Already confirmed.
    if (
      p.Payment_Status__c == 'Success' &&
      p.Jewellery_Order__r.Payment_Status__c == 'Paid' &&
      p.Jewellery_Order__r.Order_Status__c == 'Confirmed'
    ) {
      result.state = 'Confirmed';
      result.message = 'Payment confirmed.';
      return result;
    }

    // Already cancelled.
    if (
      p.Jewellery_Order__r.Order_Status__c == 'Cancelled'
    ) {
      result.state = 'Cancelled';
      result.message = 'Checkout cancelled.';
      return result;
    }

    result.state = 'Uncertain';
    result.message = 'Payment status is being verified.';

    if (
      p.Payment_Status__c != 'Pending' ||
      p.Jewellery_Order__r.Order_Status__c != 'pending' ||
      p.Jewellery_Order__r.Payment_Status__c != 'Pending'
    ) {
      return result;
    }

    // Never retry a payment already received.
    if (
      !String.isBlank(p.Transaction_ID__c) ||
      !String.isBlank(
        p.Razorpay_Verified_Payment_ID__c
      ) ||
      (
        !String.isBlank(p.Reconciliation_State__c) &&
        p.Reconciliation_State__c
          .toLowerCase()
          .contains('captured')
      )
    ) {
      result.state = 'Review';
      result.message =
        'Payment received. Order confirmation is pending.';
      return result;
    }

    // Initialization with an unknown outcome
    // must not create another Razorpay order.
    if (
      p.Initialization_State__c == 'Unknown' ||
      p.Initialization_State__c == 'Review required' ||
      (
        !String.isBlank(p.Reconciliation_State__c) &&
        (
          p.Reconciliation_State__c
            .toLowerCase()
            .contains('review required') ||
          p.Reconciliation_State__c
            .toLowerCase()
            .contains('unknown')
        )
      )
    ) {
      result.state = 'Review';
      result.message =
        'Checking the existing Razorpay payment.';
      return result;
    }

    // No gateway order or initialization job:
    // this draft is safe to cancel or continue.
    result.canCancel =
      String.isBlank(p.Razorpay_Order_ID__c) &&
      String.isBlank(p.Initialization_Job__c) &&
      (
        String.isBlank(p.Initialization_State__c) ||
        p.Initialization_State__c == 'New'
      );

    if (result.canCancel) {
      result.state = 'Interrupted';
      result.canRetry = true;
      result.message = 'Ready to continue secure payment.';
      return result;
    }

    Payment__c timing = [
      SELECT
        Last_Checked_At__c,
        Reconciliation_Requested_At__c
      FROM Payment__c
      WHERE Id = :p.Id
      WITH SYSTEM_MODE
    ];

    // A reconciliation request is still in progress.
    if (
      timing.Reconciliation_Requested_At__c != null &&
      (
        timing.Last_Checked_At__c == null ||
        timing.Last_Checked_At__c <
          timing.Reconciliation_Requested_At__c
      ) &&
      timing.Reconciliation_Requested_At__c >
        System.now().addMinutes(-1)
    ) {
      return result;
    }

    // Retry only an existing Razorpay order after
    // a recent successful gateway reconciliation.
    if (
      !String.isBlank(p.Razorpay_Order_ID__c) &&
      p.Initialization_State__c == 'Ready' &&
      p.Reconciliation_State__c == 'Unpaid - verified' &&
      timing.Last_Checked_At__c != null &&
      timing.Last_Checked_At__c >
        System.now().addMinutes(-1) &&
      (
        timing.Reconciliation_Requested_At__c == null ||
        timing.Last_Checked_At__c >=
          timing.Reconciliation_Requested_At__c
      )
    ) {
      result.state = 'Interrupted';
      result.canRetry = true;
      result.message =
        'You can resume your existing secure payment.';
    }

    return result;
  }

  // ==========================================
  // CANCEL SAFELY UNINITIALIZED CHECKOUT
  // ==========================================

  @AuraEnabled
  public static RecoveryResult cancelUnpaidCheckout(Id paymentId) {
    Payment__c pre = GVCheckoutEngine.ownedPayment(paymentId);

    GVCheckoutEngine.lockCustomer(
      pre.Jewellery_Order__r.Customer__c
    );

    List<Shopping_Cart__c> carts = [
      SELECT Id
      FROM Shopping_Cart__c
      WHERE Id IN (
        SELECT Shopping_Cart__c
        FROM Jewellery_Order__c
        WHERE Id = :pre.Jewellery_Order__c
      )
      WITH SYSTEM_MODE
      FOR UPDATE
    ];

    Jewellery_Order__c orderRecord = [
      SELECT
        Id,
        Order_Status__c,
        Payment_Status__c
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
        Razorpay_Verified_Payment_ID__c,
        Razorpay_Order_ID__c,
        Initialization_State__c,
        Initialization_Job__c,
        Reconciliation_State__c
      FROM Payment__c
      WHERE Id = :paymentId
      WITH SYSTEM_MODE
      FOR UPDATE
    ];

    RecoveryResult result = checkoutRecovery(paymentId);

    if (
      result.state == 'Confirmed' ||
      result.state == 'Cancelled'
    ) {
      return result;
    }

    // Cancellation is allowed only before a
    // gateway initialization could have begun.
    if (
      !result.canCancel ||
      carts.isEmpty() ||
      payment.Payment_Status__c != 'Pending' ||
      orderRecord.Order_Status__c != 'pending' ||
      orderRecord.Payment_Status__c != 'Pending' ||
      !String.isBlank(payment.Transaction_ID__c) ||
      !String.isBlank(
        payment.Razorpay_Verified_Payment_ID__c
      ) ||
      !String.isBlank(payment.Razorpay_Order_ID__c) ||
      !String.isBlank(payment.Initialization_Job__c) ||
      (
        !String.isBlank(payment.Initialization_State__c) &&
        payment.Initialization_State__c != 'New'
      ) ||
      (
        !String.isBlank(payment.Reconciliation_State__c) &&
        payment.Reconciliation_State__c
          .toLowerCase()
          .contains('captured')
      )
    ) {
      result.canRetry = false;
      result.state = 'Uncertain';
      result.message =
        'An existing payment needs verification.';
      return result;
    }

    // Preserve legacy reservation compatibility.
    Set<Id> activeReservations = new Set<Id>();

    for (Stock_Reservation__c reservation : [
      SELECT Id
      FROM Stock_Reservation__c
      WHERE Jewellery_Order__c = :orderRecord.Id
        AND Reservation_Status__c = 'Active'
      WITH SYSTEM_MODE
    ]) {
      activeReservations.add(reservation.Id);
    }

    Savepoint sp = Database.setSavepoint();

    try {
      if (!activeReservations.isEmpty()) {
        GVInventoryService.change(
          activeReservations,
          false
        );
      }

      orderRecord.Order_Status__c = 'Cancelled';
      orderRecord.Payment_Status__c = 'Failed';
      payment.Payment_Status__c = 'Failed';

      update as system orderRecord;
      update as system payment;

    } catch (Exception e) {
      Database.rollback(sp);
      throw new AuraHandledException(e.getMessage());
    }

    return checkoutRecovery(paymentId);
  }

  // ==========================================
  // PREPARE ONLINE ORDER
  // ==========================================

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

  // ==========================================
  // REQUEST GATEWAY RECONCILIATION
  // ==========================================

  @AuraEnabled
  public static void requestReconciliation(Id paymentId) {
    Payment__c pre = GVCheckoutEngine.ownedPayment(paymentId);

    GVCheckoutEngine.lockCustomer(
      pre.Jewellery_Order__r.Customer__c
    );

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
      (
        p.Reconciliation_Requested_At__c != null &&
        p.Reconciliation_Requested_At__c >
          System.now().addMinutes(-1) &&
        (
          p.Last_Checked_At__c == null ||
          p.Last_Checked_At__c <
            p.Reconciliation_Requested_At__c
        )
      )
    ) {
      return;
    }

    p.Reconciliation_Requested_At__c = System.now();
    update as system p;

    System.enqueueJob(
      new GVGatewayWorker(p.Id, 'recover')
    );
  }
}
