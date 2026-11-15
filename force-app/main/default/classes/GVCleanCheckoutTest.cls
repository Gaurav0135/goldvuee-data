@IsTest
private class GVCleanCheckoutTest {
  @TestSetup
  static void setup() {
    UserRole role = new UserRole(Name = 'Checkout test owner');
    insert as system role;
    String unique = String.valueOf(System.now().getTime());
    User owner = new User(
      ProfileId = UserInfo.getProfileId(),
      UserRoleId = role.Id,
      LastName = 'Owner',
      Alias = 'gvown',
      Email = 'owner@example.com',
      Username = 'owner' + unique + '@example.com',
      CommunityNickname = 'owner' + unique,
      TimeZoneSidKey = 'Asia/Kolkata',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
    insert as system owner;
    // The actual cloned customer profile supports external test users in this org.
    Profile profile = [
      SELECT Id
      FROM Profile
      WHERE Name = 'GoldVuee Customer'
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    System.runAs(owner) {
      Account account = new Account(Name = 'Checkout test account');
      insert as system account;
      List<Contact> contacts = new List<Contact>{
        new Contact(LastName = 'Customer One', AccountId = account.Id),
        new Contact(LastName = 'Customer Two', AccountId = account.Id)
      };
      insert as system contacts;
      List<User> users = new List<User>();
      for (Integer i = 0; i < 2; i++)
        users.add(
          new User(
            ProfileId = profile.Id,
            ContactId = contacts[i].Id,
            LastName = contacts[i].LastName,
            Alias = 'gvbuy' + i,
            Email = 'buyer' + i + '@example.com',
            Username = 'buyer' + i + unique + '@example.com',
            CommunityNickname = 'buyer' + i + unique,
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
        Name = 'Checkout category'
      );
      insert as system category;
      insert as system new Jewellery_Product__c(
        Name = 'Gold ring',
        Category__c = category.Id,
        Product_Code__c = 'CLEAN-RING',
        SKU__c = 'CLEAN-RING',
        Weight__c = 1,
        Price__c = 100,
        Stock_Quantity__c = 10,
        Reserved_Quantity__c = 0,
        Active__c = true
      );
      insert as system new GV_Payment_Config__c(
        Name = 'RazorpayTest',
        Webhook_Secret__c = 'checkout-test-signing-secret'
      );
    }
  }
  private static User buyer() {
    return [
      SELECT Id, ContactId
      FROM User
      WHERE Alias = 'gvbuy0'
      WITH SYSTEM_MODE
      LIMIT 1
    ];
  }
  private static Id product() {
    return [
      SELECT Id
      FROM Jewellery_Product__c
      WHERE Product_Code__c = 'CLEAN-RING'
      WITH SYSTEM_MODE
      LIMIT 1
    ]
    .Id;
  }
  private static GVCheckoutController.Delivery delivery() {
    GVCheckoutController.Delivery d = new GVCheckoutController.Delivery();
    d.fullName = 'Test Customer';
    d.phone = '9691184503';
    d.street = '42 Gold Lane';
    d.city = 'Indore';
    d.state = 'Madhya Pradesh';
    d.postalCode = '452001';
    return d;
  }
  private static GVCheckoutController.Summary prepare() {
    GVCartController.addToCart(product(), 2);
    return GVCheckoutController.prepareOrder(delivery());
  }
  private static void ready(Id pid, String state) {
    Payment__c p = GVCheckoutService.payment(pid, buyer().ContactId);
    GVCheckoutService.Attempt a = GVCheckoutService.attempt(p);
    if (a.cartId == null)
      a.cartId = GVCheckoutService.freezeCart(
        p.Jewellery_Order__r.Customer__c,
        p.Jewellery_Order__c,
        p.Jewellery_Order__r.Shopping_Cart__c
      );
    a.state = state;
    a.linkId = 'plink_' + pid;
    a.url = 'https://rzp.io/rzp/' + pid;
    a.gatewayOrderId = 'order_' + pid;
    update as system new Payment__c(
      Id = pid,
      Gateway_Response__c = JSON.serialize(a),
      Razorpay_Order_ID__c = a.gatewayOrderId
    );
  }
  private static Map<String, Object> evidence(Id pid) {
    return new Map<String, Object>{
      'id' => 'pay_' + pid,
      'order_id' => 'order_' + pid,
      'amount' => 20000,
      'currency' => 'INR',
      'status' => 'captured',
      'captured' => true,
      'method' => 'upi'
    };
  }
  private static Map<String, Object> link(Id pid, String status) {
    return new Map<String, Object>{
      'id' => 'plink_' + pid,
      'reference_id' => String.valueOf(pid),
      'short_url' => 'https://rzp.io/rzp/' + pid,
      'order_id' => 'order_' + pid,
      'amount' => 20000,
      'amount_paid' => status == 'paid' ? 20000 : 0,
      'currency' => 'INR',
      'accept_partial' => false,
      'status' => status,
      'created_at' => System.now().getTime() / 1000,
      'payments' => new List<Object>{
        new Map<String, Object>{ 'payment_id' => 'pay_' + pid }
      }
    };
  }
  private class GatewayMock implements HttpCalloutMock {
    Id pid;
    String status;
    Boolean unavailable;
    Boolean wrongAmount;
    GatewayMock(
      Id pid,
      String status,
      Boolean unavailable,
      Boolean wrongAmount
    ) {
      this.pid = pid;
      this.status = status;
      this.unavailable = unavailable;
      this.wrongAmount = wrongAmount;
    }
    public HttpResponse respond(HttpRequest req) {
      HttpResponse response = new HttpResponse();
      response.setStatusCode(unavailable ? 503 : 200);
      if (req.getEndpoint().contains('/v1/payments/pay_')) {
        response.setBody(JSON.serialize(evidence(pid)));
        return response;
      }
      if (req.getEndpoint().contains('/v1/orders/')) {
        response.setBody(
          JSON.serialize(
            new Map<String, Object>{
              'items' => new List<Object>{ evidence(pid) }
            }
          )
        );
        return response;
      }
      if (req.getMethod() == 'POST' && !req.getEndpoint().endsWith('/cancel')) {
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
          req.getBody()
        );
        pid = (Id) body.get('reference_id');
        System.assertEquals(
          20000,
          GVCheckoutService.numberValue(body.get('amount'))
        );
        System.assertEquals('INR', body.get('currency'));
        System.assertEquals(false, body.get('accept_partial'));
      }
      String returned = status == 'cancelled' &&
        req.getMethod() == 'GET'
        ? 'created'
        : status;
      Map<String, Object> data = link(pid, returned);
      if (wrongAmount)
        data.put('amount', 19999);
      response.setBody(
        JSON.serialize(
          req.getEndpoint().contains('?reference_id=')
            ? new Map<String, Object>{
                'payment_links' => new List<Object>{ data }
              }
            : data
        )
      );
      return response;
    }
  }
  private static GoldVuee_Payment_Verification__e signed(
    String kind,
    Id pid,
    Map<String, Object> paymentEvidence
  ) {
    String raw = JSON.serialize(
      new Map<String, Object>{
        'event' => kind,
        'payload' => new Map<String, Object>{
          'payment_link' => new Map<String, Object>{
            'entity' => link(pid, 'paid')
          },
          'payment' => new Map<String, Object>{ 'entity' => paymentEvidence }
        }
      }
    );
    String signature = EncodingUtil.convertToHex(
      Crypto.generateMac(
        'HmacSHA256',
        Blob.valueOf(raw),
        Blob.valueOf('checkout-test-signing-secret')
      )
    );
    return new GoldVuee_Payment_Verification__e(
      Source__c = 'HostedLink',
      Raw_Body__c = raw,
      Razorpay_Signature__c = signature
    );
  }
  @IsTest
  static void cartLifecycleUsesServerPrices() {
    System.runAs(buyer()) {
      System.assertEquals(0, GVCartController.getCart().itemCount);
      GVCartController.CartResponse c = GVCartController.addToCart(
        product(),
        1
      );
      Id cart = c.cartId;
      c = GVCartController.addToCart(product(), 2);
      System.assertEquals(1, c.items.size());
      System.assertEquals(3, c.itemCount);
      System.assertEquals(cart, c.cartId);
      c = GVCartController.updateCartItem(c.items[0].lineId, 2);
      System.assertEquals(200, c.totalAmount);
      c = GVCartController.removeCartItem(c.items[0].lineId);
      System.assertEquals(0, c.itemCount);
      System.assertEquals(
        0,
        [SELECT COUNT() FROM Stock_Reservation__c WITH SYSTEM_MODE]
      );
    }
  }
  @IsTest
  static void discountAndAvailabilityAreAuthoritative() {
    update as system new Jewellery_Product__c(
      Id = product(),
      Discount_Price__c = 90
    );
    System.runAs(buyer()) {
      GVCartController.CartResponse cart = GVCartController.addToCart(
        product(),
        2
      );
      System.assertEquals(180, cart.totalAmount);
      System.assertEquals(
        180,
        GVCheckoutController.prepareOrder(delivery()).total
      );
    }
  }
  @IsTest
  static void rejectBadQuantitiesAndMissingProduct() {
    System.runAs(buyer()) {
      for (Integer quantity : new List<Integer>{ -1, 0, 101, 11 }) {
        Boolean rejected = false;
        try {
          GVCartController.addToCart(product(), quantity);
        } catch (Exception error) {
          rejected = true;
        }
        System.assert(rejected);
      }
      Boolean missing = false;
      try {
        GVCartController.addToCart(null, 1);
      } catch (Exception error) {
        missing = true;
      }
      System.assert(missing);
    }
  }
  @IsTest
  static void customerIsolationAndMissingIdentity() {
    Boolean missing = false;
    try {
      GVCartController.getCart();
    } catch (Exception error) {
      missing = true;
    }
    System.assert(missing);
    Id lineId;
    Id pid;
    Id oid;
    System.runAs(buyer()) {
      GVCheckoutController.Summary s = prepare();
      pid = s.paymentId;
      oid = s.orderId;
      lineId = GVCartController.getCart().items[0].lineId;
    }
    User other = [
      SELECT Id
      FROM User
      WHERE Alias = 'gvbuy1'
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    System.runAs(other) {
      System.assertEquals(0, GVCartController.getCart().itemCount);
      Boolean denied = false;
      try {
        GVCartController.removeCartItem(lineId);
      } catch (Exception error) {
        denied = true;
      }
      System.assert(denied);
      denied = false;
      try {
        GVRazorpayController.paymentStatus(pid);
      } catch (Exception error) {
        denied = true;
      }
      System.assert(denied);
      denied = false;
      try {
        GVCheckoutController.loadOrder(oid);
      } catch (Exception error) {
        denied = true;
      }
      System.assert(denied);
    }
  }
  @IsTest
  static void contactMappingAndMobileFormats() {
    User user = buyer();
    update as system new Contact(
      Id = user.ContactId,
      MobilePhone = '+91 9691184503',
      Phone = '9876543210',
      MailingStreet = '42 Gold Lane',
      MailingCity = 'Indore',
      MailingCountryCode = 'IN',
      MailingStateCode = 'MP',
      MailingPostalCode = '452001'
    );
    System.runAs(user) {
      GVCheckoutController.Delivery d = GVCheckoutController.loadDelivery();
      System.assertEquals('9691184503', d.phone);
      System.assertEquals('42 Gold Lane', d.street);
      System.assertEquals('Madhya Pradesh', d.state);
      GVCartController.addToCart(product(), 2);
      Test.startTest();
      for (
        String phone : new List<String>{
          '9691184503',
          '+919691184503',
          '+91 9691184503'
        }
      ) {
        d = delivery();
        d.phone = phone;
        GVCheckoutController.Summary s = GVCheckoutController.prepareOrder(d);
        System.assertEquals('9691184503', s.delivery.phone);
        System.assertEquals('42 Gold Lane', s.delivery.street);
      }
      Test.stopTest();
    }
  }
  @IsTest
  static void invalidContactValuesStayEmpty() {
    User user = buyer();
    update as system new Contact(
      Id = user.ContactId,
      MobilePhone = 'invalid',
      Phone = '+919691184503',
      MailingStreet = '9691184503',
      MailingPostalCode = 'bad'
    );
    System.runAs(user) {
      GVCheckoutController.Delivery d = GVCheckoutController.loadDelivery();
      System.assertEquals('9691184503', d.phone);
      System.assertEquals('', d.street);
      System.assertEquals('', d.state);
      System.assertEquals('', d.postalCode);
    }
  }

  @IsTest
  static void freeFormDeliveryCanPrepareOrder() {
    System.runAs(buyer()) {
      GVCartController.addToCart(product(), 2);

      GVCheckoutController.Delivery d = delivery();

      d.phone = '+91 98765 43210';
      d.street = 'Sector 15, Palm Beach Road';
      d.city = 'Navi Mumbai';
      d.state = 'maharashtra';
      d.postalCode = '400703';
      d.country = 'India';

      GVCheckoutController.Summary s = GVCheckoutController.prepareOrder(d);

      System.assertNotEquals(null, s.orderId);
      System.assertEquals('9876543210', s.delivery.phone);
      System.assertEquals('Sector 15, Palm Beach Road', s.delivery.street);
      System.assertEquals('Navi Mumbai', s.delivery.city);
      System.assertEquals('maharashtra', s.delivery.state);
      System.assertEquals('400703', s.delivery.postalCode);
      System.assertEquals('India', s.delivery.country);

      Jewellery_Order__c savedOrder = [
        SELECT
          Shipping_Address__c,
          Shipping_City__c,
          Shipping_State__c,
          Shipping_Postal_Code__c,
          Shipping_Country__c
        FROM Jewellery_Order__c
        WHERE Id = :s.orderId
        WITH SYSTEM_MODE
        LIMIT 1
      ];

      System.assert(
        savedOrder.Shipping_Address__c.contains('Sector 15, Palm Beach Road')
      );

      System.assertEquals('Navi Mumbai', savedOrder.Shipping_City__c);
      System.assertEquals('maharashtra', savedOrder.Shipping_State__c);
      System.assertEquals('400703', savedOrder.Shipping_Postal_Code__c);
      System.assertEquals('India', savedOrder.Shipping_Country__c);
    }
  }

  @IsTest
  static void unchangedCheckoutReusesOneOrder() {
    System.runAs(buyer()) {
      GVCheckoutController.Summary s = prepare();
      GVCheckoutController.Summary again = GVCheckoutController.prepareOrder(
        delivery()
      );
      System.assertEquals(s.orderId, again.orderId);
      System.assertEquals(s.paymentId, again.paymentId);
      GVCheckoutController.Delivery changed = delivery();
      changed.city = 'Bhopal';
      GVCheckoutController.Summary edited = GVCheckoutController.prepareOrder(
        changed
      );
      System.assertEquals(s.orderId, edited.orderId);
      System.assertEquals('Bhopal', edited.delivery.city);
    }
  }
  @IsTest
  static void pendingPaymentNeverFreezesShopping() {
    System.runAs(buyer()) {
      GVCheckoutController.Summary s = prepare();
      Id oldLine = GVCartController.getCart().items[0].lineId;
      ready(s.paymentId, 'Ready');
      GVCartController.CartResponse current = GVCartController.updateCartItem(
        oldLine,
        3
      );
      System.assertEquals(3, current.itemCount);
      System.assertEquals(
        2,
        GVCheckoutController.loadOrder(s.orderId).items[0].quantity
      );
      System.assertEquals(200, GVCheckoutController.loadOrder(s.orderId).total);
      current = GVCartController.addToCart(product(), 1);
      System.assertEquals(4, current.itemCount);
      current = GVCartController.removeCartItem(current.items[0].lineId);
      System.assertEquals(0, current.itemCount);
      System.assertEquals(
        'Pending',
        GVRazorpayController.paymentStatus(s.paymentId).paymentStatus
      );
    }
  }
  @IsTest
  static void samePurchaseAcrossBagsReusesPendingAttempt() {
    System.runAs(buyer()) {
      GVCheckoutController.Summary s = prepare();
      ready(s.paymentId, 'Ready');
      Id current = GVCartController.getCart().cartId;
      GVCheckoutController.Summary repeated = GVCheckoutController.prepareOrder(
        delivery()
      );
      System.assertEquals(s.orderId, repeated.orderId);
      System.assertEquals(s.paymentId, repeated.paymentId);
      System.assertEquals(
        current,
        GVRazorpayController.paymentStatus(s.paymentId).cartId
      );
      System.assertEquals(1, [SELECT COUNT() FROM Payment__c WITH SYSTEM_MODE]);
    }
  }
  @IsTest
  static void changedBagCreatesIndependentSnapshot() {
    System.runAs(buyer()) {
      GVCheckoutController.Summary old = prepare();
      ready(old.paymentId, 'Ready');
      GVCartController.addToCart(product(), 1);
      GVCheckoutController.Summary current = GVCheckoutController.prepareOrder(
        delivery()
      );
      System.assertNotEquals(old.orderId, current.orderId);
      System.assertEquals(300, current.total);
      System.assertEquals(
        200,
        GVCheckoutController.loadOrder(old.orderId).total
      );
    }
  }
  @IsTest
  static void createHostedLinkOnlyOnce() {
    System.runAs(buyer()) {
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
  static void failedCreationStaysUnknown() {
    System.runAs(buyer()) {
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
      System.assertEquals(
        'Pending',
        GVRazorpayController.paymentStatus(s.paymentId).paymentStatus
      );
      System.assertEquals(
        0,
        [SELECT COUNT() FROM Inventory_Movement__c WITH SYSTEM_MODE]
      );
    }
  }
  @IsTest
  static void wrongGatewayAmountRejected() {
    System.runAs(buyer()) {
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
    }
  }
  @IsTest
  static void uncertainCreationReconcilesByReference() {
    System.runAs(buyer()) {
      GVCheckoutController.Summary s = prepare();
      Payment__c p = GVCheckoutService.payment(s.paymentId, buyer().ContactId);
      GVCheckoutService.Attempt a = GVCheckoutService.attempt(p);
      a.state = 'Unknown';
      p.Gateway_Response__c = JSON.serialize(a);
      update as system p;
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
  static void capturedApiRefreshDeductsOnce() {
    System.runAs(buyer()) {
      GVCheckoutController.Summary s = prepare();
      ready(s.paymentId, 'Ready');
      Test.setMock(
        HttpCalloutMock.class,
        new GatewayMock(s.paymentId, 'paid', false, false)
      );
      Test.startTest();
      GVRazorpayController.refreshPayment(s.paymentId);
      Test.stopTest();
      System.assertEquals(0, GVCartController.getCart().itemCount);
      GVCheckoutService.captured(
        s.paymentId,
        'plink_' + s.paymentId,
        evidence(s.paymentId)
      );
      System.assertEquals(0, GVCartController.getCart().itemCount);
      System.assertEquals(
        'Success',
        GVRazorpayController.paymentStatus(s.paymentId).paymentStatus
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
        [SELECT COUNT() FROM Inventory_Movement__c WITH SYSTEM_MODE]
      );
      System.assertEquals(
        'Paid',
        GVOrderHistoryController.getMyOrders()[0].paymentStatus
      );
      System.assertEquals(
        1,
        GVOrderHistoryController.getMyOrderDetail(s.orderId).items.size()
      );
    }
  }
  @IsTest
  static void delayedSignedCapturePreservesEditedCart() {
    Id pid;
    Id currentCart;
    System.runAs(buyer()) {
      GVCheckoutController.Summary s = prepare();
      pid = s.paymentId;
      ready(pid, 'Ready');
      GVCartController.addToCart(product(), 1);
      currentCart = GVCartController.getCart().cartId;
    }
    GoldVuee_Payment_Verification__e event = signed(
      'payment_link.paid',
      pid,
      evidence(pid)
    );
    GVPaymentWebhook.process(
      new List<GoldVuee_Payment_Verification__e>{ event, event }
    );
    System.runAs(buyer()) {
      System.assertEquals(currentCart, GVCartController.getCart().cartId);
      System.assertEquals(3, GVCartController.getCart().itemCount);
      System.assertEquals(
        'Success',
        GVRazorpayController.paymentStatus(pid).paymentStatus
      );
    }
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Inventory_Movement__c WITH SYSTEM_MODE]
    );
  }
  @IsTest
  static void capturedWithoutStockRemainsPaid() {
    Id pid;
    Id oid;
    System.runAs(buyer()) {
      GVCheckoutController.Summary s = prepare();
      pid = s.paymentId;
      oid = s.orderId;
      ready(pid, 'Ready');
    }
    update as system new Jewellery_Product__c(
      Id = product(),
      Stock_Quantity__c = 0
    );
    GVPaymentWebhook.process(
      new List<GoldVuee_Payment_Verification__e>{
        signed('payment_link.paid', pid, evidence(pid))
      }
    );
    System.assertEquals(
      'Success',
      [
        SELECT Payment_Status__c
        FROM Payment__c
        WHERE Id = :pid
        WITH SYSTEM_MODE
      ]
      .Payment_Status__c
    );
    System.assertEquals(
      'Paid',
      [
        SELECT Payment_Status__c
        FROM Jewellery_Order__c
        WHERE Id = :oid
        WITH SYSTEM_MODE
      ]
      .Payment_Status__c
    );
    System.runAs(buyer()) {
      System.assertEquals(2, GVCartController.getCart().itemCount);
      System.assertEquals(
        'Stock review required',
        GVRazorpayController.paymentStatus(pid).fulfillment
      );
    }
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Inventory_Movement__c WITH SYSTEM_MODE]
    );
  }
  @IsTest
  static void invalidSignatureAndAmountDoNotFulfill() {
    Id pid;
    System.runAs(buyer()) {
      GVCheckoutController.Summary s = prepare();
      pid = s.paymentId;
      ready(pid, 'Ready');
    }
    GoldVuee_Payment_Verification__e invalid = signed(
      'payment_link.paid',
      pid,
      evidence(pid)
    );
    invalid.Razorpay_Signature__c = 'bad';
    GVPaymentWebhook.process(
      new List<GoldVuee_Payment_Verification__e>{ invalid }
    );
    Map<String, Object> wrong = evidence(pid);
    wrong.put('amount', 1);
    Boolean rejected = false;
    try {
      GVCheckoutService.captured(pid, 'plink_' + pid, wrong);
    } catch (Exception error) {
      rejected = true;
    }
    System.assert(rejected);
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Inventory_Movement__c WITH SYSTEM_MODE]
    );
  }
  @IsTest
  static void failedTransactionKeepsSafeLinkRetry() {
    Id pid;
    System.runAs(buyer()) {
      GVCheckoutController.Summary s = prepare();
      pid = s.paymentId;
      ready(pid, 'Ready');
    }
    Map<String, Object> failed = evidence(pid);
    failed.put('status', 'failed');
    failed.put('captured', false);
    GVPaymentWebhook.process(
      new List<GoldVuee_Payment_Verification__e>{
        signed('payment.failed', pid, failed)
      }
    );
    System.runAs(buyer()) {
      System.assertEquals(
        'failed',
        GVRazorpayController.paymentStatus(pid).lastFailureState
      );
      System.assertEquals(
        'Pending',
        GVRazorpayController.paymentStatus(pid).paymentStatus
      );
      System.assertEquals(2, GVCartController.getCart().itemCount);
      Test.setMock(
        HttpCalloutMock.class,
        new GatewayMock(pid, 'created', false, false)
      );
      Test.startTest();
      GVRazorpayController.Result checking = GVRazorpayController.refreshPayment(
        pid
      );
      System.assertEquals('failed', checking.lastFailureState);
      System.assertEquals('Pending', checking.paymentStatus);
      Test.stopTest();
      GVRazorpayController.Result refreshed = GVRazorpayController.paymentStatus(
        pid
      );
      System.assertEquals('failed', refreshed.lastFailureState);
      System.assertEquals('Ready', refreshed.state);
      System.assertEquals('Pending', refreshed.paymentStatus);
      System.assertEquals(2, GVCartController.getCart().itemCount);
      System.assertEquals(1, [SELECT COUNT() FROM Payment__c WITH SYSTEM_MODE]);
      System.assertEquals(
        1,
        [SELECT COUNT() FROM Jewellery_Order__c WITH SYSTEM_MODE]
      );
    }
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Inventory_Movement__c WITH SYSTEM_MODE]
    );
  }
  @IsTest
  static void failedAttemptThenUnavailableGatewayStaysUnderVerification() {
    Id pid;
    System.runAs(buyer()) {
      pid = prepare().paymentId;
      ready(pid, 'Ready');
    }
    Map<String, Object> failed = evidence(pid);
    failed.put('status', 'failed');
    failed.put('captured', false);
    GVPaymentWebhook.process(
      new List<GoldVuee_Payment_Verification__e>{
        signed('payment.failed', pid, failed)
      }
    );
    System.runAs(buyer()) {
      Test.setMock(
        HttpCalloutMock.class,
        new GatewayMock(pid, 'created', true, false)
      );
      Test.startTest();
      GVRazorpayController.refreshPayment(pid);
      Test.stopTest();
      GVRazorpayController.Result status = GVRazorpayController.paymentStatus(
        pid
      );
      System.assertEquals('Unknown', status.state);
      System.assertEquals('Pending', status.paymentStatus);
      System.assertEquals('failed', status.lastFailureState);
      System.assertEquals(null, status.paymentUrl);
      System.assertEquals(
        'Payment not confirmed yet. Refresh verification before retrying.',
        status.message
      );
      System.assertEquals(2, GVCartController.getCart().itemCount);
    }
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Inventory_Movement__c WITH SYSTEM_MODE]
    );
  }
  @IsTest
  static void confirmedCancellationAllowsOneRetry() {
    System.runAs(buyer()) {
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
      System.assertEquals(
        'Failed',
        GVRazorpayController.paymentStatus(s.paymentId).paymentStatus
      );
      System.assertEquals(
        0,
        [SELECT COUNT() FROM Inventory_Movement__c WITH SYSTEM_MODE]
      );
    }
  }
  @IsTest
  static void retryReusesBusinessOrder() {
    System.runAs(buyer()) {
      GVCheckoutController.Summary s = prepare();
      ready(s.paymentId, 'Expired');
      update as system new Payment__c(
        Id = s.paymentId,
        Payment_Status__c = 'Failed'
      );
      Test.setMock(
        HttpCalloutMock.class,
        new GatewayMock(s.paymentId, 'created', false, false)
      );
      Test.startTest();
      GVRazorpayController.Result next = GVRazorpayController.retryPayment(
        s.paymentId
      );
      GVRazorpayController.Result repeated = GVRazorpayController.retryPayment(
        s.paymentId
      );
      System.assertEquals(next.paymentId, repeated.paymentId);
      Test.stopTest();
      System.assertEquals(s.orderId, next.orderId);
      System.assertNotEquals(s.paymentId, next.paymentId);
      System.assertEquals(
        1,
        [SELECT COUNT() FROM Jewellery_Order__c WITH SYSTEM_MODE]
      );
      System.assertEquals(2, [SELECT COUNT() FROM Payment__c WITH SYSTEM_MODE]);
    }
  }
  @IsTest
  static void uninitializedCancellationAndConfigurationGuard() {
    System.runAs(buyer()) {
      GVCheckoutController.Summary s = prepare();
      System.assertEquals(
        'Cancelled',
        GVRazorpayController.cancelPayment(s.paymentId).state
      );
    }
  }
  @IsTest
  static void webhookIngressAndSubscriber() {
    String raw = '{}';
    String signature = EncodingUtil.convertToHex(
      Crypto.generateMac(
        'HmacSHA256',
        Blob.valueOf(raw),
        Blob.valueOf('checkout-test-signing-secret')
      )
    );
    System.assert(
      GVPaymentWebhook.valid(raw, signature, 'checkout-test-signing-secret')
    );
    System.assert(
      !GVPaymentWebhook.valid(
        'tampered',
        signature,
        'checkout-test-signing-secret'
      )
    );
    RestContext.request = new RestRequest();
    RestContext.response = new RestResponse();
    RestContext.request.requestBody = Blob.valueOf(raw);
    GVPaymentWebhook.receive();
    System.assertEquals(401, RestContext.response.statusCode);
    RestContext.request.addHeader('X-Razorpay-Signature', signature);
    GVPaymentWebhook.receive();
    System.assertEquals(202, RestContext.response.statusCode);
    Test.getEventBus().deliver();
  }
  @IsTest
  static void missingConfigurationRequestsEventRetry() {
    delete as system [SELECT Id FROM GV_Payment_Config__c WITH SYSTEM_MODE];
    Boolean retry = false;
    try {
      GVPaymentWebhook.deliver(new List<GoldVuee_Payment_Verification__e>());
    } catch (EventBus.RetryableException error) {
      retry = true;
    }
    System.assert(retry);
    System.runAs(buyer()) {
      GVCheckoutController.Summary s = prepare();
      Boolean blocked = false;
      try {
        GVRazorpayController.startPayment(s.paymentId);
      } catch (Exception error) {
        blocked = true;
      }
      System.assert(blocked);
      System.assertEquals(2, GVCartController.getCart().itemCount);
    }
  }
  @IsTest
  static void adminInventoryAndFulfillmentRemainAvailable() {
    GVCheckoutController.Summary summary;
    System.runAs(buyer()) {
      summary = prepare();
    }
    System.assertEquals(
      false,
      GVCheckoutOperations.configureReconciliation().get('scheduled')
    );
    System.assert(!GVCheckoutOperations.inventory().isEmpty());
    System.assert(!GVCheckoutOperations.reviewQueue().isEmpty());
    GVCheckoutOperations.adjustStock(product(), 2, 'Stock arrived');
    GVCheckoutOperations.adjustStock(product(), -1, 'Audit adjustment');
    System.assertEquals(
      11,
      [
        SELECT Stock_Quantity__c
        FROM Jewellery_Product__c
        WHERE Id = :product()
        WITH SYSTEM_MODE
      ]
      .Stock_Quantity__c
    );
    update as system new Jewellery_Order__c(
      Id = summary.orderId,
      Payment_Status__c = 'Paid',
      Order_Status__c = 'Confirmed'
    );
    System.assert(!GVCheckoutOperations.fulfillmentQueue().isEmpty());
    GVCheckoutOperations.advanceOrder(summary.orderId, 'Processing');
    GVCheckoutOperations.advanceOrder(summary.orderId, 'Shipped');
    GVCheckoutOperations.advanceOrder(summary.orderId, 'Delivered');
    Boolean rejected = false;
    try {
      GVCheckoutOperations.adjustStock(
        product(),
        -100,
        'Invalid negative stock'
      );
    } catch (Exception error) {
      rejected = true;
    }
    System.assert(rejected);
    rejected = false;
    try {
      GVCheckoutOperations.approveLateCapture(summary.paymentId);
    } catch (Exception error) {
      rejected = true;
    }
    System.assert(rejected);
  }
  @IsTest
  static void adminRefreshUsesTheSameWorkerAndCustomerIsDenied() {
    Id pid;
    System.runAs(buyer()) {
      GVCheckoutController.Summary summary = prepare();
      pid = summary.paymentId;
      ready(pid, 'Ready');
      Boolean denied = false;
      try {
        GVCheckoutOperations.inventory();
      } catch (Exception error) {
        denied = true;
      }
      System.assert(denied);
    }
    Test.setMock(
      HttpCalloutMock.class,
      new GatewayMock(pid, 'created', false, false)
    );
    Test.startTest();
    GVCheckoutOperations.reconcilePayment(pid);
    Test.stopTest();
    System.runAs(buyer()) {
      System.assertEquals(
        'Ready',
        GVRazorpayController.paymentStatus(pid).state
      );
    }
  }
  @IsTest
  static void signedExpiryRecordsFailureWithoutStockDeduction() {
    Id pid;
    System.runAs(buyer()) {
      GVCheckoutController.Summary summary = prepare();
      pid = summary.paymentId;
      ready(pid, 'Ready');
    }
    String raw = JSON.serialize(
      new Map<String, Object>{
        'event' => 'payment_link.expired',
        'payload' => new Map<String, Object>{
          'payment_link' => new Map<String, Object>{
            'entity' => link(pid, 'expired')
          }
        }
      }
    );
    String signature = EncodingUtil.convertToHex(
      Crypto.generateMac(
        'HmacSHA256',
        Blob.valueOf(raw),
        Blob.valueOf('checkout-test-signing-secret')
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
    System.assertEquals(
      'Failed',
      [
        SELECT Payment_Status__c
        FROM Payment__c
        WHERE Id = :pid
        WITH SYSTEM_MODE
      ]
      .Payment_Status__c
    );
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Inventory_Movement__c WITH SYSTEM_MODE]
    );
  }
  private static void managed(Id pid, Integer age) {
    ready(pid, 'Ready');
    Payment__c p = GVCheckoutService.payment(pid, buyer().ContactId);
    GVCheckoutService.Attempt a = GVCheckoutService.attempt(p);
    a.expirySeconds = 120;
    a.linkCreatedAt = System.now().getTime() / 1000 - age;
    update as system new Payment__c(
      Id = pid,
      Gateway_Response__c = JSON.serialize(a)
    );
  }
  private class ExpiryMock implements HttpCalloutMock {
    Id pid;
    String scenario;
    Long created;
    Integer linkReads = 0;
    Integer orderReads = 0;
    Integer cancellations = 0;
    ExpiryMock(Id pid, String scenario) {
      this.pid = pid;
      this.scenario = scenario;
      created = GVCheckoutService.attempt(
          GVCheckoutService.payment(pid, buyer().ContactId)
        )
        .linkCreatedAt;
    }
    public HttpResponse respond(HttpRequest req) {
      HttpResponse response = new HttpResponse();
      response.setStatusCode(200);
      if (req.getEndpoint().contains('/v1/orders/')) {
        orderReads++;
        Boolean captured =
          scenario == 'captured' ||
          scenario == 'terminalCaptured' ||
          (scenario == 'captureRace' &&
          orderReads >= 2) ||
          (scenario == 'cancelErrorCapture' &&
          cancellations > 0);
        List<Object> items = new List<Object>();
        if (captured || scenario == 'authorized' || scenario == 'partial') {
          Map<String, Object> row = evidence(pid);
          if (scenario == 'authorized') {
            row.put('status', 'authorized');
            row.put('captured', false);
          }
          if (scenario == 'partial')
            row.put('amount', 100);
          items.add(row);
        }
        if (scenario == 'incomplete') {
          response.setBody('{"count":1}');
          return response;
        }
        response.setBody(
          JSON.serialize(
            new Map<String, Object>{ 'items' => items, 'count' => items.size() }
          )
        );
        return response;
      }
      if (req.getEndpoint().contains('/v1/payments/')) {
        response.setBody(JSON.serialize(evidence(pid)));
        return response;
      }
      if (req.getMethod() == 'POST') {
        System.assert(
          req.getEndpoint().endsWith('/cancel'),
          'Expiry must never create another link.'
        );
        System.assertEquals(
          scenario == 'unusedNoOrder' ? 0 : 1,
          orderReads,
          'Check captures before cancellation.'
        );
        System.assertEquals(0, cancellations, 'One cancellation per worker.');
        System.assert(
          !new Set<String>{
              'captured',
              'terminalCaptured',
              'authorized',
              'partial',
              'young',
              'missingTime',
              'incomplete'
            }
            .contains(scenario)
        );
        cancellations++;
        if (scenario == 'cancelTimeout' || scenario == 'cancelErrorCapture')
          response.setStatusCode(503);
      } else
        linkReads++;
      String state = 'created';
      if (scenario == 'terminalCaptured' || scenario == 'expired')
        state = 'expired';
      else if (scenario == 'captured')
        state = 'paid';
      else if (scenario == 'partial')
        state = 'partially_paid';
      else if (cancellations > 0 && scenario != 'cancelTimeout')
        state = scenario == 'captureRace' ||
          scenario == 'cancelErrorCapture'
          ? 'paid'
          : 'cancelled';
      Map<String, Object> data = link(pid, state);
      data.put('created_at', created);
      if (scenario == 'unusedNoOrder') {
        data.put('order_id', null);
        data.put('payments', null);
      }
      if (scenario == 'missingTime')
        data.remove('created_at');
      if (scenario == 'partial')
        data.put('amount_paid', 100);
      if (scenario == 'mismatchedCancellation' && linkReads > 1)
        data.put('created_at', created - 1);
      response.setBody(JSON.serialize(data));
      return response;
    }
  }
  private static Id expiryAttempt(String scenario, Integer age) {
    Id pid;
    System.runAs(buyer()) {
      pid = prepare().paymentId;
      managed(pid, age);
    }
    Test.setMock(HttpCalloutMock.class, new ExpiryMock(pid, scenario));
    return pid;
  }
  private static void refreshExpiry(Id pid) {
    Test.startTest();
    System.runAs(buyer()) {
      GVRazorpayController.refreshPayment(pid);
    }
    Test.stopTest();
  }
  private static void assertExpiryPending(Id pid) {
    System.runAs(buyer()) {
      GVRazorpayController.Result r = GVRazorpayController.paymentStatus(pid);
      System.assertEquals('Pending', r.paymentStatus);
      System.assertEquals(2, GVCartController.getCart().itemCount);
    }
    System.assertEquals(
      'pending',
      [
        SELECT Jewellery_Order__r.Order_Status__c
        FROM Payment__c
        WHERE Id = :pid
      ]
      .Jewellery_Order__r.Order_Status__c
    );
    System.assertEquals(0, [SELECT COUNT() FROM Inventory_Movement__c]);
  }
  @IsTest
  static void expiryUsesGatewayCreationNotSalesforceAge() {
    Id pid = expiryAttempt('young', 60);
    Test.setCreatedDate(pid, System.now().addDays(-1));
    refreshExpiry(pid);
    assertExpiryPending(pid);
    System.runAs(buyer()) {
      GVRazorpayController.Result r = GVRazorpayController.paymentStatus(pid);
      System.assertEquals('Ready', r.state);
      System.assertEquals(
        (GVCheckoutService.attempt(
            GVCheckoutService.payment(pid, buyer().ContactId)
          )
          .linkCreatedAt + 120) * 1000,
        r.paymentExpiresAt
      );
    }
  }
  @IsTest
  static void expiryAtBoundaryCancelsOnlyVerifiedUnpaidAndOrder() {
    Id pid = expiryAttempt('cancelled', 120);
    refreshExpiry(pid);
    System.runAs(buyer()) {
      GVRazorpayController.Result r = GVRazorpayController.paymentStatus(pid);
      System.assertEquals('Failed', r.paymentStatus);
      System.assertEquals('Cancelled', r.state);
      System.assertEquals(true, r.expiredByTimer);
      System.assert(r.message.contains('Payment time expired'));
      System.assertEquals(2, GVCartController.getCart().itemCount);
    }
    System.assertEquals(
      'Cancelled',
      [
        SELECT Jewellery_Order__r.Order_Status__c
        FROM Payment__c
        WHERE Id = :pid
      ]
      .Jewellery_Order__r.Order_Status__c
    );
    System.assertEquals(0, [SELECT COUNT() FROM Inventory_Movement__c]);
  }
  @IsTest
  static void expiryCapturedBeforeCancellationWins() {
    Id pid = expiryAttempt('captured', 121);
    refreshExpiry(pid);
    System.runAs(buyer()) {
      System.assertEquals(
        'Success',
        GVRazorpayController.paymentStatus(pid).paymentStatus
      );
    }
    System.assertEquals(1, [SELECT COUNT() FROM Inventory_Movement__c]);
  }
  @IsTest
  static void expiryCaptureRacingWithCancellationWins() {
    Id pid = expiryAttempt('captureRace', 121);
    refreshExpiry(pid);
    System.runAs(buyer()) {
      System.assertEquals(
        'Success',
        GVRazorpayController.paymentStatus(pid).paymentStatus
      );
      System.assertEquals(0, GVCartController.getCart().itemCount);
    }
    GVCheckoutService.captured(pid, 'plink_' + pid, evidence(pid));
    System.assertEquals(1, [SELECT COUNT() FROM Inventory_Movement__c]);
  }
  @IsTest
  static void expiryCancelErrorThenVerifiedCaptureWins() {
    Id pid = expiryAttempt('cancelErrorCapture', 121);
    refreshExpiry(pid);
    System.runAs(buyer()) {
      System.assertEquals(
        'Success',
        GVRazorpayController.paymentStatus(pid).paymentStatus
      );
    }
  }
  @IsTest
  static void expiryTerminalFlagCannotOverrideVerifiedCapture() {
    Id pid = expiryAttempt('terminalCaptured', 121);
    refreshExpiry(pid);
    System.runAs(buyer()) {
      System.assertEquals(
        'Success',
        GVRazorpayController.paymentStatus(pid).paymentStatus
      );
    }
  }
  @IsTest
  static void expiryAuthorizedPaymentStaysPending() {
    Id pid = expiryAttempt('authorized', 121);
    refreshExpiry(pid);
    assertExpiryPending(pid);
  }
  @IsTest
  static void expiryPartialPaymentStaysPending() {
    Id pid = expiryAttempt('partial', 121);
    refreshExpiry(pid);
    assertExpiryPending(pid);
  }
  @IsTest
  static void expiryTimeoutNeverFailsActiveLink() {
    Id pid = expiryAttempt('cancelTimeout', 121);
    refreshExpiry(pid);
    assertExpiryPending(pid);
  }
  @IsTest
  static void expiryMissingCreationTimeStaysPending() {
    Id pid = expiryAttempt('missingTime', 121);
    refreshExpiry(pid);
    assertExpiryPending(pid);
  }
  @IsTest
  static void expiryIncompletePaymentsStayPending() {
    Id pid = expiryAttempt('incomplete', 121);
    refreshExpiry(pid);
    assertExpiryPending(pid);
  }
  @IsTest
  static void expiryMismatchedPostCancellationEvidenceStaysPending() {
    Id pid = expiryAttempt('mismatchedCancellation', 121);
    refreshExpiry(pid);
    assertExpiryPending(pid);
  }
  @IsTest
  static void expiryVerifiedExpiredAndLateCaptureDeductsOnce() {
    Id pid = expiryAttempt('expired', 121);
    refreshExpiry(pid);
    System.runAs(buyer()) {
      System.assertEquals(
        'Failed',
        GVRazorpayController.paymentStatus(pid).paymentStatus
      );
    }
    GVPaymentWebhook.process(
      new List<GoldVuee_Payment_Verification__e>{
        signed('payment_link.paid', pid, evidence(pid)),
        signed('payment_link.paid', pid, evidence(pid))
      }
    );
    System.runAs(buyer()) {
      System.assertEquals(
        'Success',
        GVRazorpayController.paymentStatus(pid).paymentStatus
      );
      System.assertEquals(
        'Confirmed',
        GVRazorpayController.paymentStatus(pid).fulfillment
      );
      System.assertEquals(
        pid,
        GVRazorpayController.retryPayment(pid).paymentId
      );
    }
    System.assertEquals(1, [SELECT COUNT() FROM Inventory_Movement__c]);
    System.assertEquals(1, [SELECT COUNT() FROM Payment__c]);
  }
  @IsTest
  static void expirySafeRetryReopensOnlyTheSameUnpaidOrder() {
    Id pid = expiryAttempt('cancelled', 121);
    refreshExpiry(pid);
    Test.setMock(
      HttpCalloutMock.class,
      new GatewayMock(pid, 'created', false, false)
    );
    System.runAs(buyer()) {
      GVRazorpayController.Result r = GVRazorpayController.retryPayment(pid);
      System.assertNotEquals(pid, r.paymentId);
      System.assertEquals(
        r.paymentId,
        GVRazorpayController.retryPayment(pid).paymentId
      );
    }
    System.assertEquals(1, [SELECT COUNT() FROM Jewellery_Order__c]);
    System.assertEquals(
      'pending',
      [SELECT Order_Status__c FROM Jewellery_Order__c LIMIT 1].Order_Status__c
    );
    System.assertEquals(2, [SELECT COUNT() FROM Payment__c]);
  }
  @IsTest
  static void expirySweepReusesWorkerWithoutBrowser() {
    Id pid = expiryAttempt('cancelled', 121);
    Test.startTest();
    new GVPaymentExpiryScheduler()
      .execute(
        (Database.BatchableContext) null,
        [SELECT Id, Gateway_Response__c FROM Payment__c WHERE Id = :pid]
      );
    Test.stopTest();
    System.runAs(buyer()) {
      System.assertEquals(
        'Failed',
        GVRazorpayController.paymentStatus(pid).paymentStatus
      );
    }
  }
  @IsTest
  static void expirySweepSkipsHistoricalAttempts() {
    System.runAs(buyer()) {
      ready(prepare().paymentId, 'Ready');
    }
    Test.startTest();
    Database.executeBatch(new GVPaymentExpiryScheduler(), 1);
    Test.stopTest();
    System.assertEquals(
      'Pending',
      [SELECT Payment_Status__c FROM Payment__c LIMIT 1].Payment_Status__c
    );
  }
  @IsTest
  static void expiryScheduledDispatcherIsIndependentOfBrowser() {
    Test.startTest();
    System.schedule(
      'GoldVuee expiry mock schedule',
      '0 0 0 1 1 ? 2099',
      new GVPaymentExpiryScheduler()
    );
    Test.stopTest();
    System.assert(
      [
        SELECT COUNT()
        FROM AsyncApexJob
        WHERE ApexClass.Name = 'GVPaymentExpiryScheduler'
      ] > 0
    );
  }

  @IsTest
  static void expirySignedTerminalEventStillVerifiesCurrentCaptures() {
    Id pid = expiryAttempt('terminalCaptured', 121);
    String raw = JSON.serialize(
      new Map<String, Object>{
        'event' => 'payment_link.expired',
        'payload' => new Map<String, Object>{
          'payment_link' => new Map<String, Object>{
            'entity' => link(pid, 'expired')
          }
        }
      }
    );
    String signature = EncodingUtil.convertToHex(
      Crypto.generateMac(
        'HmacSHA256',
        Blob.valueOf(raw),
        Blob.valueOf('checkout-test-signing-secret')
      )
    );
    Test.startTest();
    GVPaymentWebhook.process(
      new List<GoldVuee_Payment_Verification__e>{
        new GoldVuee_Payment_Verification__e(
          Source__c = 'HostedLink',
          Raw_Body__c = raw,
          Razorpay_Signature__c = signature
        )
      }
    );
    System.assertEquals(
      'Pending',
      [SELECT Payment_Status__c FROM Payment__c WHERE Id = :pid]
      .Payment_Status__c
    );
    Test.stopTest();
    System.runAs(buyer()) {
      System.assertEquals(
        'Success',
        GVRazorpayController.paymentStatus(pid).paymentStatus
      );
    }
  }
  @IsTest
  static void expirySweepWaitsUntilGatewayDeadline() {
    Id pid = expiryAttempt('young', 60);
    Test.startTest();
    new GVPaymentExpiryScheduler()
      .execute(
        (Database.BatchableContext) null,
        [SELECT Id, Gateway_Response__c FROM Payment__c WHERE Id = :pid]
      );
    System.assertEquals(0, Limits.getQueueableJobs());
    Test.stopTest();
    assertExpiryPending(pid);
  }

  @IsTest
  static void expiryUnusedLinkWithoutAnOrderCanCloseOnlyWithEmptyCaptureEvidence() {
    Id pid = expiryAttempt('unusedNoOrder', 121);
    // This gateway has no order until a customer starts an attempt.
    Payment__c p = GVCheckoutService.payment(pid, buyer().ContactId);
    GVCheckoutService.Attempt a = GVCheckoutService.attempt(p);
    a.gatewayOrderId = null;
    update as system new Payment__c(
      Id = pid,
      Gateway_Response__c = JSON.serialize(a),
      Razorpay_Order_ID__c = null
    );
    refreshExpiry(pid);
    System.runAs(buyer()) {
      System.assertEquals(
        'Failed',
        GVRazorpayController.paymentStatus(pid).paymentStatus
      );
    }
    System.assertEquals(0, [SELECT COUNT() FROM Inventory_Movement__c]);
  }

  @IsTest
  static void expirySweepSkipsLegacyWithoutAttemptMetadata() {
    Id pid;
    System.runAs(buyer()) {
      pid = prepare().paymentId;
    }
    update as system new Payment__c(
      Id = pid,
      Gateway_Response__c = null,
      Razorpay_Order_ID__c = 'order_legacy'
    );
    Test.startTest();
    Id batchId = Database.executeBatch(new GVPaymentExpiryScheduler(), 1);
    Test.stopTest();
    System.assertEquals(
      0,
      [SELECT NumberOfErrors FROM AsyncApexJob WHERE Id = :batchId]
      .NumberOfErrors
    );
    System.assertEquals(
      'Pending',
      [SELECT Payment_Status__c FROM Payment__c WHERE Id = :pid]
      .Payment_Status__c
    );
    System.assertEquals(0, [SELECT COUNT() FROM Inventory_Movement__c]);
  }
}
