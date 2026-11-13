@IsTest
private class GVCheckoutJourneyTest {
  private static final String SECRET = 'journey-test-secret';
  @TestSetup
  static void seed() {
    String key = String.valueOf(Crypto.getRandomLong()).replace('-', '');
    UserRole role = new UserRole(
      Name = 'Journey Owner',
      DeveloperName = 'Journey_Owner'
    );
    insert as system role;
    User owner = new User(
      ProfileId = UserInfo.getProfileId(),
      UserRoleId = role.Id,
      LastName = 'JourneyOwner',
      Alias = 'jowner',
      Email = 'owner@example.test',
      Username = 'owner' + key + '@example.test',
      CommunityNickname = 'owner' + key,
      TimeZoneSidKey = 'Asia/Kolkata',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
    insert as system owner;
    System.runAs(owner) {
      Account a = new Account(Name = 'Journey Account');
      insert as system a;
      Contact c = new Contact(LastName = 'JourneyCustomer', AccountId = a.Id);
      insert as system c;
      Profile profile = [
        SELECT Id
        FROM Profile
        WHERE Name = 'GoldVuee Customer'
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      User customer = new User(
        ProfileId = profile.Id,
        ContactId = c.Id,
        LastName = 'JourneyCustomer',
        Alias = 'jcust',
        Email = 'customer@example.test',
        Username = 'customer' + key + '@example.test',
        CommunityNickname = 'customer' + key,
        TimeZoneSidKey = 'Asia/Kolkata',
        LocaleSidKey = 'en_US',
        EmailEncodingKey = 'UTF-8',
        LanguageLocaleKey = 'en_US'
      );
      insert as system customer;
    }
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Jewellery_Category__c cat = new Jewellery_Category__c(
        Name = 'Journey Rings',
        Active__c = true
      );
      insert as system cat;
      insert as system new Jewellery_Product__c(
        Name = 'Journey Ring',
        Category__c = cat.Id,
        Product_Code__c = 'JOURNEY-1',
        SKU__c = 'JOURNEY-1',
        Weight__c = 1,
        Price__c = 1000,
        Discount_Price__c = 900,
        Stock_Quantity__c = 10,
        Reserved_Quantity__c = 0,
        New_Arrival__c = true,
        Active__c = true
      );
      insert as system new GV_Payment_Config__c(
        Name = 'RazorpayTest',
        Razorpay_Test_Secret__c = SECRET,
        Webhook_Secret__c = SECRET
      );
    }
  }
  private static User customer() {
    return [
      SELECT Id, ContactId
      FROM User
      WHERE LastName = 'JourneyCustomer'
      WITH SYSTEM_MODE
      LIMIT 1
    ];
  }
  private static Jewellery_Product__c product() {
    return [
      SELECT Id, Stock_Quantity__c, Reserved_Quantity__c
      FROM Jewellery_Product__c
      WHERE SKU__c = 'JOURNEY-1'
      WITH SYSTEM_MODE
      LIMIT 1
    ];
  }
  private static GVOnlineCheckoutController.CheckoutResult prepare() {
    GVCartController.addToCart(product().Id, 1);
    return GVOnlineCheckoutController.prepareOnlineOrder(
      '10 Gold Street',
      'Indore',
      'Madhya Pradesh',
      '452001',
      'India'
    );
  }
  private class GatewayMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      Map<String, Object> payment = new Map<String, Object>{
        'id' => 'pay_Journey',
        'order_id' => 'order_Journey',
        'amount' => 90000,
        'currency' => 'INR',
        'status' => 'captured',
        'captured' => true,
        'method' => 'upi'
      };
      if (req.getMethod() == 'POST') {
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
          req.getBody()
        );
        res.setBody(
          JSON.serialize(
            new Map<String, Object>{
              'id' => 'order_Journey',
              'amount' => body.get('amount'),
              'currency' => 'INR',
              'status' => 'created',
              'receipt' => body.get('receipt')
            }
          )
        );
      } else if (req.getEndpoint().endsWith('/payments/pay_Journey'))
        res.setBody(JSON.serialize(payment));
      else if (req.getEndpoint().contains('/orders?')) {
        res.setBody('{"items":[]}');
      } else
        res.setBody(
          JSON.serialize(
            new Map<String, Object>{ 'items' => new List<Object>{ payment } }
          )
        );
      return res;
    }
  }
  @IsTest
  static void cartAndPreparation() {
    System.runAs(customer()) {
      Id pid = product().Id;
      System.assertEquals(0, GVCartController.getCart().itemCount);
      GVCartController.CartResponse cart = GVCartController.addToCart(pid, 1);
      cart = GVCartController.addToCart(pid, 1);
      System.assertEquals(2, cart.itemCount);
      cart = GVCartController.updateCartItem(cart.items[0].Id, 1);
      System.assertEquals(900, cart.totalAmount);
      GVCartController.removeCartItem(cart.items[0].Id);
      System.assertEquals(0, GVCartController.getCart().itemCount);
      GVOnlineCheckoutController.CheckoutResult result = prepare();
      System.assertEquals(900, result.grandTotal);
      GVOnlineCheckoutController.CheckoutResult retry = GVOnlineCheckoutController.prepareOnlineOrder(
        '10 Gold Street',
        'Indore',
        'Madhya Pradesh',
        '452001',
        'India'
      );
      System.assertEquals(result.orderId, retry.orderId);
      System.assertEquals(
        result.paymentId,
        GVOnlineCheckoutController.resumeCheckout().paymentId
      );
      Boolean rejected = false;
      try {
        GVCartController.addToCart(pid, 1);
      } catch (AuraHandledException e) {
        rejected = true;
      }
      System.assert(rejected);
      rejected = false;
      try {
        GVOnlineCheckoutController.prepareOnlineOrder(
          'Changed',
          'Indore',
          'Madhya Pradesh',
          '452001',
          'India'
        );
      } catch (AuraHandledException e) {
        rejected = true;
      }
      System.assert(rejected);
      System.assertEquals(1, GVOrderHistoryController.getMyOrders().size());
      System.assertEquals(
        1,
        GVOrderHistoryController.getMyOrderDetail(result.orderId).items.size()
      );
      System.assert(GVMyAccountController.getMyAccount().loggedIn);
    }
  }
  @IsTest
  static void initializeOnce() {
    Test.setMock(HttpCalloutMock.class, new GatewayMock());
    System.runAs(customer()) {
      GVOnlineCheckoutController.CheckoutResult order = prepare();
      Test.startTest();
      System.assertEquals(
        'Queued',
        GVPaymentController.initiatePayment(order.paymentId).state
      );
      System.assertEquals(
        'Queued',
        GVPaymentController.initiatePayment(order.paymentId).state
      );
      Test.stopTest();
      System.assertEquals(
        'order_Journey',
        GVPaymentController.paymentState(order.paymentId).razorpayOrderId
      );
      update as system new Payment__c(
        Id = order.paymentId,
        Reconciliation_State__c = 'Unpaid - verified',
        Last_Checked_At__c = System.now()
      );
      System.assertEquals(
        'Ready',
        GVPaymentController.initiatePayment(order.paymentId).state
      );
    }
  }
  @IsTest
  static void signatureAndRecoveredConfirmation() {
    Test.setMock(HttpCalloutMock.class, new GatewayMock());
    GVOnlineCheckoutController.CheckoutResult order;
    System.runAs(customer()) {
      order = prepare();
    }
    update as system new Payment__c(
      Id = order.paymentId,
      Razorpay_Order_ID__c = 'order_Journey'
    );
    String sig = EncodingUtil.convertToHex(
      Crypto.generateMac(
        'HmacSHA256',
        Blob.valueOf('order_Journey|pay_Journey'),
        Blob.valueOf(SECRET)
      )
    );
    System.runAs(customer()) {
      Test.startTest();
      System.assertEquals(
        'WAITING',
        GVPaymentVerificationController.requestSignatureVerification(
          order.paymentId,
          'pay_Journey',
          sig
        )
      );
      Test.getEventBus().deliver();
      Test.stopTest();
      System.assertEquals(
        'CONFIRMED',
        GVPaymentVerificationController.signatureVerificationState(
          order.paymentId,
          'pay_Journey'
        )
      );
      System.assert(
        GVPaymentVerificationController.verifyPayment(
            order.paymentId,
            'pay_Journey'
          )
          .success
      );
    }
    System.assertEquals(9, product().Stock_Quantity__c);
    System.assertEquals(0, product().Reserved_Quantity__c);
  }
  @IsTest
  static void expirationAndLateCapture() {
    GVOnlineCheckoutController.CheckoutResult order;
    User user = customer();
    System.runAs(user) {
      order = prepare();
    }
    Stock_Reservation__c reservation = [
      SELECT Id
      FROM Stock_Reservation__c
      WHERE Jewellery_Order__c = :order.orderId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    update as system new Stock_Reservation__c(
      Id = reservation.Id,
      Expires_At__c = System.now().addMinutes(-1)
    );
    System.assert(
      GVAbandonedCheckoutService.recoverExpiredCheckout(
        [
          SELECT Shopping_Cart__c
          FROM Jewellery_Order__c
          WHERE Id = :order.orderId
          WITH SYSTEM_MODE
        ]
        .Shopping_Cart__c,
        user.ContactId
      )
    );
    System.assertEquals(0, product().Reserved_Quantity__c);
    System.runAs(user) {
      order = GVOnlineCheckoutController.prepareOnlineOrder(
        '10 Gold Street',
        'Indore',
        'Madhya Pradesh',
        '452001',
        'India'
      );
    }
    update as system new Payment__c(
      Id = order.paymentId,
      Razorpay_Order_ID__c = 'order_Journey'
    );
    reservation = [
      SELECT Id
      FROM Stock_Reservation__c
      WHERE Jewellery_Order__c = :order.orderId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    update as system new Stock_Reservation__c(
      Id = reservation.Id,
      Expires_At__c = System.now().addMinutes(-1)
    );
    Test.setMock(HttpCalloutMock.class, new GatewayMock());
    Test.startTest();
    System.enqueueJob(new GVGatewayWorker(order.paymentId, 'reconcile'));
    Test.stopTest();
    Payment__c p = [
      SELECT Payment_Status__c, Reconciliation_State__c
      FROM Payment__c
      WHERE Id = :order.paymentId
      WITH SYSTEM_MODE
    ];
    System.assertEquals('Pending', p.Payment_Status__c);
    System.assertEquals(
      'Captured - stock review required',
      p.Reconciliation_State__c
    );
    System.assertEquals(10, product().Stock_Quantity__c);
  }
  @IsTest
  static void browseAndOwnership() {
    System.assertEquals(
      1,
      GVProductController.getProducts(null, 'Journey').size()
    );
    System.assertEquals(
      product().Id,
      GVProductController.getProductById(product().Id).Id
    );
    System.assertEquals(1, GVNewArrivalsController.getNewArrivals().size());
    System.assert(!GVMyAccountController.getMyAccount().loggedIn);
    Boolean denied = false;
    try {
      GVOrderHistoryController.getMyOrders();
    } catch (AuraHandledException e) {
      denied = true;
    }
    System.assert(denied);
    System.runAs(customer()) {
      denied = false;
      try {
        GVOrderHistoryController.getMyOrderDetail(product().Id);
      } catch (AuraHandledException e) {
        denied = true;
      }
      System.assert(denied);
    }
  }
  @IsTest
  static void administratorStockAndFulfillment() {
    Id pid = product().Id;
    GVCheckoutOperations.adjustStock(pid, 2, 'Test stock receipt');
    GVCheckoutOperations.adjustStock(pid, -1, 'Test correction');
    System.assertEquals(11, product().Stock_Quantity__c);
    System.assertEquals(1, GVCheckoutOperations.inventory().size());
    GVOnlineCheckoutController.CheckoutResult order;
    System.runAs(customer()) {
      order = prepare();
      Boolean denied = false;
      try {
        GVCheckoutOperations.inventory();
      } catch (AuraHandledException e) {
        denied = true;
      }
      System.assert(denied);
    }
    System.assertEquals(1, GVCheckoutOperations.reviewQueue().size());
    Boolean rejected = false;
    try {
      GVCheckoutOperations.advanceOrder(order.orderId, 'Processing');
    } catch (AuraHandledException e) {
      rejected = true;
    }
    System.assert(rejected);
    update as system new Jewellery_Order__c(
      Id = order.orderId,
      Payment_Status__c = 'Paid',
      Order_Status__c = 'Confirmed'
    );
    GVCheckoutOperations.advanceOrder(order.orderId, 'Processing');
    GVCheckoutOperations.advanceOrder(order.orderId, 'Shipped');
    GVCheckoutOperations.advanceOrder(order.orderId, 'Delivered');
    System.assertEquals(
      'Delivered',
      [
        SELECT Order_Status__c
        FROM Jewellery_Order__c
        WHERE Id = :order.orderId
        WITH SYSTEM_MODE
      ]
      .Order_Status__c
    );
    rejected = false;
    try {
      GVCheckoutOperations.adjustStock(
        pid,
        -11,
        'Must not consume reservations'
      );
    } catch (AuraHandledException e) {
      rejected = true;
    }
    System.assert(rejected);
    System.assertEquals(11, product().Stock_Quantity__c);
  }
  @IsTest
  static void signedWebhookIsDeduplicated() {
    Test.setMock(HttpCalloutMock.class, new GatewayMock());
    GVOnlineCheckoutController.CheckoutResult order;
    System.runAs(customer()) {
      order = prepare();
    }
    update as system new Payment__c(
      Id = order.paymentId,
      Razorpay_Order_ID__c = 'order_Journey'
    );
    String body = '{"event":"payment.captured","payload":{"payment":{"entity":{"order_id":"order_Journey"}}}}';
    String signature = EncodingUtil.convertToHex(
      Crypto.generateMac('HmacSHA256', Blob.valueOf(body), Blob.valueOf(SECRET))
    );
    GoldVuee_Payment_Verification__e eventRecord = new GoldVuee_Payment_Verification__e(
      Source__c = 'Webhook',
      Raw_Body__c = body,
      Razorpay_Signature__c = signature
    );
    Test.startTest();
    GVPaymentVerificationEventHandler.process(
      new List<GoldVuee_Payment_Verification__e>{ eventRecord, eventRecord }
    );
    GVPaymentVerificationEventHandler.process(
      new List<GoldVuee_Payment_Verification__e>{ eventRecord }
    );
    Test.stopTest();
    System.assertEquals(
      1,
      [SELECT COUNT() FROM GV_Webhook_Receipt__c WITH SYSTEM_MODE]
    );
    System.assertEquals(9, product().Stock_Quantity__c);
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Inventory_Movement__c WITH SYSTEM_MODE]
    );
  }
  @IsTest
  static void operatorRecoversExpiredCapturedPayment() {
    Test.setMock(HttpCalloutMock.class, new GatewayMock());
    GVOnlineCheckoutController.CheckoutResult order;
    System.runAs(customer()) {
      order = prepare();
    }
    update as system new Payment__c(
      Id = order.paymentId,
      Razorpay_Order_ID__c = 'order_Journey'
    );
    Stock_Reservation__c hold = [
      SELECT Id
      FROM Stock_Reservation__c
      WHERE Jewellery_Order__c = :order.orderId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    update as system new Stock_Reservation__c(
      Id = hold.Id,
      Expires_At__c = System.now().addMinutes(-1)
    );
    Test.startTest();
    GVRazorpayService.RazorpayPaymentDetails captured = GVRazorpayService.fetchPayment(
      'pay_Journey'
    );
    System.assert(
      !GVCheckoutEngine.finalizeCaptured(order.paymentId, captured).success
    );
    GVCheckoutEngine.renewCapturedHold(order.paymentId);
    System.assert(
      GVCheckoutEngine.finalizeCaptured(order.paymentId, captured).success
    );
    System.assert(
      GVCheckoutEngine.finalizeCaptured(order.paymentId, captured).success
    );
    Test.stopTest();
    System.assertEquals(9, product().Stock_Quantity__c);
    System.assertEquals(0, product().Reserved_Quantity__c);
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Inventory_Movement__c WITH SYSTEM_MODE]
    );
    System.runAs(customer()) {
      Boolean denied = false;
      try {
        GVCheckoutOperations.approveLateCapture(order.paymentId);
      } catch (AuraHandledException e) {
        denied = true;
      }
      System.assert(denied);
    }
  }
  @IsTest
  static void operationalSchedule() {
    Test.startTest();
    Map<String, Boolean> readiness = GVCheckoutOperations.configureReconciliation();
    System.assert(readiness.get('scheduled'));
    System.assert(readiness.get('checkoutSecretReady'));
    System.assert(readiness.get('webhookSecretReady'));
    Test.stopTest();
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM CronTrigger
        WHERE CronJobDetail.Name = 'GoldVuee Hourly Reconciliation'
        WITH SYSTEM_MODE
      ]
    );
  }
  @IsTest
  static void reconciledUnpaidRestartAndThrottle() {
    Test.setMock(HttpCalloutMock.class, new GatewayMock());
    GVOnlineCheckoutController.CheckoutResult order;
    User user = customer();
    System.runAs(user) {
      order = prepare();
    }
    update as system new Payment__c(
      Id = order.paymentId,
      Razorpay_Order_ID__c = 'order_Unpaid'
    );
    List<Stock_Reservation__c> holds = [
      SELECT Id, Expires_At__c
      FROM Stock_Reservation__c
      WHERE Jewellery_Order__c = :order.orderId
      WITH SYSTEM_MODE
    ];
    for (Stock_Reservation__c hold : holds)
      hold.Expires_At__c = System.now().addMinutes(-1);
    update as system holds;
    Set<Id> ids = new Map<Id, Stock_Reservation__c>(holds).keySet();
    GVInventoryService.change(ids, false);
    update as system new Payment__c(
      Id = order.paymentId,
      Reconciliation_State__c = 'Expired - stock released',
      Last_Checked_At__c = System.now()
    );
    System.runAs(user) {
      System.assertEquals(
        'Expired',
        GVPaymentController.paymentState(order.paymentId).state
      );
      Boolean denied = false;
      try {
        GVOnlineCheckoutController.cancelExpiredCheckout(order.paymentId);
      } catch (AuraHandledException e) {
        denied = true;
      }
      System.assert(
        denied,
        'A prior lookup cannot revoke an initialized gateway order.'
      );
      System.assertEquals(
        order.orderId,
        GVOnlineCheckoutController.resumeCheckout().orderId
      );
      Test.startTest();
      Integer before = Limits.getQueueableJobs();
      GVOnlineCheckoutController.requestReconciliation(order.paymentId);
      GVOnlineCheckoutController.requestReconciliation(order.paymentId);
      System.assertEquals(before + 1, Limits.getQueueableJobs());
      Test.stopTest();
    }
  }

  @IsTest
  static void safeCancellationReleasesOnceAndUnlocksBag() {
    System.runAs(customer()) {
      GVOnlineCheckoutController.CheckoutResult o = prepare();
      System.assert(
        GVOnlineCheckoutController.checkoutRecovery(o.paymentId).canCancel
      );
      System.assertEquals(
        'Cancelled',
        GVOnlineCheckoutController.cancelUnpaidCheckout(o.paymentId).state
      );
      System.assertEquals(
        'Cancelled',
        GVOnlineCheckoutController.cancelUnpaidCheckout(o.paymentId).state
      );
      System.assertEquals(0, product().Reserved_Quantity__c);
      System.assertEquals(10, product().Stock_Quantity__c);
      System.assertEquals(null, GVOnlineCheckoutController.resumeCheckout());
      GVCartController.CartResponse bag = GVCartController.getCart();
      System.assertEquals(
        2,
        GVCartController.updateCartItem(bag.items[0].Id, 2).itemCount
      );
      GVCartController.removeCartItem(bag.items[0].Id);
      System.assertEquals(0, GVCartController.getCart().itemCount);
      System.assertEquals(
        0,
        [SELECT COUNT() FROM Inventory_Movement__c WITH SYSTEM_MODE]
      );
      System.assertEquals(
        1,
        [SELECT COUNT() FROM Jewellery_Order__c WITH SYSTEM_MODE]
      );
    }
  }
  @IsTest
  static void initializedAndUnknownPaymentsCannotCancel() {
    System.runAs(customer()) {
      GVOnlineCheckoutController.CheckoutResult o = prepare();
      update as system new Payment__c(
        Id = o.paymentId,
        Initialization_State__c = 'Unknown'
      );
      System.assertEquals(
        'Uncertain',
        GVOnlineCheckoutController.cancelUnpaidCheckout(o.paymentId).state
      );
      System.assertEquals(1, product().Reserved_Quantity__c);
      update as system new Payment__c(
        Id = o.paymentId,
        Razorpay_Order_ID__c = 'order_Unit'
      );
      System.assertEquals(
        'Uncertain',
        GVOnlineCheckoutController.cancelUnpaidCheckout(o.paymentId).state
      );
      System.assertEquals(1, product().Reserved_Quantity__c);
      Boolean denied = false;
      try {
        GVPaymentController.initiatePayment(o.paymentId);
      } catch (AuraHandledException e) {
        denied = true;
      }
      System.assert(
        denied,
        'An existing gateway order must be reconciled before retry.'
      );
    }
  }
  @IsTest
  static void paidOrderReturnsConfirmationWithoutRelease() {
    Test.setMock(HttpCalloutMock.class, new GatewayMock());
    System.runAs(customer()) {
      GVOnlineCheckoutController.CheckoutResult o = prepare();
      update as system new Payment__c(
        Id = o.paymentId,
        Razorpay_Order_ID__c = 'order_Journey'
      );
      GVRazorpayService.RazorpayPaymentDetails gateway = GVRazorpayService.fetchPayment(
        'pay_Journey'
      );
      System.assert(
        GVCheckoutEngine.finalizeCaptured(o.paymentId, gateway).success
      );
      System.assertEquals(
        'Confirmed',
        GVOnlineCheckoutController.cancelUnpaidCheckout(o.paymentId).state
      );
      System.assertEquals(9, product().Stock_Quantity__c);
      System.assertEquals(0, product().Reserved_Quantity__c);
      System.assertEquals(
        1,
        [SELECT COUNT() FROM Inventory_Movement__c WITH SYSTEM_MODE]
      );
    }
  }
  @IsTest
  static void recoveryAndCancellationRejectForeignOwnership() {
    GVOnlineCheckoutController.CheckoutResult o;
    System.runAs(customer()) {
      o = prepare();
    }
    Contact other = new Contact(LastName = 'Other customer');
    insert as system other;
    update as system new Jewellery_Order__c(
      Id = o.orderId,
      Customer__c = other.Id
    );
    System.runAs(customer()) {
      System.assertEquals(null, GVOnlineCheckoutController.resumeCheckout());
      Boolean denied = false;
      try {
        GVOnlineCheckoutController.checkoutRecovery(o.paymentId);
      } catch (AuraHandledException e) {
        denied = true;
      }
      System.assert(denied);
      denied = false;
      try {
        GVOnlineCheckoutController.cancelUnpaidCheckout(o.paymentId);
      } catch (AuraHandledException e) {
        denied = true;
      }
      System.assert(denied);
    }
    System.assertEquals(1, product().Reserved_Quantity__c);
  }
  private class AttemptMock implements HttpCalloutMock {
    String status;
    AttemptMock(String value) {
      status = value;
    }
    public HttpResponse respond(HttpRequest req) {
      System.assertEquals(
        'GET',
        req.getMethod(),
        'Recovery must not create a gateway order.'
      );
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      res.setBody(
        status == 'empty'
          ? '{"items":[]}'
          : '{"items":[{"id":"pay_Unit","order_id":"order_Unit","status":"' +
            status +
            '"}]}'
      );
      return res;
    }
  }
  @IsTest
  static void authorizedAttemptDoesNotReleaseExpiredInventory() {
    GVOnlineCheckoutController.CheckoutResult o;
    System.runAs(customer()) {
      o = prepare();
    }
    update as system new Payment__c(
      Id = o.paymentId,
      Razorpay_Order_ID__c = 'order_Unit'
    );
    List<Stock_Reservation__c> holds = [
      SELECT Id, Expires_At__c
      FROM Stock_Reservation__c
      WHERE Jewellery_Order__c = :o.orderId
      WITH SYSTEM_MODE
    ];
    for (Stock_Reservation__c hold : holds)
      hold.Expires_At__c = System.now().addMinutes(-1);
    update as system holds;
    Test.setMock(HttpCalloutMock.class, new AttemptMock('authorized'));
    Test.startTest();
    new GVGatewayWorker(o.paymentId, 'reconcile').execute(null);
    Test.stopTest();
    System.assertEquals(1, product().Reserved_Quantity__c);
    System.runAs(customer()) {
      System.assert(
        !GVOnlineCheckoutController.checkoutRecovery(o.paymentId).canRetry
      );
    }
  }
  @IsTest
  static void unpaidLookupAllowsResumeWithoutAnotherOrderOrReservation() {
    GVOnlineCheckoutController.CheckoutResult o;
    System.runAs(customer()) {
      o = prepare();
    }
    update as system new Payment__c(
      Id = o.paymentId,
      Razorpay_Order_ID__c = 'order_Unit'
    );
    Test.setMock(HttpCalloutMock.class, new AttemptMock('empty'));
    Test.startTest();
    new GVGatewayWorker(o.paymentId, 'reconcile').execute(null);
    Test.stopTest();
    System.runAs(customer()) {
      System.assert(
        GVOnlineCheckoutController.checkoutRecovery(o.paymentId).canRetry
      );
      System.assertEquals(
        'order_Unit',
        GVPaymentController.initiatePayment(o.paymentId).razorpayOrderId
      );
      System.assertEquals(
        o.orderId,
        GVOnlineCheckoutController.resumeCheckout().orderId
      );
    }
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Jewellery_Order__c WITH SYSTEM_MODE]
    );
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Stock_Reservation__c WITH SYSTEM_MODE]
    );
    System.assertEquals(1, product().Reserved_Quantity__c);
  }
  @IsTest
  static void expiredGatewayOrderRemainsHeldEvenWithoutCapture() {
    GVOnlineCheckoutController.CheckoutResult o;
    System.runAs(customer()) {
      o = prepare();
    }
    update as system new Payment__c(
      Id = o.paymentId,
      Razorpay_Order_ID__c = 'order_Unit'
    );
    List<Stock_Reservation__c> holds = [
      SELECT Id, Expires_At__c
      FROM Stock_Reservation__c
      WHERE Jewellery_Order__c = :o.orderId
      WITH SYSTEM_MODE
    ];
    for (Stock_Reservation__c hold : holds)
      hold.Expires_At__c = System.now().addMinutes(-1);
    update as system holds;
    Test.setMock(HttpCalloutMock.class, new AttemptMock('empty'));
    Test.startTest();
    new GVGatewayWorker(o.paymentId, 'reconcile').execute(null);
    Test.stopTest();
    System.assertEquals(1, product().Reserved_Quantity__c);
    System.runAs(customer()) {
      System.assertEquals(
        'Uncertain',
        GVOnlineCheckoutController.cancelUnpaidCheckout(o.paymentId).state
      );
    }
  }
}
