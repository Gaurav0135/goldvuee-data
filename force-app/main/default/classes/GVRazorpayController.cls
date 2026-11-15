/** One hosted-payment implementation. Callouts run only after the authorizing transaction commits. */
public without sharing class GVRazorpayController {
  public class Result {
    @AuraEnabled
    public Id paymentId;
    @AuraEnabled
    public Id orderId;
    @AuraEnabled
    public Id cartId;
    @AuraEnabled
    public String orderNumber;
    @AuraEnabled
    public String state;
    @AuraEnabled
    public String paymentStatus;
    @AuraEnabled
    public String fulfillment;
    @AuraEnabled
    public String paymentUrl;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public String lastFailureState;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public Boolean matchesCurrentCart;
    @AuraEnabled
    public Long paymentExpiresAt;
    @AuraEnabled
    public Long serverNow;
    @AuraEnabled
    public Boolean expiredByTimer;
  }
  @AuraEnabled
  public static Result paymentStatus(Id paymentId) {
    return result(
      GVCheckoutService.payment(paymentId, GVCheckoutService.customer())
    );
  }
  @AuraEnabled
  public static Result startPayment(Id paymentId) {
    Id cid = GVCheckoutService.customer();
    GVCheckoutService.lockCustomer(cid);
    Payment__c p = GVCheckoutService.payment(paymentId, cid);
    if (p.Payment_Status__c == 'Success')
      return result(p);
    if (p.Jewellery_Order__r.Payment_Status__c == 'Paid')
      throw new AuraHandledException(
        'This order is already paid. View My Orders.'
      );
    if (
      p.Payment_Status__c != 'Pending' ||
      p.Jewellery_Order__r.Order_Status__c != 'pending' ||
      p.Payment_Amount__c != p.Jewellery_Order__r.Grand_Total__c
    )
      throw new AuraHandledException('This order is not awaiting payment.');
    configured();
    GVCheckoutService.stock(p.Jewellery_Order__c);
    GVCheckoutService.Attempt a = GVCheckoutService.attempt(p);
    if (a.version == 2 && a.state == 'New') {
      Shopping_Cart__c current = GVCheckoutService.cart(cid, false);
      if (
        current != null &&
        GVCheckoutService.sameSelection(current.Id, p.Jewellery_Order__c)
      )
        a.cartId = GVCheckoutService.freezeCart(
          cid,
          p.Jewellery_Order__c,
          current.Id
        );
      else if (a.retryOf == null)
        throw new AuraHandledException(
          'Your bag changed. Review your current bag before paying.'
        );
      a.expirySeconds = 120;
      enqueue(p, a, 'Create');
    } else if (a.state == 'Ready' || a.state == 'Unknown')
      enqueue(p, a, 'Refresh');
    return result(GVCheckoutService.payment(p.Id, cid));
  }
  @AuraEnabled
  public static Result refreshPayment(Id paymentId) {
    return action(paymentId, 'Refresh');
  }
  @AuraEnabled
  public static Result cancelPayment(Id paymentId) {
    return action(paymentId, 'Cancel');
  }
  @AuraEnabled
  public static Result retryPayment(Id paymentId) {
    Id cid = GVCheckoutService.customer();
    GVCheckoutService.lockCustomer(cid);
    Payment__c old = GVCheckoutService.payment(paymentId, cid);
    if (old.Payment_Status__c == 'Success')
      return result(old);
    GVCheckoutService.Attempt prior = GVCheckoutService.attempt(old);
    if (old.Payment_Status__c == 'Pending')
      return startPayment(old.Id);
    if (
      prior.version != 2 ||
      old.Payment_Status__c != 'Failed' ||
      !new Set<String>{ 'Cancelled', 'Expired' }.contains(prior.state)
    )
      throw new AuraHandledException(
        'Verify the previous payment before retrying.'
      );
    List<Payment__c> pending = [
      SELECT Id
      FROM Payment__c
      WHERE
        Jewellery_Order__c = :old.Jewellery_Order__c
        AND Payment_Status__c = 'Pending'
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (!pending.isEmpty())
      return startPayment(pending[0].Id);
    // Only expiry-managed, verified-unpaid cancellations may reopen their order for retry.
    if (prior.expirySeconds == 120) {
      Jewellery_Order__c orderRecord = [
        SELECT Id, Order_Status__c, Payment_Status__c
        FROM Jewellery_Order__c
        WHERE Id = :old.Jewellery_Order__c
        WITH SYSTEM_MODE
        FOR UPDATE
      ];
      if (
        orderRecord.Payment_Status__c == 'Paid' ||
        [
          SELECT COUNT()
          FROM Payment__c
          WHERE
            Jewellery_Order__c = :orderRecord.Id
            AND Payment_Status__c = 'Success'
          WITH SYSTEM_MODE
        ] > 0
      )
        throw new AuraHandledException(
          'This order is already paid. View My Orders.'
        );
      if (orderRecord.Order_Status__c == 'Cancelled') {
        orderRecord.Order_Status__c = 'pending';
        update as system orderRecord;
      }
    }
    GVCheckoutService.Attempt next = new GVCheckoutService.Attempt();
    next.fingerprint = prior.fingerprint;
    next.retryOf = old.Id;
    Payment__c p = new Payment__c(
      Jewellery_Order__c = old.Jewellery_Order__c,
      Payment_Amount__c = old.Payment_Amount__c,
      Payment_Status__c = 'Pending',
      Gateway_Response__c = JSON.serialize(next)
    );
    insert as system p;
    return startPayment(p.Id);
  }
  private static Result action(Id pid, String operation) {
    Id cid = GVCheckoutService.customer();
    GVCheckoutService.lockCustomer(cid);
    Payment__c p = GVCheckoutService.payment(pid, cid);
    queueAction(p, operation);
    return result(GVCheckoutService.payment(pid, cid));
  }
  /** Internal API for the existing administrator operations controller; no customer entry point. */
  public static void reconcileForAdmin(Id pid) {
    Payment__c owner = [
      SELECT Jewellery_Order__r.Customer__c
      FROM Payment__c
      WHERE Id = :pid
      WITH SYSTEM_MODE
    ];
    GVCheckoutService.lockCustomer(owner.Jewellery_Order__r.Customer__c);
    queueAction(
      GVCheckoutService.payment(pid, owner.Jewellery_Order__r.Customer__c),
      'Refresh'
    );
  }
  private static void queueAction(Payment__c p, String operation) {
    if (p.Payment_Status__c == 'Success')
      return;
    GVCheckoutService.Attempt a = GVCheckoutService.attempt(p);
    if (operation == 'Cancel' && a.version == 2 && a.state == 'New') {
      a.state = 'Cancelled';
      p.Payment_Status__c = 'Failed';
      p.Failure_Reason__c = 'Cancelled before a gateway request was authorized.';
      p.Gateway_Response__c = JSON.serialize(a);
      update as system p;
      return;
    }
    if (p.Payment_Status__c != 'Pending')
      return;
    if (
      new Set<String>{ 'Queued', 'Checking', 'Cancelling' }.contains(a.state)
    ) {
      // Recover a failed/crashed job by reference lookup, never by repeating POST.
      if (String.isBlank(a.jobId))
        return;
      List<AsyncApexJob> jobs = [
        SELECT Status
        FROM AsyncApexJob
        WHERE Id = :a.jobId
        WITH SYSTEM_MODE
      ];
      if (
        jobs.isEmpty() ||
        !new Set<String>{ 'Failed', 'Aborted', 'Completed' }
          .contains(jobs[0].Status)
      )
        return;
    }
    if (operation == 'Cancel' && String.isBlank(a.linkId))
      throw new AuraHandledException(
        'This previous attempt cannot safely be cancelled. Refresh status or contact support.'
      );
    if (a.state == 'New')
      return;
    configured();
    enqueue(p, a, operation);
  }
  private static void configured() {
    if (
      [
        SELECT COUNT()
        FROM GV_Payment_Config__c
        WHERE Name = 'RazorpayTest'
        WITH SYSTEM_MODE
      ] != 1
    )
      throw new AuraHandledException(
        'Secure test payments need administrator setup. You can continue shopping.'
      );
  }
  private static void enqueue(
    Payment__c p,
    GVCheckoutService.Attempt a,
    String operation
  ) {
    a.state = operation == 'Create'
      ? 'Queued'
      : operation == 'Cancel' ? 'Cancelling' : 'Checking';
    // A status lookup does not invalidate a verified failed transaction.
    a.jobId = null;
    p.Gateway_Response__c = JSON.serialize(a);
    update as system p;
    a.jobId = System.enqueueJob(new GatewayJob(p.Id, operation));
    p.Gateway_Response__c = JSON.serialize(a);
    update as system p;
  }
  private static Result result(Payment__c p) {
    GVCheckoutService.Attempt a = GVCheckoutService.attempt(p);
    Result r = new Result();
    r.paymentId = p.Id;
    r.orderId = p.Jewellery_Order__c;
    r.cartId = a.cartId;
    r.orderNumber = p.Jewellery_Order__r.Name;
    r.amount = p.Payment_Amount__c;
    r.state = a.state;
    r.paymentStatus = p.Payment_Status__c;
    r.fulfillment = a.fulfillment;
    r.lastFailureState = a.lastFailureState;
    r.serverNow = System.now().getTime();
    r.paymentExpiresAt = a.expirySeconds == 120 &&
      a.linkCreatedAt != null
      ? (a.linkCreatedAt + 120) * 1000
      : null;
    r.expiredByTimer =
      a.expiryRequested == true &&
      p.Payment_Status__c == 'Failed';
    if (
      a.state == 'Ready' &&
      p.Payment_Status__c == 'Pending' &&
      (r.paymentExpiresAt == null ||
      r.paymentExpiresAt > r.serverNow)
    )
      r.paymentUrl = a.url;
    Shopping_Cart__c current = GVCheckoutService.cart(
      p.Jewellery_Order__r.Customer__c,
      false
    );
    r.matchesCurrentCart =
      current != null &&
      GVCheckoutService.sameSelection(current.Id, p.Jewellery_Order__c);
    r.message = p.Payment_Status__c == 'Success'
      ? (a.fulfillment == 'Confirmed'
          ? 'Payment verified. Your order is confirmed.'
          : 'Payment received. Fulfillment needs admin review; do not pay again.')
      : r.expiredByTimer
          ? 'Payment time expired. The unpaid link is closed; you may retry safely.'
          : a.lastFailureState == 'failed' &&
              a.state == 'Ready'
              ? 'The last transaction failed. Retry safely with the existing payment link.'
              : a.state == 'Cancelled' ||
                  a.state == 'Expired'
                  ? 'This payment link is closed. You may retry safely.'
                  : a.state == 'Unknown'
                      ? 'Payment not confirmed yet. Refresh verification before retrying.'
                      : a.state == 'Legacy review'
                          ? 'A historical payment needs verification. Refresh status or contact GoldVuee support.'
                          : a.state == 'Ready'
                              ? 'Secure Razorpay test payment is ready.'
                              : 'Payment is pending verification.';
    return r;
  }
  public class GatewayJob implements Queueable, Database.AllowsCallouts {
    private Id pid;
    private String operation;
    public GatewayJob(Id pid, String operation) {
      this.pid = pid;
      this.operation = operation;
    }
    public void execute(QueueableContext context) {
      Payment__c p = [
        SELECT
          Id,
          Jewellery_Order__c,
          Payment_Status__c,
          Payment_Amount__c,
          Gateway_Response__c,
          Razorpay_Order_ID__c,
          Transaction_ID__c,
          Jewellery_Order__r.Customer__c,
          Jewellery_Order__r.Payment_Status__c
        FROM Payment__c
        WHERE Id = :pid
        WITH SYSTEM_MODE
      ];
      GVCheckoutService.Attempt a = GVCheckoutService.attempt(p);
      String expectedState = operation == 'Create'
        ? 'Queued'
        : operation == 'Cancel' ? 'Cancelling' : 'Checking';
      if (
        p.Payment_Status__c != 'Pending' ||
        a.state != expectedState ||
        (a.jobId != null &&
        context != null &&
        a.jobId != context.getJobId())
      )
        return;
      Savepoint paymentWrite;
      try {
        configured();
        Map<String, Object> link;
        Map<String, Object> evidence;
        if (operation == 'Create') {
          if (
            a.version != 2 ||
            p.Jewellery_Order__r.Payment_Status__c == 'Paid'
          )
            throw new GVCheckoutService.CheckoutException(
              'Order is not payable.'
            );
          link = request(
            'POST',
            '/v1/payment_links',
            new Map<String, Object>{
              'amount' => (p.Payment_Amount__c * 100).longValue(),
              'currency' => 'INR',
              'accept_partial' => false,
              'reference_id' => String.valueOf(pid),
              'description' => 'GoldVuee test order',
              'notify' => new Map<String, Object>{
                'email' => false,
                'sms' => false
              },
              'reminder_enable' => false,
              'notes' => new Map<String, Object>{
                'salesforce_order_id' => String.valueOf(p.Jewellery_Order__c),
                'salesforce_payment_id' => String.valueOf(pid)
              }
            }
          );
        } else if (a.linkId != null)
          link = request(
            'GET',
            '/v1/payment_links/' + gatewayId(a.linkId, 'plink_'),
            null
          );
        else if (a.version == 2) {
          Map<String, Object> found = request(
            'GET',
            '/v1/payment_links?reference_id=' + String.valueOf(pid),
            null
          );
          List<Object> links = (List<Object>) found.get('payment_links');
          if (links == null || links.size() != 1)
            throw new GVCheckoutService.CheckoutException(
              'Reference outcome is uncertain.'
            );
          link = (Map<String, Object>) links[0];
        } else {
          // Read-only reconciliation for historical standard orders; never a second creation path.
          Map<String, Object> payments = request(
            'GET',
            '/v1/orders/' + gatewayId(a.gatewayOrderId, 'order_') + '/payments',
            null
          );
          for (Object entry : (List<Object>) payments.get('items')) {
            Map<String, Object> row = (Map<String, Object>) entry;
            if (row.get('status') == 'captured') {
              if (evidence != null)
                throw new GVCheckoutService.CheckoutException(
                  'Multiple captures need review.'
                );
              evidence = request(
                'GET',
                '/v1/payments/' + gatewayId((String) row.get('id'), 'pay_'),
                null
              );
            }
          }
        }
        if (link != null) {
          validateLink(p, link, a.linkId);
          if (a.expirySeconds == 120) {
            ExpiryCheck checked = checkExpiry(p, a, link, operation);
            link = checked.link;
            evidence = checked.capture;
          }
          if (
            a.expirySeconds != 120 &&
            operation == 'Cancel' &&
            link.get('status') == 'created'
          ) {
            link = request(
              'POST',
              '/v1/payment_links/' +
                gatewayId((String) link.get('id'), 'plink_') +
                '/cancel',
              new Map<String, Object>()
            );
            validateLink(p, link, a.linkId);
          }
          if (link.get('status') == 'paid' && evidence == null) {
            if (
              GVCheckoutService.numberValue(link.get('amount_paid')) !=
              p.Payment_Amount__c * 100
            )
              throw new GVCheckoutService.CheckoutException(
                'Paid amount mismatch.'
              );
            List<Object> payments = (List<Object>) link.get('payments');
            if (payments == null || payments.size() != 1)
              throw new GVCheckoutService.CheckoutException(
                'Capture needs review.'
              );
            evidence = request(
              'GET',
              '/v1/payments/' +
              gatewayId(
                (String) ((Map<String, Object>) payments[0]).get('payment_id'),
                'pay_'
              ),
              null
            );
          }
        }
        // Every HTTP request has completed. Locks and DML start here.
        if (a.expirySeconds == 120)
          paymentWrite = Database.setSavepoint();
        GVCheckoutService.lockCustomer(p.Jewellery_Order__r.Customer__c);
        Payment__c latest = [
          SELECT
            Id,
            Payment_Status__c,
            Gateway_Response__c,
            Razorpay_Order_ID__c,
            Transaction_ID__c
          FROM Payment__c
          WHERE Id = :pid
          WITH SYSTEM_MODE
          FOR UPDATE
        ];
        GVCheckoutService.Attempt saved = GVCheckoutService.attempt(latest);
        if (
          latest.Payment_Status__c == 'Success' ||
          saved.state != a.state ||
          saved.jobId != a.jobId
        )
          return;
        if (link != null) {
          a.linkId = (String) link.get('id');
          a.url = (String) link.get('short_url');
          a.gatewayOrderId = (String) link.get('order_id');
          String status = (String) link.get('status');
          a.state = status == 'created'
            ? 'Ready'
            : status == 'paid'
                ? 'Verifying'
                : status == 'cancelled'
                    ? 'Cancelled'
                    : status == 'expired' ? 'Expired' : 'Unknown';
          if (
            evidence == null &&
            new Set<String>{ 'Cancelled', 'Expired' }.contains(a.state)
          ) {
            if (GVCheckoutService.numberValue(link.get('amount_paid')) != 0)
              throw new GVCheckoutService.CheckoutException(
                'Partial payment needs review.'
              );
            latest.Payment_Status__c = 'Failed';
            latest.Failure_Reason__c =
              'Gateway verified ' +
              a.state.toLowerCase() +
              ' with zero paid.';
          }
        } else
          a.state = evidence == null ? 'Legacy review' : 'Verifying';
        if (saved.lastFailurePaymentId != a.lastFailurePaymentId) {
          a.lastFailurePaymentId = saved.lastFailurePaymentId;
          a.lastFailureState = saved.lastFailureState;
        }
        latest.Gateway_Response__c = JSON.serialize(a);
        if (a.gatewayOrderId != null)
          latest.Razorpay_Order_ID__c = a.gatewayOrderId;
        update as system latest;
        if (evidence != null)
          GVCheckoutService.captured(pid, a.linkId, evidence);
        else if (a.expirySeconds == 120 && latest.Payment_Status__c == 'Failed')
          cancelUnpaidOrder(p.Jewellery_Order__c);
      } catch (Exception error) {
        if (paymentWrite != null)
          Database.rollback(paymentWrite);
        GVCheckoutService.lockCustomer(p.Jewellery_Order__r.Customer__c);
        Payment__c latest = [
          SELECT
            Id,
            Payment_Status__c,
            Gateway_Response__c,
            Razorpay_Order_ID__c,
            Transaction_ID__c
          FROM Payment__c
          WHERE Id = :pid
          WITH SYSTEM_MODE
          FOR UPDATE
        ];
        GVCheckoutService.Attempt saved = GVCheckoutService.attempt(latest);
        if (latest.Payment_Status__c == 'Success' || saved.jobId != a.jobId)
          return;
        saved.state = 'Unknown';
        latest.Gateway_Response__c = JSON.serialize(saved);
        latest.Failure_Reason__c = 'Gateway outcome requires verification. No replacement charge was created.';
        update as system latest;
      }
    }
  }
  private class ExpiryCheck {
    public Map<String, Object> link;
    public Map<String, Object> capture;
  }
  /** All evidence is obtained before DML; terminal flags alone never override a capture. */
  private static ExpiryCheck checkExpiry(
    Payment__c p,
    GVCheckoutService.Attempt a,
    Map<String, Object> link,
    String operation
  ) {
    // A paid link uses the existing captured-payment verification path even if timing is unavailable.
    if (link.get('status') == 'paid') {
      ExpiryCheck paid = new ExpiryCheck();
      paid.link = link;
      return paid;
    }
    Decimal created = GVCheckoutService.numberValue(link.get('created_at'));
    if (
      created == null ||
      created <= 0 ||
      created != created.setScale(0) ||
      created * 1000 > System.now().getTime() ||
      (a.linkCreatedAt != null &&
      a.linkCreatedAt != created.longValue()) ||
      (a.gatewayOrderId != null &&
      a.gatewayOrderId != link.get('order_id'))
    )
      throw new GVCheckoutService.CheckoutException(
        'Link creation evidence is uncertain.'
      );
    a.linkCreatedAt = created.longValue();
    Boolean due = System.now().getTime() >= (a.linkCreatedAt + 120) * 1000;
    ExpiryCheck checked = new ExpiryCheck();
    checked.link = link;
    String state = (String) link.get('status');
    if (
      !due &&
      operation != 'Cancel' &&
      state != 'cancelled' &&
      state != 'expired'
    )
      return checked;
    if (due)
      a.expiryRequested = true;
    checked.capture = orderCapture(p, link);
    if (checked.capture != null)
      return checked;
    if (
      GVCheckoutService.numberValue(link.get('amount_paid')) != 0 ||
      state == 'paid' ||
      state == 'partially_paid'
    )
      throw new GVCheckoutService.CheckoutException(
        'Payment amount needs verification; do not cancel.'
      );
    if (state == 'created' && (due || operation == 'Cancel')) {
      try {
        request(
          'POST',
          '/v1/payment_links/' +
            gatewayId((String) link.get('id'), 'plink_') +
            '/cancel',
          new Map<String, Object>()
        );
      } catch (Exception cancellationUnknown) {
        // A timeout or competing capture is not failure. Re-read the authoritative link.
      }
      link = request(
        'GET',
        '/v1/payment_links/' + gatewayId((String) link.get('id'), 'plink_'),
        null
      );
      validateLink(p, link, (String) checked.link.get('id'));
      if (
        link.get('created_at') == null ||
        GVCheckoutService.numberValue(link.get('created_at')) != created ||
        (checked.link.get('order_id') != null &&
        link.get('order_id') != checked.link.get('order_id'))
      )
        throw new GVCheckoutService.CheckoutException(
          'Cancellation evidence does not match.'
        );
      checked.link = link;
      checked.capture = orderCapture(p, link);
    }
    if (
      checked.capture == null &&
      (GVCheckoutService.numberValue(link.get('amount_paid')) != 0 ||
      link.get('status') == 'paid')
    )
      throw new GVCheckoutService.CheckoutException(
        'Capture needs verification.'
      );
    return checked;
  }
  private static Map<String, Object> orderCapture(
    Payment__c p,
    Map<String, Object> link
  ) {
    // An unused hosted link may not have a gateway order yet. Its capture collection and paid amount must both be empty.
    if (String.isBlank((String) link.get('order_id'))) {
      List<Object> linkedPayments = (List<Object>) link.get('payments');
      if (
        GVCheckoutService.numberValue(link.get('amount_paid')) == 0 &&
        (linkedPayments == null || linkedPayments.isEmpty()) &&
        new Set<String>{ 'created', 'cancelled', 'expired' }
          .contains((String) link.get('status'))
      )
        return null;
      throw new GVCheckoutService.CheckoutException(
        'Payment identity requires verification.'
      );
    }
    String orderId = gatewayId((String) link.get('order_id'), 'order_');
    Map<String, Object> response = request(
      'GET',
      '/v1/orders/' + orderId + '/payments',
      null
    );
    List<Object> rows = (List<Object>) response.get('items');
    if (
      rows == null ||
      rows.size() >= 100 ||
      (response.get('count') != null &&
      GVCheckoutService.numberValue(response.get('count')) != rows.size())
    )
      throw new GVCheckoutService.CheckoutException(
        'Payment collection is incomplete.'
      );
    Map<String, Object> capture;
    Boolean uncertain = false;
    for (Object entry : rows) {
      Map<String, Object> row = (Map<String, Object>) entry;
      if (
        row.get('order_id') != orderId ||
        row.get('currency') != 'INR' ||
        GVCheckoutService.numberValue(row.get('amount')) !=
        p.Payment_Amount__c * 100
      )
        throw new GVCheckoutService.CheckoutException(
          'Payment collection mismatch.'
        );
      if (row.get('status') == 'captured') {
        if (capture != null)
          throw new GVCheckoutService.CheckoutException(
            'Multiple captures need review.'
          );
        capture = request(
          'GET',
          '/v1/payments/' + gatewayId((String) row.get('id'), 'pay_'),
          null
        );
        if (
          capture.get('id') != row.get('id') ||
          capture.get('order_id') != orderId ||
          capture.get('currency') != 'INR' ||
          capture.get('status') != 'captured' ||
          capture.get('captured') != true ||
          GVCheckoutService.numberValue(capture.get('amount')) !=
          p.Payment_Amount__c * 100
        )
          throw new GVCheckoutService.CheckoutException(
            'Capture evidence mismatch.'
          );
      } else if (row.get('status') != 'failed') {
        uncertain = true;
      }
    }
    if (capture == null && uncertain)
      throw new GVCheckoutService.CheckoutException(
        'An authorized or uncertain payment needs verification.'
      );
    return capture;
  }
  private static void cancelUnpaidOrder(Id orderId) {
    Jewellery_Order__c orderRecord = [
      SELECT Id, Payment_Status__c, Order_Status__c
      FROM Jewellery_Order__c
      WHERE Id = :orderId
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    if (
      orderRecord.Payment_Status__c != 'Paid' &&
      orderRecord.Order_Status__c == 'pending' &&
      [
        SELECT COUNT()
        FROM Payment__c
        WHERE
          Jewellery_Order__c = :orderId
          AND Payment_Status__c IN ('Pending', 'Success')
        WITH SYSTEM_MODE
      ] == 0
    ) {
      orderRecord.Order_Status__c = 'Cancelled';
      update as system orderRecord;
    }
  }
  private static String gatewayId(String value, String prefix) {
    if (
      String.isBlank(value) ||
      !Pattern.matches('^' + prefix + '[A-Za-z0-9]+$', value)
    )
      throw new GVCheckoutService.CheckoutException(
        'Invalid gateway reference.'
      );
    return value;
  }
  private static void validateLink(
    Payment__c p,
    Map<String, Object> link,
    String expected
  ) {
    gatewayId((String) link.get('id'), 'plink_');
    String url = (String) link.get('short_url');
    if (
      (expected != null &&
      link.get('id') != expected) ||
      link.get('reference_id') != String.valueOf(p.Id) ||
      link.get('currency') != 'INR' ||
      GVCheckoutService.numberValue(link.get('amount')) !=
      p.Payment_Amount__c * 100 ||
      link.get('accept_partial') != false ||
      String.isBlank(url) ||
      !url.startsWith('https://rzp.io/')
    )
      throw new GVCheckoutService.CheckoutException(
        'Gateway response does not match the payment.'
      );
  }
  private static Map<String, Object> request(
    String method,
    String path,
    Map<String, Object> body
  ) {
    HttpRequest req = new HttpRequest();
    req.setEndpoint('callout:GV_Razorpay_Test' + path);
    req.setMethod(method);
    req.setTimeout(30000);
    if (body != null) {
      req.setHeader('Content-Type', 'application/json');
      req.setBody(JSON.serialize(body));
    }
    HttpResponse response = new Http().send(req);
    if (response.getStatusCode() < 200 || response.getStatusCode() > 299)
      throw new GVCheckoutService.CheckoutException(
        'Gateway request unavailable.'
      );
    return (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
  }
}
