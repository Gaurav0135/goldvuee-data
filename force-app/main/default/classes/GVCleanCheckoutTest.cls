@IsTest
private class GVCleanCheckoutTest {
  @TestSetup
  static void setup() {
    UserRole role = new UserRole(Name = 'Hosted Checkout Owner');
    insert as system role;
    User owner = new User(
      ProfileId = UserInfo.getProfileId(),
      UserRoleId = role.Id,
      LastName = 'HostedOwner',
      Alias = 'howner',
      Email = 'owner@example.com',
      Username = 'howner' + System.now().getTime() + '@example.com',
      CommunityNickname = 'howner' + System.now().getTime(),
      TimeZoneSidKey = 'Asia/Kolkata',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
    insert as system owner;
    // Use the org's actual cloned customer profile. Standard external profiles cannot create users in this org.
    Profile profile = [
      SELECT Id
      FROM Profile
      WHERE Name = 'GoldVuee Customer'
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    System.runAs(owner) {
      Account account = new Account(Name = 'Hosted Checkout Test');
      insert as system account;
      List<Contact> contacts = new List<Contact>{
        new Contact(LastName = 'HostedOne', AccountId = account.Id),
        new Contact(LastName = 'HostedTwo', AccountId = account.Id)
      };
      insert as system contacts;
      List<User> users = new List<User>();
      for (Integer i = 0; i < 2; i++)
        users.add(
          new User(
            ProfileId = profile.Id,
            ContactId = contacts[i].Id,
            LastName = contacts[i].LastName,
            Alias = 'hc' + i,
            Email = 'hosted' + i + '@example.com',
            Username = 'hosted' + i + System.now().getTime() + '@example.com',
            CommunityNickname = 'hosted' + i + System.now().getTime(),
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
          )
        );
      insert as system users;
    }
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Jewellery_Category__c category = new Jewellery_Category__c(
        Name = 'Hosted Test Category'
      );
      insert as system category;
      Jewellery_Product__c product = new Jewellery_Product__c(
        Category__c = category.Id,
        Name = 'Hosted Ring',
        Product_Code__c = 'HOSTED-1',
        SKU__c = 'HOSTED-1',
        Weight__c = 1,
        Price__c = 100,
        Stock_Quantity__c = 10,
        Reserved_Quantity__c = 0,
        Active__c = true
      );
      insert as system product;
      insert as system new GV_Payment_Config__c(
        Name = 'Hosted Test Mode',
        Webhook_Secret__c = 'unit-test-webhook-secret'
      );
    }
  }
  private static User customer() {
    return [
      SELECT Id, ContactId
      FROM User
      WHERE Alias = 'hc0'
      WITH SYSTEM_MODE
      LIMIT 1
    ];
  }
  private static Id product() {
    return [
      SELECT Id
      FROM Jewellery_Product__c
      WHERE Product_Code__c = 'HOSTED-1'
      WITH SYSTEM_MODE
      LIMIT 1
    ]
    .Id;
  }
  private static GVCheckoutController.Delivery delivery() {
    GVCheckoutController.Delivery d = new GVCheckoutController.Delivery();
    d.fullName = 'Hosted Customer';
    d.phone = '9876543210';
    d.street = '1 Gold Road';
    d.city = 'Indore';
    d.state = 'Madhya Pradesh';
    d.postalCode = '452001';
    d.country = 'India';
    return d;
  }
  private static GVCheckoutController.Summary prepare() {
    GVCartController.addToCart(product(), 2);
    return GVCheckoutController.prepareOrder(delivery());
  }
  private static void ready(Id pid, String state) {
    GVCheckoutService.Attempt a = new GVCheckoutService.Attempt();
    a.state = state;
    a.linkId = 'plink_Hosted1';
    a.url = 'https://rzp.io/rzp/Hosted1';
    a.gatewayOrderId = 'order_Hosted1';
    update as system new Payment__c(
      Id = pid,
      Gateway_Response__c = JSON.serialize(a),
      Razorpay_Order_ID__c = a.gatewayOrderId
    );
  }
  private static Map<String, Object> evidence() {
    return new Map<String, Object>{
      'id' => 'pay_Hosted1',
      'order_id' => 'order_Hosted1',
      'amount' => 20000,
      'currency' => 'INR',
      'status' => 'captured',
      'captured' => true,
      'method' => 'upi'
    };
  }
  private class GatewayMock implements HttpCalloutMock {
    Id pid;
    String status;
    Boolean mismatch;
    Boolean fail;
    GatewayMock(Id pid, String status, Boolean mismatch, Boolean fail) {
      this.pid = pid;
      this.status = status;
      this.mismatch = mismatch;
      this.fail = fail;
    }
    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(fail ? 503 : 200);
      if (req.getEndpoint().contains('/v1/payments?')) {
        res.setBody('{"items":[]}');
        return res;
      }
      if (req.getEndpoint().contains('/v1/payments/pay_')) {
        res.setBody(JSON.serialize(evidence()));
        return res;
      }
      Map<String, Object> data = new Map<String, Object>{
        'id' => 'plink_Hosted1',
        'reference_id' => String.valueOf(pid),
        'currency' => 'INR',
        'amount' => mismatch ? 999 : 20000,
        'amount_paid' => status == 'paid' ? 20000 : 0,
        'accept_partial' => false,
        'status' => status,
        'short_url' => 'https://rzp.io/rzp/Hosted1',
        'order_id' => 'order_Hosted1',
        'payments' => new List<Object>{
          new Map<String, Object>{ 'payment_id' => 'pay_Hosted1' }
        }
      };
      if (req.getMethod() == 'POST' && !req.getEndpoint().endsWith('/cancel')) {
        Map<String, Object> input = (Map<String, Object>) JSON.deserializeUntyped(
          req.getBody()
        );
        System.assertEquals(
          20000,
          GVCheckoutService.numberValue(input.get('amount'))
        );
        System.assertEquals(false, input.get('accept_partial'));
      }
      if (req.getEndpoint().contains('reference_id=')) {
        res.setBody(
          JSON.serialize(
            new Map<String, Object>{
              'payment_links' => new List<Object>{ data }
            }
          )
        );
        return res;
      }
      res.setBody(JSON.serialize(data));
      return res;
    }
  }
  @IsTest
  static void cartLifecycle() {
    System.runAs(customer()) {
      System.assertEquals(0, GVCartController.getCart().itemCount);
      GVCartController.CartResponse c = GVCartController.addToCart(
        product(),
        1
      );
      Id cartId = c.cartId;
      c = GVCartController.addToCart(product(), 2);
      System.assertEquals(1, c.items.size());
      System.assertEquals(3, c.itemCount);
      System.assertEquals(cartId, c.cartId);
      c = GVCartController.updateCartItem(c.items[0].Id, 2);
      System.assertEquals(200, c.totalAmount);
      c = GVCartController.removeCartItem(c.items[0].Id);
      System.assertEquals(0, c.itemCount);
      System.assertEquals(
        0,
        [SELECT COUNT() FROM Stock_Reservation__c WITH SYSTEM_MODE]
      );
    }
  }
  @IsTest
  static void invalidQuantitiesAndStock() {
    System.runAs(customer()) {
      for (Integer qty : new List<Integer>{ -1, 0, 101, 11 }) {
        Boolean failed = false;
        try {
          GVCartController.addToCart(product(), qty);
        } catch (Exception e) {
          failed = true;
        }
        System.assert(failed);
      }
      Boolean rejected = false;
      try {
        GVCartController.addToCart(null, 1);
      } catch (Exception e) {
        rejected = true;
      }
      System.assert(rejected);
      System.assertEquals(
        10,
        [
          SELECT Stock_Quantity__c
          FROM Jewellery_Product__c
          WHERE Id = :product()
          WITH SYSTEM_MODE
        ]
        .Stock_Quantity__c
      );
    }
  }
  @IsTest
  static void checkoutIdempotentAndAddress() {
    System.runAs(customer()) {
      GVCheckoutController.Summary s = prepare();
      GVCheckoutController.Summary again = GVCheckoutController.prepareOrder(
        delivery()
      );
      System.assertEquals(s.orderId, again.orderId);
      System.assertEquals(s.paymentId, again.paymentId);
      System.assertEquals(200, s.total);
      System.assertEquals(
        1,
        [SELECT COUNT() FROM Jewellery_Order__c WITH SYSTEM_MODE]
      );
      System.assertEquals('1 Gold Road', GVCheckoutController.loadOrder(s.orderId).delivery.street);
      System.assertEquals('9876543210', GVCheckoutController.loadOrder(s.orderId).delivery.phone);
      GVCheckoutController.Delivery d = delivery();
      d.postalCode = '000000';
      Boolean failed = false;
      try {
        GVCheckoutController.prepareOrder(d);
      } catch (Exception e) {
        failed = true;
      }
      System.assert(failed);
      System.assertEquals('India', GVCheckoutController.loadDelivery().country);
    }
  }
  @IsTest
  static void isolateCustomers() {
    Id lineId;
    Id pid;
    Id oid;
    System.runAs(customer()) {
      GVCheckoutController.Summary s = prepare();
      pid = s.paymentId;
      oid = s.orderId;
      lineId = GVCartController.getCart().items[0].Id;
    }
    User second = [
      SELECT Id
      FROM User
      WHERE Alias = 'hc1'
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    System.runAs(second) {
      System.assertEquals(0, GVCartController.getCart().itemCount);
      Boolean denied = false;
      try {
        GVCartController.removeCartItem(lineId);
      } catch (Exception e) {
        denied = true;
      }
      System.assert(denied);
      denied = false;
      try {
        GVRazorpayController.paymentStatus(pid);
      } catch (Exception e) {
        denied = true;
      }
      System.assert(denied);
      denied = false;
      try {
        GVCheckoutController.loadOrder(oid);
      } catch (Exception e) {
        denied = true;
      }
      System.assert(denied);
    }
  }
  @IsTest
  static void missingContactRejected() {
    Boolean denied = false;
    try {
      GVCartController.getCart();
    } catch (Exception e) {
      denied = true;
    }
    System.assert(denied);
  }
  @IsTest
  static void createLinkOnce() {
    System.runAs(customer()) {
      GVCheckoutController.Summary s = prepare();
      Test.setMock(
        HttpCalloutMock.class,
        new GatewayMock(s.paymentId, 'created', false, false)
      );
      Test.startTest();
      System.assertEquals(
        'Queued',
        GVRazorpayController.startPayment(s.paymentId).state
      );
      GVRazorpayController.startPayment(s.paymentId);
      System.assertEquals(1, Limits.getQueueableJobs());
      Test.stopTest();
      System.assertEquals(
        'Ready',
        GVRazorpayController.paymentStatus(s.paymentId).state
      );
      System.assertEquals(
        'https://rzp.io/rzp/Hosted1',
        GVRazorpayController.paymentStatus(s.paymentId).paymentUrl
      );
      System.assertEquals(
        10,
        [
          SELECT Stock_Quantity__c
          FROM Jewellery_Product__c
          WHERE Id = :product()
          WITH SYSTEM_MODE
        ]
        .Stock_Quantity__c
      );
    }
  }
  @IsTest
  static void failedRequestDoesNotRetry() {
    System.runAs(customer()) {
      GVCheckoutController.Summary s = prepare();
      Test.setMock(
        HttpCalloutMock.class,
        new GatewayMock(s.paymentId, 'created', false, true)
      );
      Test.startTest();
      GVRazorpayController.startPayment(s.paymentId);
      Test.stopTest();
      System.assertEquals(
        'Unknown',
        GVRazorpayController.paymentStatus(s.paymentId).state
      );
      System.assertEquals(
        'Unknown',
        GVRazorpayController.startPayment(s.paymentId).state
      );
      System.assertEquals(
        10,
        [
          SELECT Stock_Quantity__c
          FROM Jewellery_Product__c
          WHERE Id = :product()
          WITH SYSTEM_MODE
        ]
        .Stock_Quantity__c
      );
    }
  }
  @IsTest
  static void incorrectGatewayAmount() {
    System.runAs(customer()) {
      GVCheckoutController.Summary s = prepare();
      Test.setMock(
        HttpCalloutMock.class,
        new GatewayMock(s.paymentId, 'created', true, false)
      );
      Test.startTest();
      GVRazorpayController.startPayment(s.paymentId);
      Test.stopTest();
      System.assertEquals(
        'Unknown',
        GVRazorpayController.paymentStatus(s.paymentId).state
      );
    }
  }
  @IsTest
  static void capturedAndDuplicate() {
    System.runAs(customer()) {
      GVCheckoutController.Summary s = prepare();
      ready(s.paymentId, 'Ready');
      GVCheckoutService.captured(s.paymentId, 'plink_Hosted1', evidence());
      GVCheckoutService.captured(s.paymentId, 'plink_Hosted1', evidence());
      System.assertEquals(
        'Success',
        GVRazorpayController.paymentStatus(s.paymentId).paymentStatus
      );
      System.assertEquals(
        'Confirmed',
        GVRazorpayController.paymentStatus(s.paymentId).fulfillment
      );
      System.assertEquals(
        8,
        [
          SELECT Stock_Quantity__c
          FROM Jewellery_Product__c
          WHERE Id = :product()
          WITH SYSTEM_MODE
        ]
        .Stock_Quantity__c
      );
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM Inventory_Movement__c
          WHERE Jewellery_Order__c = :s.orderId
          WITH SYSTEM_MODE
        ]
      );
      System.assertEquals(
        'Paid',
        GVOrderHistoryController.getMyOrders()[0].paymentStatus
      );
      System.assertEquals(
        1,
        GVOrderHistoryController.getMyOrderDetail(s.orderId).items.size()
      );
      System.assertEquals(
        'Success',
        GVRazorpayController.startPayment(s.paymentId).paymentStatus
      );
    }
  }
  @IsTest
  static void capturedWithoutStockRemainsPaid() {
    GVCheckoutController.Summary summary;
    System.runAs(customer()) {
      summary = prepare();
      ready(summary.paymentId, 'Ready');
    }
    update as system new Jewellery_Product__c(
      Id = product(),
      Stock_Quantity__c = 0
    );
    System.runAs(customer()) {
      GVCheckoutService.captured(
        summary.paymentId,
        'plink_Hosted1',
        evidence()
      );
      GVCheckoutService.captured(
        summary.paymentId,
        'plink_Hosted1',
        evidence()
      );
      System.assertEquals(
        'Success',
        GVRazorpayController.paymentStatus(summary.paymentId).paymentStatus
      );
      System.assertEquals(
        'Stock review required',
        GVRazorpayController.paymentStatus(summary.paymentId).fulfillment
      );
      System.assertEquals(
        'Paid',
        [
          SELECT Payment_Status__c
          FROM Jewellery_Order__c
          WHERE Id = :summary.orderId
          WITH SYSTEM_MODE
        ]
        .Payment_Status__c
      );
      System.assertEquals(
        0,
        [SELECT COUNT() FROM Inventory_Movement__c WITH SYSTEM_MODE]
      );
    }
  }
  @IsTest
  static void rejectWrongCapture() {
    System.runAs(customer()) {
      GVCheckoutController.Summary s = prepare();
      ready(s.paymentId, 'Ready');
      Map<String, Object> data = evidence();
      data.put('amount', 1);
      Boolean failed = false;
      try {
        GVCheckoutService.captured(s.paymentId, 'plink_Hosted1', data);
      } catch (Exception e) {
        failed = true;
      }
      System.assert(failed);
      System.assertEquals(
        'Pending',
        GVRazorpayController.paymentStatus(s.paymentId).paymentStatus
      );
      data = evidence();
      data.put('currency', 'USD');
      failed = false;
      try {
        GVCheckoutService.captured(s.paymentId, 'plink_Hosted1', data);
      } catch (Exception e) {
        failed = true;
      }
      System.assert(failed);
      System.assertEquals(
        0,
        [SELECT COUNT() FROM Inventory_Movement__c WITH SYSTEM_MODE]
      );
    }
  }
  @IsTest
  static void cancellationAndRetrySameOrder() {
    System.runAs(customer()) {
      GVCheckoutController.Summary s = prepare();
      ready(s.paymentId, 'Ready');
      Test.setMock(
        HttpCalloutMock.class,
        new GatewayMock(s.paymentId, 'cancelled', false, false)
      );
      Test.startTest();
      GVRazorpayController.cancelPayment(s.paymentId);
      Test.stopTest();
      System.assertEquals(
        'Cancelled',
        GVRazorpayController.paymentStatus(s.paymentId).state
      );
      GVCheckoutController.Summary retry = GVCheckoutController.prepareOrder(
        delivery()
      );
      System.assertEquals(s.orderId, retry.orderId);
      System.assertNotEquals(s.paymentId, retry.paymentId);
      System.assertEquals(
        0,
        [SELECT COUNT() FROM Inventory_Movement__c WITH SYSTEM_MODE]
      );
    }
  }
  @IsTest
  static void cancelUninitialized() {
    System.runAs(customer()) {
      GVCheckoutController.Summary s = prepare();
      System.assertEquals(
        'Cancelled',
        GVRazorpayController.cancelPayment(s.paymentId).state
      );
    }
  }
  @IsTest
  static void pendingRefresh() {
    System.runAs(customer()) {
      GVCheckoutController.Summary s = prepare();
      ready(s.paymentId, 'Ready');
      Test.setMock(
        HttpCalloutMock.class,
        new GatewayMock(s.paymentId, 'created', false, false)
      );
      Test.startTest();
      GVRazorpayController.refreshPayment(s.paymentId);
      Test.stopTest();
      System.assertEquals(
        'Pending',
        GVRazorpayController.paymentStatus(s.paymentId).paymentStatus
      );
      System.assertEquals(
        'Ready',
        GVRazorpayController.paymentStatus(s.paymentId).state
      );
    }
  }
  @IsTest
  static void capturedApiRefresh() {
    System.runAs(customer()) {
      GVCheckoutController.Summary s = prepare();
      ready(s.paymentId, 'Ready');
      Test.setMock(
        HttpCalloutMock.class,
        new GatewayMock(s.paymentId, 'paid', false, false)
      );
      Test.startTest();
      GVRazorpayController.refreshPayment(s.paymentId);
      Test.stopTest();
      System.assertEquals(
        'Success',
        GVRazorpayController.paymentStatus(s.paymentId).paymentStatus
      );
    }
  }
  @IsTest
  static void signaturesAndIngress() {
    String body = '{}', secret = 'unit-test-webhook-secret';
    String signature = EncodingUtil.convertToHex(
      Crypto.generateMac('HmacSHA256', Blob.valueOf(body), Blob.valueOf(secret))
    );
    System.assert(GVPaymentWebhook.valid(body, signature, secret));
    System.assert(!GVPaymentWebhook.valid(body, signature + '0', secret));
    System.assert(!GVPaymentWebhook.valid('tampered', signature, secret));
    RestContext.request = new RestRequest();
    RestContext.response = new RestResponse();
    RestContext.request.requestBody = Blob.valueOf(body);
    GVPaymentWebhook.receive();
    System.assertEquals(401, RestContext.response.statusCode);
    RestContext.request.addHeader('X-Razorpay-Signature', signature);
    GVPaymentWebhook.receive();
    System.assertEquals(202, RestContext.response.statusCode);
    Test.getEventBus().deliver();
  }
  @IsTest
  static void retiredApisCannotCharge() {
    GVOnlineCheckoutController.CheckoutResult retiredOrder = new GVOnlineCheckoutController.CheckoutResult();
    GVOnlineCheckoutController.RecoveryResult retiredRecovery = new GVOnlineCheckoutController.RecoveryResult();
    Integer denied = 0;
    try {
      GVOnlineCheckoutController.beginCheckout();
    } catch (Exception e) {
      denied++;
    }
    try {
      GVOnlineCheckoutController.checkoutRecovery(null);
    } catch (Exception e) {
      denied++;
    }
    try {
      GVOnlineCheckoutController.cancelUnpaidCheckout(null);
    } catch (Exception e) {
      denied++;
    }
    try {
      GVOnlineCheckoutController.prepareOnlineOrder(
        null,
        null,
        null,
        null,
        null
      );
    } catch (Exception e) {
      denied++;
    }
    try {
      GVOnlineCheckoutController.resumeCheckout();
    } catch (Exception e) {
      denied++;
    }
    try {
      GVOnlineCheckoutController.cancelExpiredCheckout(null);
    } catch (Exception e) {
      denied++;
    }
    try {
      GVOnlineCheckoutController.requestReconciliation(null);
    } catch (Exception e) {
      denied++;
    }
    try {
      GVPaymentController.initiatePayment(null);
    } catch (Exception e) {
      denied++;
    }
    try {
      GVPaymentController.paymentState(null);
    } catch (Exception e) {
      denied++;
    }
    try {
      GVPaymentVerificationController.requestSignatureVerification(
        null,
        null,
        null
      );
    } catch (Exception e) {
      denied++;
    }
    try {
      GVPaymentVerificationController.signatureVerificationState(null, null);
    } catch (Exception e) {
      denied++;
    }
    try {
      GVPaymentVerificationController.verifyPayment(null, null);
    } catch (Exception e) {
      denied++;
    }
    try {
      GVCheckoutController.placeOrder(null, null, null, null, null);
    } catch (Exception e) {
      denied++;
    }
    System.assertEquals(13, denied);
    new GVGatewayWorker((Id) null, 'initialize').execute(null);
    new GVGatewayWorker(new List<Id>()).execute(null);
    GVReconciliationScheduler scheduler = new GVReconciliationScheduler();
    scheduler.execute((SchedulableContext) null);
    scheduler.start(null);
    scheduler.execute((Database.BatchableContext) null, new List<Payment__c>());
    scheduler.finish(null);
    RestContext.response = new RestResponse();
    GVRazorpayWebhook.receive();
    System.assertEquals(410, RestContext.response.statusCode);
  }
  @IsTest
  static void duplicateSignedWebhook() {
    Id pid;
    System.runAs(customer()) {
      GVCheckoutController.Summary s = prepare();
      pid = s.paymentId;
      ready(pid, 'Ready');
    }
    Map<String, Object> link = new Map<String, Object>{
      'id' => 'plink_Hosted1',
      'reference_id' => String.valueOf(pid),
      'currency' => 'INR',
      'amount' => 20000,
      'amount_paid' => 20000,
      'accept_partial' => false,
      'status' => 'paid',
      'order_id' => 'order_Hosted1'
    };
    String raw = JSON.serialize(
      new Map<String, Object>{
        'event' => 'payment_link.paid',
        'payload' => new Map<String, Object>{
          'payment_link' => new Map<String, Object>{ 'entity' => link },
          'payment' => new Map<String, Object>{ 'entity' => evidence() }
        }
      }
    );
    String signature = EncodingUtil.convertToHex(
      Crypto.generateMac(
        'HmacSHA256',
        Blob.valueOf(raw),
        Blob.valueOf('unit-test-webhook-secret')
      )
    );
    GoldVuee_Payment_Verification__e evt = new GoldVuee_Payment_Verification__e(
      Source__c = 'HostedLink',
      Raw_Body__c = raw,
      Razorpay_Signature__c = signature
    );
    GVPaymentWebhook.process(
      new List<GoldVuee_Payment_Verification__e>{ evt, evt }
    );
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Inventory_Movement__c WITH SYSTEM_MODE]
    );
  }

  @IsTest
  static void expiredLinkCanRetryWithoutNewOrder() {
    System.runAs(customer()) {
      GVCheckoutController.Summary s = prepare();
      ready(s.paymentId, 'Ready');
      Test.setMock(
        HttpCalloutMock.class,
        new GatewayMock(s.paymentId, 'expired', false, false)
      );
      Test.startTest();
      GVRazorpayController.refreshPayment(s.paymentId);
      Test.stopTest();
      System.assertEquals(
        'Expired',
        GVRazorpayController.paymentStatus(s.paymentId).state
      );
      System.assertEquals(
        'Failed',
        GVRazorpayController.paymentStatus(s.paymentId).paymentStatus
      );
      System.assertEquals(
        s.orderId,
        GVCheckoutController.prepareOrder(delivery()).orderId
      );
      System.assertEquals(
        0,
        [SELECT COUNT() FROM Inventory_Movement__c WITH SYSTEM_MODE]
      );
    }
  }
  @IsTest
  static void unknownCreationReconcilesByReference() {
    System.runAs(customer()) {
      GVCheckoutController.Summary s = prepare();
      GVCheckoutService.Attempt a = new GVCheckoutService.Attempt();
      a.state = 'Unknown';
      update as system new Payment__c(
        Id = s.paymentId,
        Gateway_Response__c = JSON.serialize(a)
      );
      Test.setMock(
        HttpCalloutMock.class,
        new GatewayMock(s.paymentId, 'created', false, false)
      );
      Test.startTest();
      GVRazorpayController.refreshPayment(s.paymentId);
      Test.stopTest();
      System.assertEquals(
        'Ready',
        GVRazorpayController.paymentStatus(s.paymentId).state
      );
      System.assertEquals(1, [SELECT COUNT() FROM Payment__c WITH SYSTEM_MODE]);
    }
  }
  @IsTest
  static void cartEditsPreservePayableSnapshotAndLateCapture() {
    System.runAs(customer()) {
      GVCheckoutController.Summary old = prepare();
      ready(old.paymentId, 'Ready');
      Id oldCart = GVCartController.getCart().cartId;
      GVCartController.CartResponse changed = GVCartController.addToCart(
        product(),
        1
      );
      System.assertNotEquals(oldCart, changed.cartId);
      System.assertEquals(3, changed.itemCount);
      System.assertEquals(
        200,
        GVCheckoutController.loadOrder(old.orderId).total
      );
      System.assertEquals(
        2,
        GVCheckoutController.loadOrder(old.orderId).items[0].Quantity__c
      );
      System.assertEquals(
        'Pending',
        GVRazorpayController.paymentStatus(old.paymentId).paymentStatus
      );
      changed = GVCartController.updateCartItem(changed.items[0].Id, 1);
      System.assertEquals(100, changed.totalAmount);
      changed = GVCartController.removeCartItem(changed.items[0].Id);
      System.assertEquals(0, changed.itemCount);
      GVCartController.addToCart(product(), 1);
      GVCheckoutController.Summary current = GVCheckoutController.prepareOrder(
        delivery()
      );
      System.assertNotEquals(old.orderId, current.orderId);
      System.assertEquals(100, current.total);
    }
  }
  @IsTest
  static void lateCaptureNeverClearsIndependentCurrentBag() {
    System.runAs(customer()) {
      GVCheckoutController.Summary old = prepare();
      ready(old.paymentId, 'Ready');
      GVCartController.addToCart(product(), 1);
      Id currentCart = GVCartController.getCart().cartId;
      Test.startTest();
      GVCheckoutService.captured(old.paymentId, 'plink_Hosted1', evidence());
      GVCheckoutService.captured(old.paymentId, 'plink_Hosted1', evidence());
      Test.stopTest();
      System.assertEquals(currentCart, GVCartController.getCart().cartId);
      System.assertEquals(3, GVCartController.getCart().itemCount);
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM Inventory_Movement__c
          WHERE Jewellery_Order__c = :old.orderId
          WITH SYSTEM_MODE
        ]
      );
      System.assertEquals(
        8,
        [
          SELECT Stock_Quantity__c
          FROM Jewellery_Product__c
          WHERE Id = :product()
          WITH SYSTEM_MODE
        ]
        .Stock_Quantity__c
      );
    }
  }
  @IsTest
  static void quantityAndRemovalCanBeFirstPendingCartEdit() {
    System.runAs(customer()) {
      GVCheckoutController.Summary old = prepare();
      ready(old.paymentId, 'Ready');
      Id originalLine = GVCartController.getCart().items[0].Id;
      GVCartController.CartResponse current = GVCartController.updateCartItem(
        originalLine,
        3
      );
      System.assertEquals(3, current.itemCount);
      System.assertEquals(
        2,
        GVCheckoutController.loadOrder(old.orderId).items[0].Quantity__c
      );
      GVCheckoutController.Summary newer = GVCheckoutController.prepareOrder(
        delivery()
      );
      GVCheckoutService.Attempt nextAttempt = new GVCheckoutService.Attempt();
      nextAttempt.state = 'Ready';
      nextAttempt.linkId = 'plink_Hosted2';
      nextAttempt.gatewayOrderId = 'order_Hosted2';
      update as system new Payment__c(
        Id = newer.paymentId,
        Gateway_Response__c = JSON.serialize(nextAttempt),
        Razorpay_Order_ID__c = 'order_Hosted2'
      );
      Id beforeRemovalCart = GVCartController.getCart().cartId;
      current = GVCartController.removeCartItem(current.items[0].Id);
      System.assertEquals(0, current.itemCount);
      System.assertNotEquals(beforeRemovalCart, current.cartId);
      System.assertEquals(
        3,
        GVCheckoutController.loadOrder(newer.orderId).items[0].Quantity__c
      );
    }
  }
  @IsTest
  static void missingContactAddressDoesNotBlockValidOrder() {
    System.runAs(customer()) {
      GVCheckoutController.Delivery d = GVCheckoutController.loadDelivery();
      System.assertEquals('', d.street);
      System.assertEquals('', d.city);
      System.assertEquals('', d.state);
      System.assertEquals('', d.postalCode);
      System.assertEquals('', d.phone);
      System.assertEquals('India', d.country);
      GVCheckoutController.Summary old = prepare();
      ready(old.paymentId, 'Ready');
      GVCheckoutController.Delivery changed = delivery();
      changed.state = 'Rajasthan';
      changed.city = 'Jaipur';
      changed.postalCode = '302001';
      GVCheckoutController.Summary current = GVCheckoutController.prepareOrder(
        changed
      );
      System.assertNotEquals(old.orderId, current.orderId);
      System.assertEquals(
        'Madhya Pradesh',
        GVCheckoutController.loadOrder(old.orderId).delivery.state
      );
      System.assertEquals('Rajasthan', current.delivery.state);
    }
  }
  @IsTest
  static void failedGatewayPaymentIsRecordedWithoutStockChange() {
    Id pid;
    System.runAs(customer()) {
      GVCheckoutController.Summary s = prepare();
      pid = s.paymentId;
      ready(pid, 'Ready');
    }
    Map<String, Object> failed = evidence();
    failed.put('status', 'failed');
    failed.put('captured', false);
    String raw = JSON.serialize(
      new Map<String, Object>{
        'event' => 'payment.failed',
        'payload' => new Map<String, Object>{
          'payment' => new Map<String, Object>{ 'entity' => failed }
        }
      }
    );
    String signature = EncodingUtil.convertToHex(
      Crypto.generateMac(
        'HmacSHA256',
        Blob.valueOf(raw),
        Blob.valueOf('unit-test-webhook-secret')
      )
    );
    GVPaymentWebhook.process(
      new List<GoldVuee_Payment_Verification__e>{
        new GoldVuee_Payment_Verification__e(
          Source__c = 'HostedLink',
          Raw_Body__c = raw,
          Razorpay_Signature__c = signature
        )
      }
    );
    Payment__c p = [
      SELECT
        Payment_Status__c,
        Gateway_Response__c,
        Razorpay_Order_ID__c,
        Transaction_ID__c
      FROM Payment__c
      WHERE Id = :pid
      WITH SYSTEM_MODE
    ];
    System.assertEquals('Pending', p.Payment_Status__c);
    System.assertEquals(
      'pay_Hosted1',
      GVCheckoutService.attempt(p).lastFailurePaymentId
    );
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Inventory_Movement__c WITH SYSTEM_MODE]
    );
  }
  @IsTest
  static void missingWebhookConfigurationRequestsRedelivery() {
    delete as system [SELECT Id FROM GV_Payment_Config__c WITH SYSTEM_MODE];
    Boolean retryRequested = false;
    try {
      GVPaymentWebhook.deliver(
        new List<GoldVuee_Payment_Verification__e>{
          new GoldVuee_Payment_Verification__e(
            Source__c = 'HostedLink',
            Raw_Body__c = '{}',
            Razorpay_Signature__c = 'invalid'
          )
        }
      );
    } catch (EventBus.RetryableException error) {
      retryRequested = true;
    }
    System.assert(
      retryRequested,
      'Unavailable server signing configuration must request event redelivery.'
    );
  }
  @IsTest
  static void unchangedHostedCheckoutReusesSameAttempt() {
    System.runAs(customer()) {
      GVCheckoutController.Summary original = prepare();
      ready(original.paymentId, 'Ready');
      GVCheckoutController.Summary repeated = GVCheckoutController.prepareOrder(
        delivery()
      );
      System.assertEquals(original.orderId, repeated.orderId);
      System.assertEquals(original.paymentId, repeated.paymentId);
      System.assertEquals(1, [SELECT COUNT() FROM Payment__c WITH SYSTEM_MODE]);
    }
  }
  @IsTest
  static void legacyPendingPaymentDoesNotBlockCurrentCheckout() {
    System.runAs(customer()) {
      GVCheckoutController.Summary legacy = prepare();
      ready(legacy.paymentId, 'Ready');
      update as system new Payment__c(
        Id = legacy.paymentId,
        Gateway_Response__c = null
      );
      GVCheckoutController.Summary current = GVCheckoutController.prepareOrder(
        delivery()
      );
      System.assertNotEquals(legacy.orderId, current.orderId);
      System.assertEquals(
        'Pending',
        GVRazorpayController.paymentStatus(legacy.paymentId).paymentStatus
      );
      System.assertEquals(
        200,
        GVCheckoutController.loadOrder(legacy.orderId).total
      );
    }
  }
  @IsTest
  static void addressAcceptsAllRequestedPhoneFormatsAndStoresTenDigits() {
    System.runAs(customer()) {
      GVCartController.addToCart(product(), 1);
      Test.startTest();
      for(String numberValue : new List<String>{'9691184503', '+919691184503', '+91 9691184503'}) {
        GVCheckoutController.Delivery d = delivery(); d.phone = numberValue;
        GVCheckoutController.Summary saved = GVCheckoutController.prepareOrder(d);
        System.assertEquals('9691184503', saved.delivery.phone);
        System.assertEquals('1 Gold Road', saved.delivery.street);
        System.assertEquals('Hosted Customer', saved.delivery.fullName);
        String stored = [SELECT Shipping_Address__c FROM Jewellery_Order__c WHERE Id=:saved.orderId WITH SYSTEM_MODE].Shipping_Address__c;
        System.assertEquals('Hosted Customer\n9691184503\n1 Gold Road', stored);
      }
      Test.stopTest();
    }
  }
  @IsTest
  static void contactAutofillUsesOnlyMatchingValidatedFields() {
    User buyer = customer();
    update as system new Contact(Id=buyer.ContactId, MobilePhone='+91 9691184503', Phone='9876543210',
      MailingStreet='42 Jewellery Lane', OtherStreet='Do not use the other address', MailingCity='Indore',
      MailingCountryCode='IN', MailingStateCode='MP', MailingPostalCode='452001');
    System.runAs(buyer) {
      GVCheckoutController.Delivery d = GVCheckoutController.loadDelivery();
      System.assertEquals('9691184503', d.phone);System.assertEquals('42 Jewellery Lane', d.street);
      System.assertEquals('Indore', d.city);System.assertEquals('Madhya Pradesh', d.state);
      System.assertEquals('452001', d.postalCode);System.assertEquals('India', d.country);
    }
    update as system new Contact(Id=buyer.ContactId, MobilePhone='not a mobile', MailingStreet='+91 9691184503', MailingPostalCode='invalid');
    System.runAs(buyer) {
      GVCheckoutController.Delivery d = GVCheckoutController.loadDelivery();
      System.assertEquals('9876543210', d.phone, 'Use the valid Phone when MobilePhone is invalid.');
      System.assertEquals('', d.street, 'A phone-only MailingStreet must not prefill an address.');
      System.assertEquals('', d.postalCode);
    }
  }
  @IsTest
  static void addressRejectsInvalidPhoneAndPhoneOnlyStreet() {
    System.runAs(customer()) {
      GVCartController.addToCart(product(), 1);
      for(String numberValue : new List<String>{'12345', '+449691184503', '96911abc4503', '+919691184503abc', '919691184503'}) {
        GVCheckoutController.Delivery d = delivery(); d.phone = numberValue;
        Boolean rejected = false;
        try { GVCheckoutController.prepareOrder(d); } catch(AuraHandledException error) { rejected = true; }
        System.assert(rejected, 'Reject invalid mobile format: '+numberValue);
      }
      GVCheckoutController.Delivery d = delivery(); d.street = '+91 9691184503';
      Boolean rejected = false;
      try { GVCheckoutController.prepareOrder(d); } catch(AuraHandledException error) { rejected = true; }
      System.assert(rejected, 'A phone number is not a street address.');
    }
  }
}
