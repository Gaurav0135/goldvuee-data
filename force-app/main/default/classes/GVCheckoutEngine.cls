/** Trusted checkout boundary. Lock hierarchy: Contact, Cart, Order, Payment, Product. */
public without sharing class GVCheckoutEngine {
  public class CheckoutException extends Exception {
  }
  public static Id customer() {
    User u = [
      SELECT ContactId
      FROM User
      WHERE Id = :UserInfo.getUserId()
      WITH SYSTEM_MODE
    ];
    if (u.ContactId == null)
      throw new AuraHandledException(
        'Please sign in with your GoldVuee customer account.'
      );
    return u.ContactId;
  }
  public static void lockCustomer(Id cid) {
    List<Contact> locks = [
      SELECT Id
      FROM Contact
      WHERE Id = :cid
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    if (locks.isEmpty())
      throw new CheckoutException('Customer not found.');
  }
  public static Shopping_Cart__c activeCart(Id cid, Boolean createCart) {
    List<Shopping_Cart__c> rows = [
      SELECT Id, Customer__c, Cart_Status__c
      FROM Shopping_Cart__c
      WHERE Customer__c = :cid AND Cart_Status__c = 'Active'
      WITH SYSTEM_MODE
      LIMIT 2
      FOR UPDATE
    ];
    if (rows.size() > 1)
      throw new CheckoutException('Multiple active bags require support.');
    if (!rows.isEmpty())
      return rows[0];
    if (!createCart)
      throw new CheckoutException('Your bag is empty.');
    Shopping_Cart__c cart = new Shopping_Cart__c(
      Customer__c = cid,
      Cart_Status__c = 'Active'
    );
    insert as system cart;
    return cart;
  }
  // An unfinished payment must not make an active shopping bag read-only.
  // Callers still have to serialize changes using the customer/cart locks.
  public static void assertMutable(Id cartId) {
    if (cartId == null || [
      SELECT COUNT()
      FROM Shopping_Cart__c
      WHERE Id = :cartId AND Cart_Status__c = 'Active'
      WITH SYSTEM_MODE
    ] != 1)
      throw new AuraHandledException('Your shopping bag is no longer active.');
  }
  public static Decimal price(Jewellery_Product__c p) {
    if (p.Price__c == null || p.Price__c <= 0)
      throw new CheckoutException('Invalid product price.');
    return p.Discount_Price__c != null &&
      p.Discount_Price__c > 0 &&
      p.Discount_Price__c < p.Price__c
      ? p.Discount_Price__c
      : p.Price__c;
  }
  public static GVOnlineCheckoutController.CheckoutResult resume() {
    Id cid = customer();
    List<Payment__c> payments = [
      SELECT Id, Jewellery_Order__c, Reconciliation_State__c
      FROM Payment__c
      WHERE
        Jewellery_Order__r.Customer__c = :cid
        AND Jewellery_Order__r.Shopping_Cart__r.Cart_Status__c = 'Active'
        AND Jewellery_Order__r.Order_Status__c = 'pending'
        AND Payment_Status__c = 'Pending'
      WITH SYSTEM_MODE
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
    if (payments.isEmpty())
      return null;
    Id oid = payments[0].Jewellery_Order__c;
    Jewellery_Order__c o = [
      SELECT
        Id,
        Name,
        Grand_Total__c,
        Order_Status__c,
        Payment_Status__c,
        Shipping_Address__c,
        Shipping_City__c,
        Shipping_State__c,
        Shipping_Postal_Code__c,
        Shipping_Country__c
      FROM Jewellery_Order__c
      WHERE Id = :oid
      WITH SYSTEM_MODE
    ];
    GVOnlineCheckoutController.CheckoutResult r = prepared(o);
    r.shippingAddress = o.Shipping_Address__c;
    r.shippingCity = o.Shipping_City__c;
    r.shippingState = o.Shipping_State__c;
    r.shippingPostalCode = o.Shipping_Postal_Code__c;
    r.shippingCountry = o.Shipping_Country__c;
    r.reconciliationState = payments[0].Reconciliation_State__c;
    return r;
  }
  /** Compatibility entry point. Use the same fail-closed cancellation boundary as the new UI. */
  public static void cancelExpired(Id paymentId) {
    GVOnlineCheckoutController.RecoveryResult result = GVOnlineCheckoutController.cancelUnpaidCheckout(
      paymentId
    );
    if (result.state != 'Cancelled')
      throw new AuraHandledException(
        'This checkout cannot safely be cancelled as unpaid. Please verify your payment or contact GoldVuee support.'
      );
  }
  public static GVOnlineCheckoutController.CheckoutResult beginCheckout() {
    return prepare(null, null, null, null, 'India', true);
  }
  public static GVOnlineCheckoutController.CheckoutResult prepare(
    String address,
    String city,
    String state,
    String pin,
    String country
  ) {
    return prepare(address, city, state, pin, country, false);
  }
  public static void requireDelivery(Id orderId) {
    Jewellery_Order__c o = [
      SELECT
        Shipping_Address__c,
        Shipping_City__c,
        Shipping_State__c,
        Shipping_Postal_Code__c,
        Shipping_Country__c
      FROM Jewellery_Order__c
      WHERE Id = :orderId
      WITH SYSTEM_MODE
    ];
    validateDelivery(
      o.Shipping_Address__c,
      o.Shipping_City__c,
      o.Shipping_State__c,
      o.Shipping_Postal_Code__c,
      o.Shipping_Country__c
    );
  }
  private static void validateDelivery(
    String address,
    String city,
    String state,
    String pin,
    String country
  ) {
    List<String> values = new List<String>{
      address,
      city,
      state,
      pin,
      country
    };
    for (String value : values)
      if (String.isBlank(value))
        throw new CheckoutException('Complete all delivery information.');
    address = address.trim();
    city = city.trim();
    state = state.trim();
    pin = pin.trim();
    country = country.trim();
    if (
      address.length() > 32768 ||
      city.length() > 50 ||
      state.length() > 50 ||
      country.toLowerCase() != 'india' ||
      !Pattern.matches('^[1-9][0-9]{5}$', pin)
    )
      throw new CheckoutException(
        'Enter a valid Indian delivery address and PIN code.'
      );
  }
  private static GVOnlineCheckoutController.CheckoutResult prepare(
    String address,
    String city,
    String state,
    String pin,
    String country,
    Boolean draft
  ) {
    Id cid = customer();
    lockCustomer(cid);
    if (!draft) {
      validateDelivery(address, city, state, pin, country);
      address = address.trim();
      city = city.trim();
      state = state.trim();
      pin = pin.trim();
      country = country.trim();
    }
    Shopping_Cart__c cart = activeCart(cid, false);
    // Do not reconcile/renew inventory holds while preparing a new checkout.
    // Previous payment attempts remain persisted for gateway reconciliation.
    List<Cart_Item__c> items = [
      SELECT Jewellery_Product__c, Quantity__c
      FROM Cart_Item__c
      WHERE Shopping_Cart__c = :cart.Id
      WITH SYSTEM_MODE
    ];
    Map<Id, Decimal> qty = new Map<Id, Decimal>();
    for (Cart_Item__c item : items) {
      if (
        item.Jewellery_Product__c == null ||
        item.Quantity__c == null ||
        item.Quantity__c < 1 ||
        item.Quantity__c > 100 ||
        item.Quantity__c != item.Quantity__c.setScale(0)
      )
        throw new CheckoutException('Invalid bag quantity.');
      Id pid = item.Jewellery_Product__c;
      qty.put(
        pid,
        (qty.containsKey(pid) ? qty.get(pid) : 0) + item.Quantity__c
      );
    }
    if (qty.isEmpty() || qty.size() > 25)
      throw new CheckoutException('Choose between 1 and 25 products.');
    Map<Id, Jewellery_Product__c> products = new Map<Id, Jewellery_Product__c>(
      [
        SELECT Id, Name, Active__c, Price__c, Discount_Price__c, Stock_Quantity__c, Reserved_Quantity__c
        FROM Jewellery_Product__c
        WHERE Id IN :qty.keySet()
        WITH SYSTEM_MODE
        FOR UPDATE
      ]
    );
    if (products.size() != qty.size())
      throw new CheckoutException('Product unavailable.');
    Decimal total = 0;
    for (Id pid : qty.keySet()) {
      Jewellery_Product__c product = products.get(pid);
      if (product.Active__c != true)
        throw new CheckoutException('Product unavailable.');
      Decimal available = (product.Stock_Quantity__c == null ? 0 : product.Stock_Quantity__c) -
        (product.Reserved_Quantity__c == null ? 0 : product.Reserved_Quantity__c);
      if (available < qty.get(pid))
        throw new CheckoutException('Insufficient available stock for ' + product.Name);
      total += price(product) * qty.get(pid);
    }
    total = total.setScale(2);
    if (total < 1)
      throw new CheckoutException('Invalid payment total.');
    // Reuse only an unchanged, never-initialized draft.
    // An initialized payment is never modified or silently restarted.
    List<Jewellery_Order__c> drafts = [
      SELECT Id, Shipping_Address__c, Shipping_City__c,
        Shipping_State__c, Shipping_Postal_Code__c, Shipping_Country__c
      FROM Jewellery_Order__c
      WHERE Shopping_Cart__c = :cart.Id AND Order_Status__c = 'pending'
        AND Payment_Status__c = 'Pending'
      WITH SYSTEM_MODE
      LIMIT 20
      FOR UPDATE
    ];
    for (Jewellery_Order__c candidate : drafts) {
      List<Payment__c> candidates = [
        SELECT Id, Payment_Status__c, Razorpay_Order_ID__c,
          Transaction_ID__c, Razorpay_Verified_Payment_ID__c,
          Initialization_State__c, Initialization_Job__c
        FROM Payment__c
        WHERE Jewellery_Order__c = :candidate.Id
        WITH SYSTEM_MODE
        LIMIT 2
      ];
      if (candidates.size() != 1 ||
          candidates[0].Payment_Status__c != 'Pending' ||
          !String.isBlank(candidates[0].Razorpay_Order_ID__c) ||
          !String.isBlank(candidates[0].Transaction_ID__c) ||
          !String.isBlank(candidates[0].Razorpay_Verified_Payment_ID__c) ||
          !String.isBlank(candidates[0].Initialization_Job__c) ||
          (!String.isBlank(candidates[0].Initialization_State__c) &&
           candidates[0].Initialization_State__c != 'New'))
        continue;
      Map<Id, Decimal> snapshot = orderQuantities(candidate.Id);
      if (snapshot != qty)
        continue;
      if (draft) return prepared(candidate);
      Boolean emptyAddress = String.isBlank(candidate.Shipping_Address__c) &&
        String.isBlank(candidate.Shipping_City__c) &&
        String.isBlank(candidate.Shipping_State__c) &&
        String.isBlank(candidate.Shipping_Postal_Code__c);
      if (emptyAddress) {
        candidate.Shipping_Address__c = address;
        candidate.Shipping_City__c = city;
        candidate.Shipping_State__c = state;
        candidate.Shipping_Postal_Code__c = pin;
        candidate.Shipping_Country__c = country;
        update as system candidate;
        return prepared(candidate);
      }
      if (candidate.Shipping_Address__c == address &&
          candidate.Shipping_City__c == city &&
          candidate.Shipping_State__c == state &&
          candidate.Shipping_Postal_Code__c == pin &&
          candidate.Shipping_Country__c == country)
        return prepared(candidate);
    }
    Jewellery_Order__c orderRecord = new Jewellery_Order__c(
      Customer__c = cid,
      Shopping_Cart__c = cart.Id,
      Order_Date__c = System.now(),
      Order_Status__c = 'pending',
      Payment_Status__c = 'Pending',
      Subtotal__c = total,
      Discount_Amount__c = 0,
      Tax_Amount__c = 0,
      Shipping_Charges__c = 0,
      Shipping_Address__c = address,
      Shipping_City__c = city,
      Shipping_State__c = state,
      Shipping_Postal_Code__c = pin,
      Shipping_Country__c = 'India'
    );
    insert as system orderRecord;
    List<Jewellery_Order_Item__c> lines = new List<Jewellery_Order_Item__c>();
    for (Id pid : qty.keySet())
      lines.add(
        new Jewellery_Order_Item__c(
          Jewellery_Order__c = orderRecord.Id,
          Jewellery_Product__c = pid,
          Quantity__c = qty.get(pid),
          Unit_Price__c = price(products.get(pid)),
          Discount_Amount__c = 0
        )
      );
    insert as system lines;
    // New checkout: do not reserve stock. Stock is deducted after verified capture.
    insert as system new Payment__c(
      Jewellery_Order__c = orderRecord.Id,
      Payment_Amount__c = total,
      Payment_Status__c = 'Pending',
      Initialization_State__c = 'New'
    );
    orderRecord = [
      SELECT Id, Name, Grand_Total__c, Order_Status__c, Payment_Status__c
      FROM Jewellery_Order__c
      WHERE Id = :orderRecord.Id
      WITH SYSTEM_MODE
    ];
    return prepared(orderRecord);
  }
  private static GVOnlineCheckoutController.CheckoutResult prepared(
    Jewellery_Order__c o
  ) {
    o = [
      SELECT
        Id,
        Name,
        Shopping_Cart__c,
        Grand_Total__c,
        Order_Status__c,
        Payment_Status__c,
        Shipping_Address__c,
        Shipping_City__c,
        Shipping_State__c,
        Shipping_Postal_Code__c,
        Shipping_Country__c
      FROM Jewellery_Order__c
      WHERE Id = :o.Id
      WITH SYSTEM_MODE
    ];
    List<Payment__c> payments = [
      SELECT Id
      FROM Payment__c
      WHERE Jewellery_Order__c = :o.Id
      WITH SYSTEM_MODE
      LIMIT 2
    ];
    if (payments.size() != 1)
      throw new CheckoutException('Payment requires reconciliation.');
    GVOnlineCheckoutController.CheckoutResult r = new GVOnlineCheckoutController.CheckoutResult();
    r.orderId = o.Id;
    r.cartId = o.Shopping_Cart__c;
    r.shippingAddress = o.Shipping_Address__c;
    r.shippingCity = o.Shipping_City__c;
    r.shippingState = o.Shipping_State__c;
    r.shippingPostalCode = o.Shipping_Postal_Code__c;
    r.shippingCountry = o.Shipping_Country__c;
    r.paymentId = payments[0].Id;
    r.orderNumber = o.Name;
    r.grandTotal = o.Grand_Total__c;
    r.items = [
      SELECT
        Id,
        Jewellery_Product__r.Name,
        Quantity__c,
        Unit_Price__c,
        Line_Total__c
      FROM Jewellery_Order_Item__c
      WHERE Jewellery_Order__c = :o.Id
      WITH SYSTEM_MODE
    ];
    r.orderStatus = o.Order_Status__c;
    r.paymentStatus = o.Payment_Status__c;
    r.message = 'Checkout ready.';
    return r;
  }
  public static Payment__c ownedPayment(Id pid) {
    Id cid = customer();
    List<Payment__c> rows = [
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
        Jewellery_Order__r.Customer__c,
        Jewellery_Order__r.Shopping_Cart__c,
        Jewellery_Order__r.Name,
        Jewellery_Order__r.Grand_Total__c,
        Jewellery_Order__r.Order_Status__c,
        Jewellery_Order__r.Payment_Status__c
      FROM Payment__c
      WHERE Id = :pid AND Jewellery_Order__r.Customer__c = :cid
      WITH SYSTEM_MODE
    ];
    if (rows.isEmpty())
      throw new AuraHandledException('Payment not found or access denied.');
    return rows[0];
  }
  public static Set<Id> reservationIds(Id oid, Boolean requireLive) {
    Set<Id> result = new Set<Id>();
    Map<Id, Decimal> held = new Map<Id, Decimal>();
    for (Stock_Reservation__c r : [
      SELECT Id, Jewellery_Product__c, Reserved_Quantity__c, Expires_At__c
      FROM Stock_Reservation__c
      WHERE Jewellery_Order__c = :oid AND Reservation_Status__c = 'Active'
      WITH SYSTEM_MODE
    ]) {
      if (
        requireLive &&
        (r.Expires_At__c == null ||
        r.Expires_At__c <= System.now())
      )
        throw new CheckoutException(
          'Reservation expired. Check payment status before restarting.'
        );
      result.add(r.Id);
      Id pid = r.Jewellery_Product__c;
      held.put(
        pid,
        (held.containsKey(pid) ? held.get(pid) : 0) + r.Reserved_Quantity__c
      );
    }
    Map<Id, Decimal> ordered = new Map<Id, Decimal>();
    for (Jewellery_Order_Item__c i : [
      SELECT Jewellery_Product__c, Quantity__c
      FROM Jewellery_Order_Item__c
      WHERE Jewellery_Order__c = :oid
      WITH SYSTEM_MODE
    ]) {
      Id pid = i.Jewellery_Product__c;
      ordered.put(
        pid,
        (ordered.containsKey(pid) ? ordered.get(pid) : 0) + i.Quantity__c
      );
    }
    if (result.isEmpty() || held != ordered)
      throw new CheckoutException('Order stock requires reconciliation.');
    return result;
  }
  /** Only called with authenticated gateway data, never an untrusted browser payload. */
  public static GVPaymentVerificationService.Result finalizeCaptured(
    Id pid,
    GVRazorpayService.RazorpayPaymentDetails gateway
  ) {
    Payment__c pre = [
      SELECT
        Jewellery_Order__c,
        Jewellery_Order__r.Customer__c,
        Jewellery_Order__r.Shopping_Cart__c
      FROM Payment__c
      WHERE Id = :pid
      WITH SYSTEM_MODE
    ];
    lockCustomer(pre.Jewellery_Order__r.Customer__c);
    List<Shopping_Cart__c> carts = [
      SELECT Id, Cart_Status__c
      FROM Shopping_Cart__c
      WHERE Id = :pre.Jewellery_Order__r.Shopping_Cart__c
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    Jewellery_Order__c o = [
      SELECT
        Id,
        Name,
        Customer__c,
        Grand_Total__c,
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
        Payment_Amount__c,
        Razorpay_Order_ID__c,
        Transaction_ID__c
      FROM Payment__c
      WHERE Id = :pid
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    if (
      gateway == null ||
      gateway.orderId != payment.Razorpay_Order_ID__c ||
      gateway.currencyCode != 'INR' ||
      gateway.paymentStatus != 'captured' ||
      gateway.captured != true ||
      payment.Payment_Amount__c != o.Grand_Total__c ||
      gateway.amountPaise != (payment.Payment_Amount__c * 100).longValue()
    )
      throw new CheckoutException('Gateway payment does not match the order.');
    if (
      payment.Payment_Status__c == 'Success' &&
      payment.Transaction_ID__c == gateway.paymentId
    )
      return confirmed(o, 'Payment already confirmed.');
    if (payment.Payment_Status__c != 'Pending')
      throw new CheckoutException('Payment is not pending.');
    if (
      [
        SELECT COUNT()
        FROM Payment__c
        WHERE Transaction_ID__c = :gateway.paymentId AND Id != :pid
        WITH SYSTEM_MODE
      ] > 0
    )
      throw new CheckoutException('Transaction already assigned.');
    if (
      o.Order_Status__c != 'pending' ||
      o.Payment_Status__c != 'Pending' ||
      carts.isEmpty()
    )
      throw new CheckoutException('Order state requires reconciliation.');

    // Legacy orders created before this redesign may have reservation records.
    // Never mix the old and new deduction paths for the same order.
    List<Stock_Reservation__c> legacyReservations = [
      SELECT Id, Reservation_Status__c
      FROM Stock_Reservation__c
      WHERE Jewellery_Order__c = :o.Id
      WITH SYSTEM_MODE
    ];
    try {
      if (legacyReservations.isEmpty()) {
        // New reservation-free orders: deduct stock only after verified capture.
        // Caller must commit this and payment confirmation in one transaction.
        GVInventoryService.deductOnPayment(o.Id);
      } else {
        // Legacy path: only commit an intact live hold. Expired or partially
        // released reservations must be resolved through operator review.
        Set<Id> ids = reservationIds(o.Id, true);
        if (ids.size() != legacyReservations.size())
          throw new CheckoutException('Legacy reservation requires review.');
        GVInventoryService.change(ids, true);
      }
    } catch (GVInventoryService.InventoryException e) {
      payment.Reconciliation_State__c = 'Captured - stock review required';
      payment.Transaction_ID__c = gateway.paymentId;
      payment.Last_Checked_At__c = System.now();
      update as system payment;
      GVPaymentVerificationService.Result r = new GVPaymentVerificationService.Result();
      r.success = false;
      r.orderId = o.Id;
      r.orderNumber = o.Name;
      r.paymentStatus = 'Pending';
      r.orderStatus = o.Order_Status__c;
      r.message = 'Payment received. Inventory review is required; do not pay again.';
      return r;
    } catch (CheckoutException e) {
      payment.Reconciliation_State__c = 'Captured - stock review required';
      payment.Transaction_ID__c = gateway.paymentId;
      payment.Last_Checked_At__c = System.now();
      update as system payment;
      GVPaymentVerificationService.Result r = new GVPaymentVerificationService.Result();
      r.success = false;
      r.orderId = o.Id;
      r.orderNumber = o.Name;
      r.paymentStatus = 'Pending';
      r.orderStatus = o.Order_Status__c;
      r.message = 'Payment received. Legacy inventory review is required; do not pay again.';
      return r;
    }
    payment.Payment_Status__c = 'Success';
    payment.Transaction_ID__c = gateway.paymentId;
    payment.Payment_Date__c = System.now();
    payment.Payment_Method__c = method(gateway.paymentMethod);
    payment.Reconciliation_State__c = 'Confirmed';
    payment.Last_Checked_At__c = System.now();
    update as system payment;
    o.Payment_Status__c = 'Paid';
    o.Order_Status__c = 'Confirmed';
    update as system o;
    // A late capture must not convert a bag the customer has edited
    // or one already used for a newer checkout.
    Jewellery_Order__c datedOrder = [
      SELECT Id, CreatedDate
      FROM Jewellery_Order__c WHERE Id = :o.Id WITH SYSTEM_MODE
    ];
    Id currentCartId = carts[0].Id;
    Integer laterOrders = [
      SELECT COUNT() FROM Jewellery_Order__c
      WHERE Shopping_Cart__c = :currentCartId
        AND CreatedDate >= :datedOrder.CreatedDate
        AND Id != :o.Id
      WITH SYSTEM_MODE
    ];
    if (carts[0].Cart_Status__c == 'Active' && laterOrders == 0 &&
        cartMatchesOrder(carts[0].Id, o.Id)) {
      carts[0].Cart_Status__c = 'Converted';
      update as system carts;
    }
    return confirmed(o, 'Payment confirmed.');
  }
  /** Worker-only recovery after fresh unpaid attempts and retryable order verification. */
  public static void renewUnpaidHold(
    Id paymentId,
    String gatewayOrderId,
    Decimal amount
  ) {
    Payment__c pre = [
      SELECT
        Jewellery_Order__c,
        Jewellery_Order__r.Customer__c,
        Jewellery_Order__r.Shopping_Cart__c
      FROM Payment__c
      WHERE Id = :paymentId
      WITH SYSTEM_MODE
    ];
    lockCustomer(pre.Jewellery_Order__r.Customer__c);
    Shopping_Cart__c cart = [
      SELECT Id, Customer__c, Cart_Status__c
      FROM Shopping_Cart__c
      WHERE Id = :pre.Jewellery_Order__r.Shopping_Cart__c
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    Jewellery_Order__c o = [
      SELECT Id, Customer__c, Order_Status__c, Payment_Status__c, Grand_Total__c
      FROM Jewellery_Order__c
      WHERE Id = :pre.Jewellery_Order__c
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    Payment__c p = [
      SELECT
        Payment_Status__c,
        Payment_Amount__c,
        Razorpay_Order_ID__c,
        Transaction_ID__c,
        Reconciliation_State__c
      FROM Payment__c
      WHERE Id = :paymentId
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    if (
      cart.Cart_Status__c != 'Active' ||
      cart.Customer__c != o.Customer__c ||
      o.Customer__c != pre.Jewellery_Order__r.Customer__c ||
      o.Order_Status__c != 'pending' ||
      o.Payment_Status__c != 'Pending' ||
      p.Payment_Status__c != 'Pending' ||
      p.Razorpay_Order_ID__c != gatewayOrderId ||
      p.Payment_Amount__c != amount ||
      o.Grand_Total__c != amount ||
      !String.isBlank(p.Transaction_ID__c) ||
      (p.Reconciliation_State__c != null &&
      p.Reconciliation_State__c.toLowerCase().contains('captured')) ||
      [
        SELECT COUNT()
        FROM Jewellery_Order__c
        WHERE Shopping_Cart__c = :cart.Id AND Order_Status__c != 'Cancelled'
        WITH SYSTEM_MODE
      ] != 1
    )
      throw new CheckoutException('This payment requires review before retry.');
    // A second serialized recovery reuses a live hold without extending its lifetime.
    try {
      reservationIds(o.Id, true);
      return;
    } catch (CheckoutException e) {
    }
    Set<Id> expired = new Set<Id>();
    for (Stock_Reservation__c hold : [
      SELECT Id, Reservation_Status__c, Expires_At__c
      FROM Stock_Reservation__c
      WHERE Jewellery_Order__c = :o.Id
      WITH SYSTEM_MODE
    ]) {
      if (
        hold.Reservation_Status__c == 'Committed' ||
        (hold.Reservation_Status__c == 'Active' &&
        (hold.Expires_At__c == null ||
        hold.Expires_At__c > System.now()))
      )
        throw new CheckoutException('Order stock requires review.');
      if (hold.Reservation_Status__c == 'Active')
        expired.add(hold.Id);
    }
    Map<Id, Decimal> quantities = new Map<Id, Decimal>();
    for (Jewellery_Order_Item__c line : [
      SELECT Jewellery_Product__c, Quantity__c
      FROM Jewellery_Order_Item__c
      WHERE Jewellery_Order__c = :o.Id
      WITH SYSTEM_MODE
    ]) {
      Id pid = line.Jewellery_Product__c;
      quantities.put(
        pid,
        (quantities.containsKey(pid) ? quantities.get(pid) : 0) +
        line.Quantity__c
      );
    }
    Savepoint sp = Database.setSavepoint();
    try {
      if (!expired.isEmpty())
        GVInventoryService.change(expired, false);
      GVInventoryService.reserve(quantities, o.Id);
      reservationIds(o.Id, true);
    } catch (Exception e) {
      Database.rollback(sp);
      throw e;
    }
  }
  /** Operator-approved late capture recovery. Caller has fetched captured gateway evidence. */
  public static void renewCapturedHold(Id paymentId) {
    Payment__c pre = [
      SELECT
        Jewellery_Order__c,
        Jewellery_Order__r.Customer__c,
        Jewellery_Order__r.Shopping_Cart__c
      FROM Payment__c
      WHERE Id = :paymentId
      WITH SYSTEM_MODE
    ];
    lockCustomer(pre.Jewellery_Order__r.Customer__c);
    List<Shopping_Cart__c> carts = [
      SELECT Id, Cart_Status__c
      FROM Shopping_Cart__c
      WHERE Id = :pre.Jewellery_Order__r.Shopping_Cart__c
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    Jewellery_Order__c o = [
      SELECT Id, Order_Status__c
      FROM Jewellery_Order__c
      WHERE Id = :pre.Jewellery_Order__c
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    Payment__c p = [
      SELECT Id, Payment_Status__c
      FROM Payment__c
      WHERE Id = :paymentId
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    if (
      p.Payment_Status__c != 'Pending' ||
      o.Order_Status__c != 'pending' ||
      carts.isEmpty() ||
      carts[0].Cart_Status__c != 'Active'
    )
      throw new CheckoutException(
        'Subsequent checkout or closed order requires manual refund review.'
      );
    Set<Id> oldIds = new Set<Id>();
    for (Stock_Reservation__c hold : [
      SELECT Id
      FROM Stock_Reservation__c
      WHERE Jewellery_Order__c = :o.Id AND Reservation_Status__c = 'Active'
      WITH SYSTEM_MODE
    ])
      oldIds.add(hold.Id);
    if (!oldIds.isEmpty())
      GVInventoryService.change(oldIds, false);
    Map<Id, Decimal> quantities = new Map<Id, Decimal>();
    for (Jewellery_Order_Item__c line : [
      SELECT Jewellery_Product__c, Quantity__c
      FROM Jewellery_Order_Item__c
      WHERE Jewellery_Order__c = :o.Id
      WITH SYSTEM_MODE
    ]) {
      Id pid = line.Jewellery_Product__c;
      quantities.put(
        pid,
        (quantities.containsKey(pid) ? quantities.get(pid) : 0) +
        line.Quantity__c
      );
    }
    GVInventoryService.reserve(quantities, o.Id);
  }
  // Immutable order-line snapshot helpers; never update a cart from a late capture.
  private static Map<Id, Decimal> orderQuantities(Id orderId) {
    Map<Id, Decimal> result = new Map<Id, Decimal>();
    for (Jewellery_Order_Item__c row : [
      SELECT Jewellery_Product__c, Quantity__c
      FROM Jewellery_Order_Item__c
      WHERE Jewellery_Order__c = :orderId WITH SYSTEM_MODE
    ]) {
      Id pid = row.Jewellery_Product__c;
      result.put(pid, (result.containsKey(pid) ? result.get(pid) : 0) + row.Quantity__c);
    }
    return result;
  }

  private static Boolean cartMatchesOrder(Id cartId, Id orderId) {
    Map<Id, Decimal> quantities = new Map<Id, Decimal>();
    for (Cart_Item__c row : [
      SELECT Jewellery_Product__c, Quantity__c
      FROM Cart_Item__c WHERE Shopping_Cart__c = :cartId WITH SYSTEM_MODE
    ]) {
      Id pid = row.Jewellery_Product__c;
      quantities.put(pid,
        (quantities.containsKey(pid) ? quantities.get(pid) : 0) + row.Quantity__c);
    }
    return quantities == orderQuantities(orderId);
  }

  public static GVPaymentVerificationService.Result confirmed(
    Jewellery_Order__c o,
    String message
  ) {
    GVPaymentVerificationService.Result r = new GVPaymentVerificationService.Result();
    r.success = true;
    r.orderId = o.Id;
    r.orderNumber = o.Name;
    r.paymentStatus = o.Payment_Status__c;
    r.orderStatus = o.Order_Status__c;
    r.message = message;
    return r;
  }
  private static String method(String value) {
    Map<String, String> methods = new Map<String, String>{
      'upi' => 'UPI',
      'card' => 'Card',
      'netbanking' => 'Net Banking',
      'wallet' => 'Wallet'
    };
    if (!methods.containsKey(value))
      throw new CheckoutException(
        'Unsupported payment method requires review.'
      );
    return methods.get(value);
  }
}
