/** Internal trust boundary. Browser entry points authorize Contact ownership before system DML.
 * Existing objects only. Gateway_Response__c holds versioned attempt state, never credentials.
 */
public without sharing class GVCheckoutService {
  public class CheckoutException extends Exception {
  }
  public class Attempt {
    public Integer version = 1;
    public String state = 'New';
    public String linkId;
    public String url;
    public String gatewayOrderId;
    public String fulfillment;
    public String lastFailurePaymentId;
    public String lastFailureState;
  }
  public static Id customer() {
    User u = [
      SELECT ContactId, UserType
      FROM User
      WHERE Id = :UserInfo.getUserId()
      WITH SYSTEM_MODE
    ];
    if (u.UserType == 'Guest' || u.ContactId == null)
      throw new AuraHandledException(
        'Please sign in with your GoldVuee customer account.'
      );
    return u.ContactId;
  }
  public static void lockCustomer(Id cid) {
    Contact c = [
      SELECT Id
      FROM Contact
      WHERE Id = :cid
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
  }
  public static Attempt attempt(Payment__c p) {
    if (String.isBlank(p.Gateway_Response__c)) {
      Attempt a = new Attempt();
      // Never treat a legacy gateway order as an uninitialized hosted payment.
      if (
        !String.isBlank(p.Razorpay_Order_ID__c) ||
        !String.isBlank(p.Transaction_ID__c)
      )
        a.state = 'Legacy review';
      return a;
    }
    try {
      Attempt a = (Attempt) JSON.deserialize(
        p.Gateway_Response__c,
        Attempt.class
      );
      if (a == null || a.version != 1 || String.isBlank(a.state))
        throw new CheckoutException('Invalid attempt');
      return a;
    } catch (Exception e) {
      Attempt a = new Attempt();
      a.state = 'Legacy review';
      return a;
    }
  }
  public static Payment__c payment(Id pid, Id cid) {
    List<Payment__c> rows = [
      SELECT
        Id,
        Jewellery_Order__c,
        Payment_Amount__c,
        Payment_Status__c,
        Transaction_ID__c,
        Razorpay_Order_ID__c,
        Gateway_Response__c,
        Failure_Reason__c,
        Jewellery_Order__r.Customer__c,
        Jewellery_Order__r.Shopping_Cart__c,
        Jewellery_Order__r.Grand_Total__c,
        Jewellery_Order__r.Payment_Status__c,
        Jewellery_Order__r.Order_Status__c
      FROM Payment__c
      WHERE Id = :pid AND Jewellery_Order__r.Customer__c = :cid
      WITH SYSTEM_MODE
    ];
    if (rows.isEmpty())
      throw new AuraHandledException('Payment not found or access denied.');
    return rows[0];
  }
  public static Decimal price(Jewellery_Product__c p) {
    if (p.Price__c == null || p.Price__c <= 0)
      throw new CheckoutException('Product price unavailable.');
    return p.Discount_Price__c != null &&
      p.Discount_Price__c > 0 &&
      p.Discount_Price__c < p.Price__c
      ? p.Discount_Price__c
      : p.Price__c;
  }
  public static void quantity(Decimal q) {
    if (q == null || q < 1 || q > 100 || q != q.setScale(0))
      throw new AuraHandledException('Quantity must be between 1 and 100.');
  }
  public static void mutableCart(Id cartId) {
    List<Shopping_Cart__c> carts = [
      SELECT Id
      FROM Shopping_Cart__c
      WHERE Id = :cartId AND Cart_Status__c = 'Active'
      WITH SYSTEM_MODE
    ];
    if (carts.isEmpty())
      throw new AuraHandledException('Your shopping bag is no longer active.');
  }
  /** Fork only the editable bag. Original order, payment and cart lines remain unchanged. */
  public static Id editableCart(Id cartId, Id cid) {
    mutableCart(cartId);
    Boolean payable = false;
    for (Payment__c p : [
      SELECT Gateway_Response__c, Razorpay_Order_ID__c, Transaction_ID__c
      FROM Payment__c
      WHERE
        Jewellery_Order__r.Shopping_Cart__c = :cartId
        AND Payment_Status__c = 'Pending'
      WITH SYSTEM_MODE
    ]) {
      if (attempt(p).state != 'New')
        payable = true;
    }
    return payable ? forkCart(cartId, cid) : cartId;
  }
  public static Id forkCart(Id cartId, Id cid) {
    Shopping_Cart__c oldCart = [
      SELECT Id, Customer__c, Cart_Status__c
      FROM Shopping_Cart__c
      WHERE Id = :cartId AND Customer__c = :cid AND Cart_Status__c = 'Active'
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    oldCart.Cart_Status__c = 'Abandoned';
    update as system oldCart;
    Shopping_Cart__c current = new Shopping_Cart__c(
      Customer__c = cid,
      Cart_Status__c = 'Active'
    );
    insert as system current;
    List<Cart_Item__c> copies = new List<Cart_Item__c>();
    for (Cart_Item__c line : [
      SELECT Jewellery_Product__c, Quantity__c, Unit_Price__c
      FROM Cart_Item__c
      WHERE Shopping_Cart__c = :cartId
      WITH SYSTEM_MODE
    ]) {
      copies.add(
        new Cart_Item__c(
          Shopping_Cart__c = current.Id,
          Jewellery_Product__c = line.Jewellery_Product__c,
          Quantity__c = line.Quantity__c,
          Unit_Price__c = line.Unit_Price__c
        )
      );
    }
    insert as system copies;
    return current.Id;
  }

  public static void stock(Id oid) {
    Map<Id, Decimal> qty = quantities(oid);
    Map<Id, Jewellery_Product__c> products = new Map<Id, Jewellery_Product__c>(
      [
        SELECT Id, Name, Active__c, Available_Quantity__c
        FROM Jewellery_Product__c
        WHERE Id IN :qty.keySet()
        WITH SYSTEM_MODE
        FOR UPDATE
      ]
    );
    if (qty.isEmpty() || qty.size() > 25 || products.size() != qty.size())
      throw new CheckoutException('Invalid order items.');
    for (Id pid : qty.keySet()) {
      quantity(qty.get(pid));
      if (
        !products.get(pid).Active__c ||
        products.get(pid).Available_Quantity__c < qty.get(pid)
      )
        throw new CheckoutException(
          'Insufficient stock for ' + products.get(pid).Name
        );
    }
  }
  public static Map<Id, Decimal> quantities(Id oid) {
    Map<Id, Decimal> qty = new Map<Id, Decimal>();
    for (Jewellery_Order_Item__c i : [
      SELECT Jewellery_Product__c, Quantity__c
      FROM Jewellery_Order_Item__c
      WHERE Jewellery_Order__c = :oid
      WITH SYSTEM_MODE
    ]) {
      quantity(i.Quantity__c);
      qty.put(
        i.Jewellery_Product__c,
        (qty.containsKey(i.Jewellery_Product__c)
          ? qty.get(i.Jewellery_Product__c)
          : 0) + i.Quantity__c
      );
    }
    return qty;
  }
  /** Only accepts evidence fetched with Named Credential or authenticated raw webhook HMAC. */
  public static void captured(
    Id pid,
    String linkId,
    Map<String, Object> evidence
  ) {
    Savepoint checkpoint = Database.setSavepoint();
    try {
      finalizeCapture(pid, linkId, evidence);
    } catch (Exception e) {
      Database.rollback(checkpoint);
      throw e;
    }
  }
  private static void finalizeCapture(
    Id pid,
    String linkId,
    Map<String, Object> evidence
  ) {
    Payment__c pre = [
      SELECT Jewellery_Order__r.Customer__c
      FROM Payment__c
      WHERE Id = :pid
      WITH SYSTEM_MODE
    ];
    lockCustomer(pre.Jewellery_Order__r.Customer__c);
    Payment__c p = [
      SELECT
        Id,
        Jewellery_Order__c,
        Payment_Amount__c,
        Payment_Status__c,
        Transaction_ID__c,
        Razorpay_Order_ID__c,
        Gateway_Response__c
      FROM Payment__c
      WHERE Id = :pid
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    Attempt a = attempt(p);
    String transactionId = (String) evidence.get('id');
    if (
      a.linkId != linkId ||
      String.isBlank(transactionId) ||
      !transactionId.startsWith('pay_') ||
      evidence.get('status') != 'captured' ||
      evidence.get('captured') != true ||
      evidence.get('currency') != 'INR' ||
      numberValue(evidence.get('amount')) != p.Payment_Amount__c * 100 ||
      String.isBlank(a.gatewayOrderId) ||
      evidence.get('order_id') != a.gatewayOrderId
    )
      throw new CheckoutException(
        'Gateway payment does not match this checkout.'
      );
    if (p.Payment_Status__c == 'Success') {
      if (p.Transaction_ID__c != transactionId)
        throw new CheckoutException(
          'Additional payment requires admin review.'
        );
      return;
    }
    Jewellery_Order__c o = [
      SELECT Id, Shopping_Cart__c, Grand_Total__c, Payment_Status__c
      FROM Jewellery_Order__c
      WHERE Id = :p.Jewellery_Order__c
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    if (
      p.Payment_Amount__c != o.Grand_Total__c ||
      o.Payment_Status__c == 'Paid'
    )
      throw new CheckoutException('Order requires payment review.');
    // Record capture even if fulfillment cannot proceed. No inventory DML until every product passes.
    Map<Id, Decimal> qty = quantities(o.Id);
    Map<Id, Jewellery_Product__c> products = new Map<Id, Jewellery_Product__c>(
      [
        SELECT
          Id,
          Active__c,
          Stock_Quantity__c,
          Reserved_Quantity__c,
          Available_Quantity__c
        FROM Jewellery_Product__c
        WHERE Id IN :qty.keySet()
        WITH SYSTEM_MODE
        FOR UPDATE
      ]
    );
    Boolean available =
      !qty.isEmpty() &&
      products.size() == qty.size() &&
      qty.size() <= 25;
    for (Id productId : qty.keySet()) {
      Jewellery_Product__c product = products.get(productId);
      if (
        product == null ||
        !product.Active__c ||
        product.Available_Quantity__c < qty.get(productId)
      )
        available = false;
    }
    if (
      [
        SELECT COUNT()
        FROM Inventory_Movement__c
        WHERE Jewellery_Order__c = :o.Id AND Movement_Type__c = 'Sale'
        WITH SYSTEM_MODE
      ] > 0
    )
      available = false;
    a.state = 'Paid';
    a.fulfillment = available ? 'Confirmed' : 'Stock review required';
    List<Inventory_Movement__c> moves = new List<Inventory_Movement__c>();
    if (available) {
      for (Id productId : qty.keySet()) {
        Jewellery_Product__c product = products.get(productId);
        Decimal beforeStock = product.Stock_Quantity__c;
        product.Stock_Quantity__c -= qty.get(productId);
        moves.add(
          new Inventory_Movement__c(
            Jewellery_Order__c = o.Id,
            Jewellery_Product__c = productId,
            Movement_Type__c = 'Sale',
            Quantity__c = qty.get(productId),
            Stock_Before__c = beforeStock,
            Stock_After__c = product.Stock_Quantity__c,
            Movement_Date__c = System.now(),
            Reason__c = 'Verified hosted Razorpay payment'
          )
        );
      }
      update as system products.values();
      insert as system moves;
    }
    p.Payment_Status__c = 'Success';
    p.Transaction_ID__c = transactionId;
    p.Payment_Date__c = System.now();
    Map<String, String> methods = new Map<String, String>{
      'upi' => 'UPI',
      'card' => 'Card',
      'netbanking' => 'Net Banking',
      'wallet' => 'Wallet'
    };
    p.Payment_Method__c = methods.get((String) evidence.get('method'));
    p.Gateway_Response__c = JSON.serialize(a);
    p.Failure_Reason__c = available
      ? null
      : 'PAYMENT CAPTURED: stock unavailable. Admin fulfillment/refund review required. Do not pay again.';
    update as system p;
    o.Payment_Status__c = 'Paid';
    o.Order_Status__c = available ? 'Confirmed' : 'pending';
    update as system o;
    // A paid exception is not fulfillment. Remove the frozen bag from further charging in either case.
    if (o.Shopping_Cart__c != null)
      update as system new Shopping_Cart__c(
        Id = o.Shopping_Cart__c,
        Cart_Status__c = 'Converted'
      );
  }
  public static Decimal numberValue(Object value) {
    return value == null ? null : Decimal.valueOf(String.valueOf(value));
  }
}
