
/**
 * GOLDVUEE | RAZORPAY PAYMENT CONTROLLER
 *
 * Reservation-free checkout architecture.
 *
 * - No stock reservation required to start Razorpay.
 * - Reuses an existing initialized gateway order.
 * - Prevents duplicate initialization jobs.
 * - Protects captured and confirmed payments.
 * - Keeps verification and finalization in existing services.
 */
public without sharing class GVPaymentController {

  public class PaymentResult {
    @AuraEnabled public Id paymentId;
    @AuraEnabled public Id orderId;
    @AuraEnabled public String razorpayOrderId;
    @AuraEnabled public Long amountPaise;
    @AuraEnabled public String currencyCode;
    @AuraEnabled public String message;
    @AuraEnabled public String state;
  }

  @AuraEnabled
  public static PaymentResult initiatePayment(Id paymentId) {

    if (paymentId == null) {
      throw new AuraHandledException(
        'Payment ID is required.'
      );
    }

    // Identify and authorize the customer.
    Payment__c pre = GVCheckoutEngine.ownedPayment(paymentId);

    // Serialize checkout operations for this customer.
    GVCheckoutEngine.lockCustomer(
      pre.Jewellery_Order__r.Customer__c
    );

    // Ensure delivery details are complete.
    GVCheckoutEngine.requireDelivery(
      pre.Jewellery_Order__c
    );

    // Lock the payment before deciding whether to initialize.
    Payment__c payment = [
      SELECT
        Id,
        Jewellery_Order__c,
        Payment_Amount__c,
        Payment_Status__c,
        Razorpay_Order_ID__c,
        Razorpay_Verified_Payment_ID__c,
        Transaction_ID__c,
        Initialization_State__c,
        Initialization_Job__c,
        Reconciliation_State__c,
        Last_Checked_At__c
      FROM Payment__c
      WHERE Id = :paymentId
      WITH SYSTEM_MODE
      FOR UPDATE
    ];

    Jewellery_Order__c orderRecord = [
      SELECT
        Id,
        Order_Status__c,
        Payment_Status__c,
        Grand_Total__c
      FROM Jewellery_Order__c
      WHERE Id = :payment.Jewellery_Order__c
      WITH SYSTEM_MODE
    ];

    // Never charge an already confirmed order.
    if (
      payment.Payment_Status__c == 'Success' ||
      orderRecord.Payment_Status__c == 'Paid' ||
      orderRecord.Order_Status__c == 'Confirmed'
    ) {
      throw new AuraHandledException(
        'This order is already paid. View My Orders.'
      );
    }

    if (
      payment.Payment_Status__c != 'Pending' ||
      orderRecord.Order_Status__c != 'pending' ||
      orderRecord.Payment_Status__c != 'Pending'
    ) {
      throw new AuraHandledException(
        'This checkout is no longer awaiting payment.'
      );
    }

    // Ensure the Razorpay amount matches Salesforce.
    if (
      payment.Payment_Amount__c == null ||
      payment.Payment_Amount__c <= 0 ||
      payment.Payment_Amount__c != orderRecord.Grand_Total__c
    ) {
      throw new AuraHandledException(
        'Payment amount does not match the order.'
      );
    }

    // Protect a payment that may already be captured.
    if (
      !String.isBlank(payment.Transaction_ID__c) ||
      !String.isBlank(
        payment.Razorpay_Verified_Payment_ID__c
      ) ||
      (
        !String.isBlank(payment.Reconciliation_State__c) &&
        payment.Reconciliation_State__c
          .toLowerCase()
          .contains('captured')
      )
    ) {
      throw new AuraHandledException(
        'Payment has been received or requires confirmation. ' +
        'Please check My Orders before paying again.'
      );
    }

    // Do not start a new charge when initialization
    // or reconciliation has an ambiguous outcome.
    if (
      payment.Initialization_State__c == 'Unknown' ||
      payment.Initialization_State__c == 'Review required' ||
      (
        !String.isBlank(payment.Reconciliation_State__c) &&
        (
          payment.Reconciliation_State__c
            .toLowerCase()
            .contains('review required') ||
          payment.Reconciliation_State__c
            .toLowerCase()
            .contains('unknown')
        )
      )
    ) {
      throw new AuraHandledException(
        'The previous payment outcome requires verification.'
      );
    }

    // No stock reservation or reservationIds() call.

    // If the gateway order already exists,
    // reuse it rather than create a duplicate.
    if (!String.isBlank(payment.Razorpay_Order_ID__c)) {

      if (
        payment.Initialization_State__c != 'Ready' &&
        payment.Reconciliation_State__c != 'Unpaid - verified'
      ) {
        throw new AuraHandledException(
          'The previous payment must be verified before retrying.'
        );
      }

      return result(payment);
    }

    // First initialization is queued exactly once.
    if (
      String.isBlank(payment.Initialization_State__c) ||
      payment.Initialization_State__c == 'New'
    ) {

      payment.Initialization_State__c = 'Queued';
      payment.Last_Checked_At__c = System.now();

      payment.Initialization_Job__c = System.enqueueJob(
        new GVGatewayWorker(
          payment.Id,
          'initialize'
        )
      );

      update as system payment;
    }

    return result(payment);
  }

  @AuraEnabled
  public static PaymentResult paymentState(Id paymentId) {

    if (paymentId == null) {
      throw new AuraHandledException(
        'Payment ID is required.'
      );
    }

    return result(
      GVCheckoutEngine.ownedPayment(paymentId)
    );
  }

  private static PaymentResult result(Payment__c p) {

    PaymentResult r = new PaymentResult();

    r.paymentId = p.Id;
    r.orderId = p.Jewellery_Order__c;
    r.razorpayOrderId = p.Razorpay_Order_ID__c;

    r.amountPaise = p.Payment_Amount__c == null
      ? 0
      : (p.Payment_Amount__c * 100).longValue();

    r.currencyCode = 'INR';

    if (p.Payment_Status__c == 'Success') {
      r.state = 'Confirmed';
    } else if (p.Payment_Status__c == 'Failed') {
      r.state = 'Cancelled';
    } else if (
      !String.isBlank(p.Transaction_ID__c) ||
      (
        !String.isBlank(p.Reconciliation_State__c) &&
        (
          p.Reconciliation_State__c
            .toLowerCase()
            .contains('captured') ||
          p.Reconciliation_State__c
            .toLowerCase()
            .contains('review required')
        )
      ) ||
      p.Initialization_State__c == 'Unknown' ||
      p.Initialization_State__c == 'Review required'
    ) {
      r.state = 'Review';
    } else if (!String.isBlank(p.Razorpay_Order_ID__c)) {
      r.state = 'Ready';
    } else {
      r.state = String.isBlank(p.Initialization_State__c)
        ? 'New'
        : p.Initialization_State__c;
    }

    r.message = String.isBlank(p.Reconciliation_State__c)
      ? 'Payment initialization ' + r.state
      : p.Reconciliation_State__c;

    return r;
  }
}
