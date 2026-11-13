
/**
 * GOLDVUEE | RAZORPAY GATEWAY WORKER
 *
 * Simplified payment initialization:
 * - No inventory reservation required for Razorpay.
 * - No reservation renewal for unpaid payments.
 * - Captured payments use the existing trusted finalization.
 * - Uncertain gateway results remain protected.
 * - Legacy reservation cleanup is retained temporarily.
 *
 * IMPORTANT:
 * Deploy together with the updated checkout engine,
 * inventory service and payment/recovery controllers.
 */
public without sharing class GVGatewayWorker
  implements Queueable, Database.AllowsCallouts {

  private Id paymentId;
  private String operation;
  private List<Id> remaining;

  public GVGatewayWorker(Id pid, String op) {
    paymentId = pid;
    operation = op;
  }

  public GVGatewayWorker(List<Id> ids) {
    remaining = ids.clone();
    paymentId = remaining.remove(0);
    operation = 'reconcile';
  }

  public void execute(QueueableContext context) {

    Payment__c p = [
      SELECT
        Id,
        Jewellery_Order__c,
        Payment_Amount__c,
        Payment_Status__c,
        Razorpay_Order_ID__c,
        Initialization_State__c,
        Initialization_Job__c,
        Jewellery_Order__r.Customer__c
      FROM Payment__c
      WHERE Id = :paymentId
      WITH SYSTEM_MODE
    ];

    if (p.Payment_Status__c != 'Pending') {
      next();
      return;
    }

    try {

      // ==========================================
      // 1. INITIALIZE RAZORPAY
      // ==========================================

      if (operation == 'initialize') {

        if (
          p.Initialization_State__c != 'Queued' ||
          p.Initialization_Job__c != context.getJobId() ||
          !String.isBlank(p.Razorpay_Order_ID__c)
        )
          return;

        // No inventory reservation is required here.

        GVRazorpayService.RazorpayOrder created =
          GVRazorpayService.createOrder(
            p.Payment_Amount__c,
            String.valueOf(p.Id)
          );

        GVCheckoutEngine.lockCustomer(
          p.Jewellery_Order__r.Customer__c
        );

        Payment__c locked = [
          SELECT
            Id,
            Razorpay_Order_ID__c,
            Payment_Status__c
          FROM Payment__c
          WHERE Id = :p.Id
          WITH SYSTEM_MODE
          FOR UPDATE
        ];

        if (
          locked.Payment_Status__c != 'Pending' ||
          !String.isBlank(locked.Razorpay_Order_ID__c)
        )
          return;

        locked.Razorpay_Order_ID__c =
          created.razorpayOrderId;

        locked.Initialization_State__c = 'Ready';
        locked.Last_Checked_At__c = System.now();

        update as system locked;

      } else {

        // ==========================================
        // 2. FIND EXISTING RAZORPAY ORDER
        // ==========================================

        String orderId = p.Razorpay_Order_ID__c;

        if (String.isBlank(orderId)) {

          if (
            p.Initialization_State__c == 'New' ||
            String.isBlank(p.Initialization_State__c)
          ) {
            expireUnpaid(p);
            return;
          }

          orderId = GVRazorpayService.findOrder(
            String.valueOf(p.Id),
            p.Payment_Amount__c
          );

          if (String.isBlank(orderId)) {

            mark(
              'Review required',
              'Gateway initialization outcome unknown; do not retry payment.'
            );

            return;
          }
        }

        // ==========================================
        // 3. CHECK CAPTURED PAYMENT
        // ==========================================

        GVRazorpayService.RazorpayPaymentDetails gateway =
          GVRazorpayService.capturedForOrder(orderId);

        Boolean retryAllowed =
          operation != 'recover' ||
          gateway != null ||
          GVRazorpayService.orderAllowsRetry(
            orderId,
            p.Payment_Amount__c
          );

        if (!retryAllowed) {

          mark(
            'Review required',
            'Gateway order is not available for retry.'
          );

          return;
        }

        // All gateway callouts finish before DML.

        GVCheckoutEngine.lockCustomer(
          p.Jewellery_Order__r.Customer__c
        );

        Payment__c locked = [
          SELECT
            Id,
            Razorpay_Order_ID__c
          FROM Payment__c
          WHERE Id = :p.Id
          WITH SYSTEM_MODE
          FOR UPDATE
        ];

        if (String.isBlank(locked.Razorpay_Order_ID__c)) {

          locked.Razorpay_Order_ID__c = orderId;
          locked.Initialization_State__c = 'Ready';

          update as system locked;
        }

        // ==========================================
        // 4. PAYMENT SUCCESS
        // ==========================================

        if (gateway != null) {

          Savepoint sp = Database.setSavepoint();

          try {

            // Finalization must verify and deduct stock
            // exactly once. No reservation renewal here.

            GVCheckoutEngine.finalizeCaptured(
              p.Id,
              gateway
            );

          } catch (Exception e) {

            Database.rollback(sp);

            mark(
              'Review required',
              'Captured payment requires order review.'
            );
          }

        }

        // ==========================================
        // 5. UNPAID PAYMENT RECOVERY
        // ==========================================

        else if (operation == 'recover') {

          // Gateway has been queried.
          // Reuse only an eligible existing Razorpay
          // order. Do not create inventory reservations.

          update as system new Payment__c(
            Id = p.Id,
            Initialization_State__c = 'Ready',
            Reconciliation_State__c = 'Unpaid - verified',
            Last_Checked_At__c = System.now()
          );

        }

        // ==========================================
        // 6. NORMAL RECONCILIATION
        // ==========================================

        else {

          // No captured payment found at this time.
          // This does not prove a payable Razorpay
          // order can never receive a late capture.

          p.Razorpay_Order_ID__c = orderId;

          expireUnpaid(p);
        }
      }

    } catch (Exception e) {

      mark(
        operation == 'initialize'
          ? 'Unknown'
          : 'Review required',
        'Gateway reconciliation pending.'
      );

    } finally {

      next();
    }
  }

  // ==========================================
  // NEXT RECONCILIATION JOB
  // ==========================================

  private void next() {

    if (remaining != null && !remaining.isEmpty()) {

      System.enqueueJob(
        new GVGatewayWorker(remaining)
      );
    }
  }

  // ==========================================
  // PAYMENT RECONCILIATION STATUS
  // ==========================================

  private void mark(String state, String reason) {

    update as system new Payment__c(
      Id = paymentId,
      Initialization_State__c = state,
      Reconciliation_State__c = reason,
      Last_Checked_At__c = System.now()
    );
  }

  // ==========================================
  // LEGACY UNPAID CHECKOUT HANDLING
  // ==========================================

  private static void expireUnpaid(Payment__c p) {

    // An ambiguous initialization may already have
    // created a payable Razorpay order.

    if (
      String.isBlank(p.Razorpay_Order_ID__c) &&
      (
        !String.isBlank(p.Initialization_Job__c) ||
        (
          !String.isBlank(p.Initialization_State__c) &&
          p.Initialization_State__c != 'New'
        )
      )
    )
      return;

    GVCheckoutEngine.lockCustomer(
      p.Jewellery_Order__r.Customer__c
    );

    List<Shopping_Cart__c> carts = [
      SELECT Id
      FROM Shopping_Cart__c
      WHERE Id IN (
        SELECT Shopping_Cart__c
        FROM Jewellery_Order__c
        WHERE Id = :p.Jewellery_Order__c
      )
      WITH SYSTEM_MODE
      FOR UPDATE
    ];

    Jewellery_Order__c o = [
      SELECT
        Id,
        Order_Status__c
      FROM Jewellery_Order__c
      WHERE Id = :p.Jewellery_Order__c
      WITH SYSTEM_MODE
      FOR UPDATE
    ];

    Payment__c locked = [
      SELECT
        Id,
        Payment_Status__c,
        Razorpay_Order_ID__c,
        Transaction_ID__c,
        Reconciliation_State__c
      FROM Payment__c
      WHERE Id = :p.Id
      WITH SYSTEM_MODE
      FOR UPDATE
    ];

    if (
      locked.Payment_Status__c != 'Pending' ||
      !String.isBlank(locked.Transaction_ID__c) ||
      (
        !String.isBlank(locked.Reconciliation_State__c) &&
        locked.Reconciliation_State__c
          .toLowerCase()
          .contains('captured')
      )
    )
      return;

    if (!String.isBlank(p.Razorpay_Order_ID__c)) {

      locked.Reconciliation_State__c =
        'Unpaid - verified';
    }

    // Legacy reservation records only.
    // New checkouts will not create these.

    Set<Id> active = new Set<Id>();
    Boolean allExpired = true;

    for (Stock_Reservation__c r : [
      SELECT
        Id,
        Expires_At__c
      FROM Stock_Reservation__c
      WHERE Jewellery_Order__c = :o.Id
        AND Reservation_Status__c = 'Active'
      WITH SYSTEM_MODE
    ]) {

      active.add(r.Id);

      if (
        r.Expires_At__c == null ||
        r.Expires_At__c > System.now()
      ) {
        allExpired = false;
      }
    }

    if (allExpired && !active.isEmpty()) {

      // Do not release a legacy hold automatically
      // while its Razorpay order may still be payable.

      if (!String.isBlank(locked.Razorpay_Order_ID__c)) {

        locked.Reconciliation_State__c =
          'Expired - payment review required';

        locked.Last_Checked_At__c = System.now();

        update as system locked;

        return;
      }

      GVInventoryService.change(active, false);

      if (
        String.isBlank(locked.Razorpay_Order_ID__c) &&
        (
          p.Initialization_State__c == 'New' ||
          String.isBlank(p.Initialization_State__c)
        )
      ) {

        locked.Payment_Status__c = 'Failed';

        o.Order_Status__c = 'Cancelled';
        o.Payment_Status__c = 'Failed';

        update as system o;
      }

      locked.Reconciliation_State__c =
        'Expired - stock released';
    }

    locked.Last_Checked_At__c = System.now();

    update as system locked;
  }
}
