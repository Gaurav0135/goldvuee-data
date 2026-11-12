/** Trusted checkout boundary. Lock hierarchy: Contact, Cart, Order, Payment, Product, Reservation. */
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
  public static void assertMutable(Id cartId) {
    if (
      [
        SELECT COUNT()
        FROM Jewellery_Order__c
        WHERE Shopping_Cart__c = :cartId AND Order_Status__c != 'Cancelled'
        WITH SYSTEM_MODE
      ] > 0
    )
      throw new AuraHandledException(
        'This bag has a checkout in progress. Finish payment or cancel the unpaid checkout first.'
      );
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
  /** Restart only after authoritative reconciliation released an expired, unpaid hold. */
  public static void cancelExpired(Id paymentId) {
    Payment__c pre = ownedPayment(paymentId);
    lockCustomer(pre.Jewellery_Order__r.Customer__c);
    Jewellery_Order__c o = [
      SELECT Id, Order_Status__c
      FROM Jewellery_Order__c
      WHERE Id = :pre.Jewellery_Order__c
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    Payment__c p = [
      SELECT
        Id,
        Payment_Status__c,
        Transaction_ID__c,
        Reconciliation_State__c,
        Last_Checked_At__c
      FROM Payment__c
      WHERE Id = :paymentId
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    if (
      p.Payment_Status__c != 'Pending' ||
      !String.isBlank(p.Transaction_ID__c) ||
      p.Reconciliation_State__c != 'Expired - stock released' ||
      p.Last_Checked_At__c == null ||
      p.Last_Checked_At__c < System.now().addMinutes(-5)
    )
      throw new AuraHandledException(
        'Check payment status first. Only reconciled expired unpaid checkouts can restart.'
      );
    o.Order_Status__c = 'Cancelled';
    update as system o;
    p.Reconciliation_State__c = 'Cancelled - monitor late capture';
    update as system p;
  }
  public static GVOnlineCheckoutController.CheckoutResult prepare(
    String address,
    String city,
    String state,
    String pin,
    String country
  ) {
    Id cid = customer();
    lockCustomer(cid);
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
    Shopping_Cart__c cart = activeCart(cid, false);
    GVAbandonedCheckoutService.recoverExpiredCheckout(cart.Id, cid);
    List<Jewellery_Order__c> existing = [
      SELECT
        Id,
        Name,
        Grand_Total__c,
        Order_Status__c,
        Payment_Status__c,
        Shipping_Address__c,
        Shipping_City__c,
        Shipping_State__c,
        Shipping_Postal_Code__c
      FROM Jewellery_Order__c
      WHERE Shopping_Cart__c = :cart.Id AND Order_Status__c != 'Cancelled'
      WITH SYSTEM_MODE
      LIMIT 2
      FOR UPDATE
    ];
    if (existing.size() > 1)
      throw new CheckoutException('Multiple checkouts require support.');
    if (!existing.isEmpty()) {
      Jewellery_Order__c o = existing[0];
      if (o.Payment_Status__c != 'Pending' || o.Order_Status__c != 'pending')
        throw new CheckoutException(
          'This bag already has an order. Check My Orders.'
        );
      if (
        o.Shipping_Address__c != address ||
        o.Shipping_City__c != city ||
        o.Shipping_State__c != state ||
        o.Shipping_Postal_Code__c != pin
      )
        throw new CheckoutException(
          'Delivery details are frozen for this checkout. Resume or cancel it first.'
        );
      return prepared(o);
    }
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
        SELECT Id, Name, Active__c, Price__c, Discount_Price__c
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
      if (products.get(pid).Active__c != true)
        throw new CheckoutException('Product unavailable.');
      total += price(products.get(pid)) * qty.get(pid);
    }
    total = total.setScale(2);
    if (total < 1)
      throw new CheckoutException('Invalid payment total.');
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
    GVInventoryService.reserve(qty, orderRecord.Id);
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
    r.paymentId = payments[0].Id;
    r.orderNumber = o.Name;
    r.grandTotal = o.Grand_Total__c;
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
    Set<Id> ids;
    try {
      ids = reservationIds(o.Id, true);
    } catch (Exception e) {
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
    }
    if (
      o.Order_Status__c != 'pending' ||
      o.Payment_Status__c != 'Pending' ||
      carts.isEmpty() ||
      carts[0].Cart_Status__c != 'Active'
    )
      throw new CheckoutException('Order state requires reconciliation.');
    GVInventoryService.change(ids, true);
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
    carts[0].Cart_Status__c = 'Converted';
    update as system carts;
    return confirmed(o, 'Payment confirmed.');
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
