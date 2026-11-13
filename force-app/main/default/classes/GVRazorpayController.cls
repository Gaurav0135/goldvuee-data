/** Hosted links only. A persisted Queued state precedes each callout transaction. */
public without sharing class GVRazorpayController {
  public class Result {
    @AuraEnabled
    public Id paymentId;
    @AuraEnabled
    public Id orderId;
    @AuraEnabled
    public Id cartId;
    @AuraEnabled
    public String state;
    @AuraEnabled
    public String paymentStatus;
    @AuraEnabled
    public String fulfillment;
    @AuraEnabled
    public String lastFailureState;
    @AuraEnabled
    public String paymentUrl;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public Decimal amount;
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
    GVCheckoutService.Attempt a = GVCheckoutService.attempt(p);
    if (
      p.Payment_Status__c == 'Success' ||
      p.Jewellery_Order__r.Payment_Status__c == 'Paid'
    )
      return result(p);
    if (
      p.Payment_Status__c != 'Pending' ||
      p.Jewellery_Order__r.Order_Status__c != 'pending' ||
      p.Payment_Amount__c != p.Jewellery_Order__r.Grand_Total__c
    )
      throw new AuraHandledException('This order requires support review.');
    if (a.state == 'New') {
      if (
        [
          SELECT COUNT()
          FROM GV_Payment_Config__c
          WHERE Name = 'Hosted Test Mode'
          WITH SYSTEM_MODE
        ] != 1
      )
        throw new AuraHandledException(
          'Test payment configuration must be verified by a GoldVuee administrator first.'
        );
      GVCheckoutService.stock(p.Jewellery_Order__c);
      a.state = 'Queued';
      p.Gateway_Response__c = JSON.serialize(a);
      update as system p;
      AsyncOptions queueOptions = new AsyncOptions();
      queueOptions.MaximumQueueableStackDepth = 5;
      System.enqueueJob(new GatewayJob(p.Id, 'Create'), queueOptions);
    } else if (a.state == 'Ready') {
      // Recheck stock and gateway status before presenting an existing hosted URL.
      GVCheckoutService.stock(p.Jewellery_Order__c);
      a.state = 'Checking';
      a.lastFailureState = null;
      p.Gateway_Response__c = JSON.serialize(a);
      update as system p;
      System.enqueueJob(new GatewayJob(p.Id, 'Refresh'));
    }
    return result(p);
  }
  @AuraEnabled
  public static Result refreshPayment(Id paymentId) {
    return queueAction(paymentId, 'Refresh');
  }
  @AuraEnabled
  public static Result cancelPayment(Id paymentId) {
    return queueAction(paymentId, 'Cancel');
  }
  private static Result queueAction(Id pid, String action) {
    Id cid = GVCheckoutService.customer();
    GVCheckoutService.lockCustomer(cid);
    Payment__c p = GVCheckoutService.payment(pid, cid);
    GVCheckoutService.Attempt a = GVCheckoutService.attempt(p);
    if (p.Payment_Status__c == 'Success')
      return result(p);
    if (action == 'Cancel' && a.state == 'New') {
      a.state = 'Cancelled';
      p.Payment_Status__c = 'Failed';
      p.Failure_Reason__c = 'Cancelled before payment initialization.';
      p.Gateway_Response__c = JSON.serialize(a);
      update as system p;
      return result(p);
    }
    if (
      (!String.isBlank(a.linkId) ||
      (a.state == 'Unknown' &&
      action == 'Refresh')) &&
      a.state != 'Checking' &&
      a.state != 'Cancelling' &&
      a.state != 'Queued'
    ) {
      a.state = action == 'Cancel' ? 'Cancelling' : 'Checking';
      p.Gateway_Response__c = JSON.serialize(a);
      update as system p;
      System.enqueueJob(new GatewayJob(pid, action));
    }
    return result(p);
  }
  private static Result result(Payment__c p) {
    GVCheckoutService.Attempt a = GVCheckoutService.attempt(p);
    Result r = new Result();
    r.paymentId = p.Id;
    r.orderId = p.Jewellery_Order__c;
    r.cartId = p.Jewellery_Order__r.Shopping_Cart__c;
    r.amount = p.Payment_Amount__c;
    r.state = a.state;
    r.paymentStatus = p.Payment_Status__c;
    r.fulfillment = a.fulfillment;
    r.lastFailureState = a.lastFailureState;
    if (a.state == 'Ready' && p.Payment_Status__c == 'Pending')
      r.paymentUrl = a.url;
    r.message = p.Payment_Status__c == 'Success'
      ? (a.fulfillment == 'Confirmed'
          ? 'Payment confirmed. Your order is confirmed.'
          : 'Payment received. Fulfillment requires support review; do not pay again.')
      : a.lastFailureState == 'failed'
          ? 'Your last payment attempt failed. No stock was deducted. Retry using the same secure payment link.'
          : a.state == 'Unknown'
              ? 'Payment outcome is uncertain. Contact support before trying another payment.'
              : a.state == 'Legacy review'
                  ? 'A previous checkout requires support review.'
                  : a.state == 'Cancelled' ||
                      a.state == 'Expired'
                      ? 'This payment link is closed. You may prepare a safe retry.'
                      : a.state == 'Ready'
                          ? 'Secure test payment is ready.'
                          : 'Awaiting payment verification. Closing the payment page does not cancel your payment.';
    return r;
  }
  public class GatewayJob implements Queueable, Database.AllowsCallouts {
    private Id pid;
    private String action;
    private Integer remainingChecks = 4;
    public GatewayJob(Id pid, String action) {
      this.pid = pid;
      this.action = action;
    }
    private GatewayJob(Id pid, Integer checks) {
      this.pid = pid;
      this.action = 'Monitor';
      this.remainingChecks = checks;
    }
    public void execute(QueueableContext context) {
      perform();
      // One bounded read-only chain survives browser closure and the UI deadline.
      // Four children respect this Developer Edition org's five-job chain limit.
      if ((action == 'Create' || action == 'Monitor') && remainingChecks > 0) {
        Payment__c current = [
          SELECT
            Payment_Status__c,
            Gateway_Response__c,
            Razorpay_Order_ID__c,
            Transaction_ID__c
          FROM Payment__c
          WHERE Id = :pid
          WITH SYSTEM_MODE
        ];
        String state = GVCheckoutService.attempt(current).state;
        if (
          current.Payment_Status__c == 'Pending' &&
          state != 'Legacy review' &&
          state != 'Cancelled' &&
          state != 'Expired'
        )
          System.enqueueJob(new GatewayJob(pid, remainingChecks - 1), 1);
      }
    }
    private void perform() {
      Payment__c p = [
        SELECT
          Id,
          Jewellery_Order__c,
          Payment_Amount__c,
          Payment_Status__c,
          Gateway_Response__c,
          Razorpay_Order_ID__c,
          Transaction_ID__c,
          Jewellery_Order__r.Customer__c
        FROM Payment__c
        WHERE Id = :pid
        WITH SYSTEM_MODE
      ];
      GVCheckoutService.Attempt a = GVCheckoutService.attempt(p);
      if (p.Payment_Status__c == 'Success')
        return;
      // Refuse duplicate jobs. Only a serialized Aura transaction can enqueue this state.
      if (action == 'Create' && a.state != 'Queued')
        return;
      if (
        action != 'Create' &&
        action != 'Monitor' &&
        a.state != 'Checking' &&
        a.state != 'Cancelling'
      )
        return;
      if (action == 'Monitor' && a.state != 'Ready' && a.state != 'Unknown')
        return;
      try {
        Map<String, Object> link;
        if (action == 'Create') {
          verifyTestConfiguration();
          link = request(
            'POST',
            '/v1/payment_links',
            new Map<String, Object>{
              'amount' => (p.Payment_Amount__c * 100).longValue(),
              'currency' => 'INR',
              'accept_partial' => false,
              'reference_id' => String.valueOf(pid),
              'description' => 'GoldVuee test checkout',
              'notify' => new Map<String, Object>{
                'sms' => false,
                'email' => false
              },
              'reminder_enable' => false,
              'notes' => new Map<String, Object>{
                'salesforce_payment_id' => String.valueOf(pid),
                'salesforce_order_id' => String.valueOf(p.Jewellery_Order__c)
              }
            }
          );
        } else {
          if (String.isBlank(a.linkId)) {
            Map<String, Object> recovered = request(
              'GET',
              '/v1/payment_links?reference_id=' +
              EncodingUtil.urlEncode(String.valueOf(pid), 'UTF-8'),
              null
            );
            List<Object> links = (List<Object>) recovered.get('payment_links');
            if (links == null || links.size() != 1)
              throw new GVCheckoutService.CheckoutException(
                'Payment reference requires operator reconciliation.'
              );
            link = (Map<String, Object>) links[0];
          } else
            link = request(
              'GET',
              '/v1/payment_links/' + safeId(a.linkId, 'plink_'),
              null
            );
          validateLink(p, link, a.linkId);
          if (action == 'Cancel' && link.get('status') == 'created')
            link = request(
              'POST',
              '/v1/payment_links/' +
                safeId((String) link.get('id'), 'plink_') +
                '/cancel',
              new Map<String, Object>()
            );
        }
        validateLink(p, link, action == 'Create' ? null : a.linkId);
        String linkId = (String) link.get('id');
        String status = (String) link.get('status');
        Map<String, Object> evidence;
        if (status == 'paid') {
          if (
            GVCheckoutService.numberValue(link.get('amount_paid')) !=
            p.Payment_Amount__c * 100
          )
            throw new GVCheckoutService.CheckoutException(
              'Paid amount mismatch.'
            );
          // Fetch the captured transaction independently; link return parameters never establish payment.
          List<Object> payments = (List<Object>) link.get('payments');
          if (payments == null || payments.size() != 1)
            throw new GVCheckoutService.CheckoutException(
              'Payment reconciliation required.'
            );
          Map<String, Object> payment = (Map<String, Object>) payments[0];
          String transactionId = (String) payment.get('payment_id');
          evidence = request(
            'GET',
            '/v1/payments/' + safeId(transactionId, 'pay_'),
            null
          );
        }
        // All HTTP requests finish before obtaining locks or performing DML.
        GVCheckoutService.lockCustomer(p.Jewellery_Order__r.Customer__c);
        Payment__c current = [
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
        if (current.Payment_Status__c == 'Success')
          return;
        GVCheckoutService.Attempt currentAttempt = GVCheckoutService.attempt(
          current
        );
        if (
          currentAttempt.state != a.state ||
          currentAttempt.linkId != a.linkId
        )
          return;
        if (currentAttempt.lastFailurePaymentId != a.lastFailurePaymentId) {
          a.lastFailurePaymentId = currentAttempt.lastFailurePaymentId;
          a.lastFailureState = currentAttempt.lastFailureState;
        }
        a.linkId = linkId;
        a.url = (String) link.get('short_url');
        a.gatewayOrderId = (String) link.get('order_id');
        a.state = status == 'created'
          ? 'Ready'
          : status == 'paid'
              ? 'Verifying'
              : status == 'cancelled'
                  ? 'Cancelled'
                  : status == 'expired' ? 'Expired' : 'Unknown';
        current.Gateway_Response__c = JSON.serialize(a);
        // Keep the real Razorpay order identifier distinct from the hosted-link identifier.
        if (!String.isBlank(a.gatewayOrderId))
          current.Razorpay_Order_ID__c = a.gatewayOrderId;
        if (status == 'cancelled' || status == 'expired') {
          if (GVCheckoutService.numberValue(link.get('amount_paid')) != 0)
            throw new GVCheckoutService.CheckoutException(
              'Partial payment requires review.'
            );
          current.Payment_Status__c = 'Failed';
          current.Failure_Reason__c =
            'Hosted link ' +
            status +
            '; gateway reports zero paid.';
        }
        update as system current;
        if (evidence != null)
          GVCheckoutService.captured(pid, linkId, evidence);
      } catch (Exception e) {
        // Do not rollback a successfully recorded capture. Preserve unknown outcomes; never auto-create a replacement.
        Payment__c current = [
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
        if (current.Payment_Status__c == 'Success')
          return;
        GVCheckoutService.Attempt saved = GVCheckoutService.attempt(current);
        saved.state = 'Unknown';
        current.Gateway_Response__c = JSON.serialize(saved);
        current.Failure_Reason__c = 'Gateway outcome requires reconciliation. No automatic replacement payment is permitted.';
        update as system current;
      }
    }
  }
  private static void verifyTestConfiguration() {
    // The same Basic principal signs this read-only probe. Never log or return its key.
    Map<String, Object> data = request('GET', '/v1/payments?count=1', null);
    // Named Credential secrets are write-only. Test-mode key is separately checked from protected server config.
    List<GV_Payment_Config__c> configs = [
      SELECT Name
      FROM GV_Payment_Config__c
      WHERE Name = 'Hosted Test Mode'
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (configs.isEmpty())
      throw new GVCheckoutService.CheckoutException(
        'Test mode has not been verified by an administrator.'
      );
  }
  private static String safeId(String id, String prefix) {
    if (
      String.isBlank(id) || !Pattern.matches('^' + prefix + '[A-Za-z0-9]+$', id)
    )
      throw new GVCheckoutService.CheckoutException(
        'Invalid gateway identifier.'
      );
    return id;
  }
  private static void validateLink(
    Payment__c p,
    Map<String, Object> link,
    String expectedId
  ) {
    String id = (String) link.get('id');
    safeId(id, 'plink_');
    String url = (String) link.get('short_url');
    if (
      (expectedId != null &&
      id != expectedId) ||
      link.get('reference_id') != String.valueOf(p.Id) ||
      link.get('currency') != 'INR' ||
      GVCheckoutService.numberValue(link.get('amount')) !=
      p.Payment_Amount__c * 100 ||
      link.get('accept_partial') != false ||
      String.isBlank(url) ||
      !url.startsWith('https://rzp.io/')
    )
      throw new GVCheckoutService.CheckoutException(
        'Gateway link does not match the checkout.'
      );
  }
  public static Map<String, Object> request(
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
    HttpResponse res = new Http().send(req);
    if (res.getStatusCode() < 200 || res.getStatusCode() > 299)
      throw new GVCheckoutService.CheckoutException(
        'Gateway request unavailable.'
      );
    return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
  }
}
