/** Internal owner-checked data and atomic fulfillment boundary. No browser entry points. */
public without sharing class GVCheckoutService {
  public class CheckoutException extends Exception {
  }
  public class Item {
    @AuraEnabled
    public Id lineId;
    @AuraEnabled
    public Id productId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String imageUrl;
    @AuraEnabled
    public Decimal quantity;
    @AuraEnabled
    public Decimal unitPrice;
    @AuraEnabled
    public Decimal lineTotal;
    @AuraEnabled
    public Boolean available;
  }
  // Versioned attempt metadata uses the existing long-text field; never stores credentials.
  public class Attempt {
    public Integer version = 2;
    public String state = 'New';
    public String fingerprint;
    public Id cartId;
    public String linkId;
    public String url;
    public String gatewayOrderId;
    public String jobId;
    public Id retryOf;
    public String fulfillment;
    public String lastFailurePaymentId;
    public String lastFailureState;
    // Opt-in only for newly initiated links. Historical attempts remain untouched.
    public Integer expirySeconds;
    public Long linkCreatedAt;
    public Boolean expiryRequested;
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
        'Sign in with your GoldVuee customer account.'
      );
    return u.ContactId;
  }
  public static void lockCustomer(Id cid) {
    Contact owner = [
      SELECT Id
      FROM Contact
      WHERE Id = :cid
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
  }
  public static Shopping_Cart__c cart(Id cid, Boolean createIfEmpty) {
    List<Shopping_Cart__c> rows = [
      SELECT Id, Cart_Status__c
      FROM Shopping_Cart__c
      WHERE Customer__c = :cid AND Cart_Status__c = 'Active'
      WITH SYSTEM_MODE
      LIMIT 2
    ];
    if (rows.size() > 1)
      throw new AuraHandledException(
        'Your account has multiple current bags. Contact GoldVuee support.'
      );
    if (!rows.isEmpty())
      return rows[0];
    if (!createIfEmpty)
      return null;
    Shopping_Cart__c result = new Shopping_Cart__c(
      Customer__c = cid,
      Cart_Status__c = 'Active'
    );
    insert as system result;
    return result;
  }
  public static void quantity(Decimal value) {
    if (value == null || value < 1 || value > 100 || value != value.setScale(0))
      throw new AuraHandledException('Choose a whole quantity from 1 to 100.');
  }
  public static Decimal price(Jewellery_Product__c p) {
    if (p.Price__c == null || p.Price__c <= 0)
      throw new AuraHandledException('This jewellery price is unavailable.');
    return p.Discount_Price__c != null &&
      p.Discount_Price__c > 0 &&
      p.Discount_Price__c < p.Price__c
      ? p.Discount_Price__c
      : p.Price__c;
  }
  public static List<Item> cartItems(Id cartId) {
    List<Item> result = new List<Item>();
    for (Cart_Item__c row : [
      SELECT
        Id,
        Jewellery_Product__c,
        Quantity__c,
        Jewellery_Product__r.Name,
        Jewellery_Product__r.Main_Image_URL__c,
        Jewellery_Product__r.Price__c,
        Jewellery_Product__r.Discount_Price__c,
        Jewellery_Product__r.Active__c,
        Jewellery_Product__r.Available_Quantity__c
      FROM Cart_Item__c
      WHERE Shopping_Cart__c = :cartId
      WITH SYSTEM_MODE
      ORDER BY CreatedDate, Id
    ]) {
      Item item = new Item();
      item.lineId = row.Id;
      item.productId = row.Jewellery_Product__c;
      item.name = row.Jewellery_Product__r.Name;
      item.imageUrl = row.Jewellery_Product__r.Main_Image_URL__c;
      item.quantity = row.Quantity__c;
      item.unitPrice = row.Jewellery_Product__r.Price__c > 0
        ? price(row.Jewellery_Product__r)
        : 0;
      item.lineTotal = (item.unitPrice * item.quantity).setScale(2);
      item.available =
        row.Jewellery_Product__r.Active__c &&
        item.unitPrice > 0 &&
        row.Jewellery_Product__r.Available_Quantity__c >= item.quantity;
      result.add(item);
    }
    return result;
  }
  public static List<Item> orderItems(Id orderId) {
    return orderItems(new Set<Id>{ orderId }).get(orderId);
  }
  public static Map<Id, List<Item>> orderItems(Set<Id> orderIds) {
    Map<Id, List<Item>> result = new Map<Id, List<Item>>();
    for (Id id : orderIds)
      result.put(id, new List<Item>());
    for (Jewellery_Order_Item__c row : [
      SELECT
        Id,
        Jewellery_Order__c,
        Jewellery_Product__c,
        Jewellery_Product__r.Name,
        Jewellery_Product__r.Main_Image_URL__c,
        Quantity__c,
        Unit_Price__c,
        Line_Total__c
      FROM Jewellery_Order_Item__c
      WHERE Jewellery_Order__c IN :orderIds
      WITH SYSTEM_MODE
      ORDER BY CreatedDate, Id
    ]) {
      Item item = new Item();
      item.lineId = row.Id;
      item.productId = row.Jewellery_Product__c;
      item.name = row.Jewellery_Product__r.Name;
      item.imageUrl = row.Jewellery_Product__r.Main_Image_URL__c;
      item.quantity = row.Quantity__c;
      item.unitPrice = row.Unit_Price__c;
      item.lineTotal = row.Line_Total__c;
      item.available = true;
      result.get(row.Jewellery_Order__c).add(item);
    }
    return result;
  }
  public static String fingerprint(
    String address,
    String city,
    String state,
    String pin,
    String country,
    List<Item> items,
    Decimal total
  ) {
    List<String> selection = new List<String>();
    for (Item item : items)
      selection.add(
        String.valueOf(item.productId) +
          ':' +
          String.valueOf(item.quantity.setScale(0)) +
          ':' +
          String.valueOf(item.lineTotal.setScale(2))
      );
    selection.sort();
    List<String> parts = new List<String>{ address, city, state, pin, country };
    for (Integer i = 0; i < parts.size(); i++)
      parts[i] = parts[i] == null
        ? ''
        : parts[i].trim().replaceAll('\\s+', ' ').toLowerCase();
    parts.addAll(selection);
    parts.add(String.valueOf(total.setScale(2)));
    return EncodingUtil.convertToHex(
      Crypto.generateDigest('SHA-256', Blob.valueOf(JSON.serialize(parts)))
    );
  }
  public static Attempt attempt(Payment__c payment) {
    if (!String.isBlank(payment.Gateway_Response__c)) {
      try {
        Attempt value = (Attempt) JSON.deserialize(
          payment.Gateway_Response__c,
          Attempt.class
        );
        if (
          value != null &&
          (value.version == 0 ||
          value.version == 1 ||
          value.version == 2) &&
          !String.isBlank(value.state)
        ) {
          if (
            value.version != 2 &&
            value.state == 'New' &&
            value.linkId == null
          )
            value.state = 'Legacy review';
          return value;
        }
      } catch (Exception ignored) {
      }
    }
    Attempt legacy = new Attempt();
    legacy.version = 0;
    legacy.state = 'Legacy review';
    legacy.gatewayOrderId = payment.Razorpay_Order_ID__c;
    return legacy;
  }
  public static Payment__c payment(Id pid, Id cid) {
    List<Payment__c> rows = [
      SELECT
        Id,
        Jewellery_Order__c,
        Payment_Amount__c,
        Payment_Status__c,
        Gateway_Response__c,
        Razorpay_Order_ID__c,
        Transaction_ID__c,
        Failure_Reason__c,
        Jewellery_Order__r.Customer__c,
        Jewellery_Order__r.Shopping_Cart__c,
        Jewellery_Order__r.Grand_Total__c,
        Jewellery_Order__r.Payment_Status__c,
        Jewellery_Order__r.Order_Status__c,
        Jewellery_Order__r.Name
      FROM Payment__c
      WHERE Id = :pid AND Jewellery_Order__r.Customer__c = :cid
      WITH SYSTEM_MODE
    ];
    if (rows.isEmpty())
      throw new AuraHandledException('Payment not found or access denied.');
    return rows[0];
  }
  public static void stock(Id orderId) {
    List<Item> items = orderItems(orderId);
    Set<Id> ids = new Set<Id>();
    for (Item item : items) {
      quantity(item.quantity);
      ids.add(item.productId);
    }
    Map<Id, Jewellery_Product__c> products = new Map<Id, Jewellery_Product__c>(
      [
        SELECT Id, Active__c, Available_Quantity__c
        FROM Jewellery_Product__c
        WHERE Id IN :ids
        WITH SYSTEM_MODE
        FOR UPDATE
      ]
    );
    if (items.isEmpty() || items.size() > 25 || products.size() != ids.size())
      throw new AuraHandledException(
        'Choose available jewellery before paying.'
      );
    for (Item item : items)
      if (
        !products.get(item.productId).Active__c ||
        products.get(item.productId).Available_Quantity__c < item.quantity
      )
        throw new AuraHandledException(
          'The selected quantity is no longer in stock.'
        );
  }
  public static Boolean sameSelection(Id cartId, Id orderId) {
    List<Item> bag = cartItems(cartId);
    List<Item> saved = orderItems(orderId);
    Decimal bagTotal = 0, savedTotal = 0;
    for (Item item : bag)
      bagTotal += item.lineTotal;
    for (Item item : saved)
      savedTotal += item.lineTotal;
    return fingerprint('', '', '', '', '', bag, bagTotal) ==
      fingerprint('', '', '', '', '', saved, savedTotal);
  }
  /** Freeze at payment initialization, not during shopping. The new editable bag needs no payment lookups. */
  public static Id freezeCart(Id cid, Id orderId, Id oldCartId) {
    Shopping_Cart__c current = cart(cid, false);
    if (
      current == null ||
      current.Id != oldCartId ||
      !sameSelection(current.Id, orderId)
    )
      throw new AuraHandledException(
        'Your bag changed. Review it again before paying.'
      );
    current.Cart_Status__c = 'Abandoned';
    update as system current;
    Shopping_Cart__c next = new Shopping_Cart__c(
      Customer__c = cid,
      Cart_Status__c = 'Active'
    );
    insert as system next;
    List<Cart_Item__c> copies = new List<Cart_Item__c>();
    for (Item item : cartItems(current.Id))
      copies.add(
        new Cart_Item__c(
          Shopping_Cart__c = next.Id,
          Jewellery_Product__c = item.productId,
          Quantity__c = item.quantity,
          Unit_Price__c = item.unitPrice
        )
      );
    insert as system copies;
    return next.Id;
  }
  public static Decimal numberValue(Object value) {
    return value == null ? null : Decimal.valueOf(String.valueOf(value));
  }
  /** Only called with authenticated gateway evidence. Every fulfillment change commits or rolls back together. */
  public static void captured(
    Id pid,
    String linkId,
    Map<String, Object> evidence
  ) {
    Savepoint checkpoint = Database.setSavepoint();
    try {
      finalizeCapture(pid, linkId, evidence);
    } catch (Exception error) {
      Database.rollback(checkpoint);
      throw error;
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
        Payment_Status__c,
        Payment_Amount__c,
        Gateway_Response__c,
        Razorpay_Order_ID__c,
        Transaction_ID__c
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
      !Pattern.matches('^pay_[A-Za-z0-9]+$', transactionId) ||
      a.gatewayOrderId != evidence.get('order_id') ||
      String.isBlank(a.gatewayOrderId) ||
      evidence.get('status') != 'captured' ||
      evidence.get('captured') != true ||
      evidence.get('currency') != 'INR' ||
      numberValue(evidence.get('amount')) != p.Payment_Amount__c * 100
    )
      throw new CheckoutException(
        'Gateway evidence does not match this payment.'
      );
    if (p.Payment_Status__c == 'Success') {
      if (p.Transaction_ID__c != transactionId)
        throw new CheckoutException(
          'Additional captured transaction requires admin review.'
        );
      return;
    }
    Jewellery_Order__c orderRecord = [
      SELECT Id, Grand_Total__c, Payment_Status__c, Shopping_Cart__c
      FROM Jewellery_Order__c
      WHERE Id = :p.Jewellery_Order__c
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    if (orderRecord.Grand_Total__c != p.Payment_Amount__c)
      throw new CheckoutException('Captured amount requires order review.');
    List<Item> items = orderItems(orderRecord.Id);
    Map<Id, Decimal> quantities = new Map<Id, Decimal>();
    Boolean available = !items.isEmpty();
    for (Item item : items) {
      if (
        item.productId == null ||
        item.quantity == null ||
        item.quantity < 1 ||
        item.quantity != item.quantity.setScale(0)
      )
        available = false;
      else
        quantities.put(
          item.productId,
          (quantities.containsKey(item.productId)
            ? quantities.get(item.productId)
            : 0) + item.quantity
        );
    }
    Map<Id, Jewellery_Product__c> products = new Map<Id, Jewellery_Product__c>(
      [
        SELECT
          Id,
          Active__c,
          Stock_Quantity__c,
          Reserved_Quantity__c,
          Available_Quantity__c
        FROM Jewellery_Product__c
        WHERE Id IN :quantities.keySet()
        WITH SYSTEM_MODE
        FOR UPDATE
      ]
    );
    available =
      available &&
      products.size() == quantities.size() &&
      orderRecord.Payment_Status__c != 'Paid';
    if (
      [
        SELECT COUNT()
        FROM Inventory_Movement__c
        WHERE Jewellery_Order__c = :orderRecord.Id AND Movement_Type__c = 'Sale'
        WITH SYSTEM_MODE
      ] > 0
    )
      available = false;
    for (Id id : quantities.keySet())
      if (
        !products.containsKey(id) ||
        !products.get(id).Active__c ||
        products.get(id).Available_Quantity__c < quantities.get(id)
      )
        available = false;
    List<Inventory_Movement__c> moves = new List<Inventory_Movement__c>();
    if (available) {
      for (Id id : quantities.keySet()) {
        Jewellery_Product__c product = products.get(id);
        Decimal beforeStock = product.Stock_Quantity__c;
        product.Stock_Quantity__c -= quantities.get(id);
        moves.add(
          new Inventory_Movement__c(
            Jewellery_Product__c = id,
            Jewellery_Order__c = orderRecord.Id,
            Movement_Type__c = 'Sale',
            Quantity__c = quantities.get(id),
            Stock_Before__c = beforeStock,
            Stock_After__c = product.Stock_Quantity__c,
            Movement_Date__c = System.now(),
            Reason__c = 'Verified GoldVuee hosted payment'
          )
        );
      }
      update as system products.values();
      insert as system moves;
    }
    a.state = 'Paid';
    a.fulfillment = available ? 'Confirmed' : 'Stock review required';
    p.Payment_Status__c = 'Success';
    p.Transaction_ID__c = transactionId;
    p.Payment_Date__c = System.now();
    p.Gateway_Response__c = JSON.serialize(a);
    p.Failure_Reason__c = available
      ? null
      : 'PAYMENT CAPTURED: admin fulfillment/refund review required. Do not charge again.';
    Map<String, String> methods = new Map<String, String>{
      'upi' => 'UPI',
      'card' => 'Card',
      'netbanking' => 'Net Banking',
      'wallet' => 'Wallet'
    };
    p.Payment_Method__c = methods.get((String) evidence.get('method'));
    update as system p;
    orderRecord.Payment_Status__c = 'Paid';
    if (available)
      orderRecord.Order_Status__c = 'Confirmed';
    update as system orderRecord;
    Id boundCart = a.cartId == null ? orderRecord.Shopping_Cart__c : a.cartId;
    Shopping_Cart__c current = cart(pre.Jewellery_Order__r.Customer__c, false);
    if (
      available &&
      current != null &&
      current.Id == boundCart &&
      sameSelection(current.Id, orderRecord.Id)
    ) {
      current.Cart_Status__c = 'Converted';
      update as system current;
    }
  }
}
