/** Current cart checkout, independent of immutable historical payment snapshots. */
public without sharing class GVCheckoutController {
  // Deny the obsolete COD API while its separately reviewed org removal is pending.
  public class CheckoutResult {
    @AuraEnabled
    public Id orderId;
    @AuraEnabled
    public String orderNumber;
    @AuraEnabled
    public Decimal grandTotal;
    @AuraEnabled
    public String orderStatus;
    @AuraEnabled
    public String paymentStatus;
    @AuraEnabled
    public String paymentMethod;
    @AuraEnabled
    public String message;
  }
  @AuraEnabled
  public static CheckoutResult placeOrder(
    String shippingAddress,
    String shippingCity,
    String shippingState,
    String shippingPostalCode,
    String shippingCountry
  ) {
    throw new AuraHandledException('Use the GoldVuee hosted checkout.');
  }
  public class Delivery {
    @AuraEnabled
    public String fullName;
    @AuraEnabled
    public String phone;
    @AuraEnabled
    public String street;
    @AuraEnabled
    public String city;
    @AuraEnabled
    public String state;
    @AuraEnabled
    public String postalCode;
    @AuraEnabled
    public String country;
  }
  public class Summary {
    @AuraEnabled
    public Id orderId;
    @AuraEnabled
    public Id paymentId;
    @AuraEnabled
    public String orderNumber;
    @AuraEnabled
    public Decimal total;
    @AuraEnabled
    public Delivery delivery;
    @AuraEnabled
    public List<Jewellery_Order_Item__c> items;
  }
  @AuraEnabled
  public static Delivery loadDelivery() {
    Id cid = GVCheckoutService.customer();
    Contact c = [
      SELECT
        Name,
        Phone,
        MobilePhone,
        MailingStreet,
        MailingCity,
        MailingState,
        MailingPostalCode,
        MailingCountry
      FROM Contact
      WHERE Id = :cid
      WITH SYSTEM_MODE
    ];
    Delivery d = new Delivery();
    d.fullName = addressText(c.Name, 120);
    d.phone = normalizePhone(c.MobilePhone);
    if (String.isBlank(d.phone)) d.phone = normalizePhone(c.Phone);
    d.street = addressText(c.MailingStreet, 1000);
    d.city = addressText(c.MailingCity, 50);
    d.state = addressText(c.MailingState, 50);
    d.postalCode = Pattern.matches('^[1-9][0-9]{5}$', text(c.MailingPostalCode)) ? text(c.MailingPostalCode) : '';
    d.country = text(c.MailingCountry);
    if (!d.country.equalsIgnoreCase('India')) d.country = 'India';
    return d;
  }
  private static String text(String value) {
    String clean = value == null ? '' : value.trim();
    return clean.equalsIgnoreCase('null') || clean.equalsIgnoreCase('undefined') ? '' : clean;
  }
  // Matches the shared HTML/JavaScript input rule. Never strip arbitrary invalid characters.
  private static String normalizePhone(String value) {
    String clean = text(value);
    if (!Pattern.matches('\\s*(?:\\+91\\s?)?[6-9][0-9]{9}\\s*', clean)) return '';
    clean = clean.replaceAll('\\s', '');
    return clean.startsWith('+91') ? clean.substring(3) : clean;
  }
  private static Boolean phoneOnly(String value) {
    return Pattern.matches('^\\+?[0-9][0-9\\s().-]{8,}$', text(value));
  }
  private static String addressText(String value, Integer maximum) {
    String clean = text(value);
    return clean.length() > maximum || phoneOnly(clean) ? '' : clean;
  }
  private static void validateDelivery(Delivery d) {
    if (d == null) throw new AuraHandledException('Complete all delivery address fields.');
    String phone = normalizePhone(d.phone);
    if (String.isBlank(phone)) throw new AuraHandledException('Enter a valid Indian mobile number: 9691184503, +919691184503 or +91 9691184503.');
    if (phoneOnly(d.street)) throw new AuraHandledException('Enter your street address, not a phone number.');
    d.phone = phone;
    d.fullName = text(d.fullName);
    d.street = text(d.street);
    d.city = text(d.city);
    d.state = text(d.state);
    d.postalCode = text(d.postalCode);
    d.country = text(d.country);
    if (
      d == null ||
      String.isBlank(d.fullName) ||
      String.isBlank(d.phone) ||
      String.isBlank(d.street) ||
      String.isBlank(d.city) ||
      String.isBlank(d.state) ||
      String.isBlank(d.postalCode) ||
      String.isBlank(d.country) ||
      d.fullName.length() > 120 ||
      d.street.length() > 1000 ||
      d.city.length() > 50 ||
      d.state.length() > 50 ||
      phoneOnly(d.fullName) || phoneOnly(d.city) || phoneOnly(d.state) ||
      d.country.trim().toLowerCase() != 'india' ||
      !Pattern.matches('^[1-9][0-9]{5}$', d.postalCode.trim()) ||
      !Pattern.matches('^[6-9][0-9]{9}$', d.phone.trim())
    )
      throw new AuraHandledException(
        'Enter a complete Indian delivery address, mobile number and six-digit PIN.'
      );
  }
  @AuraEnabled
  public static Summary prepareOrder(Delivery delivery) {
    Id cid = GVCheckoutService.customer();
    GVCheckoutService.lockCustomer(cid);
    if (delivery != null && String.isBlank(delivery.country))
      delivery.country = 'India';
    validateDelivery(delivery);
    List<Shopping_Cart__c> carts = [
      SELECT Id
      FROM Shopping_Cart__c
      WHERE Customer__c = :cid AND Cart_Status__c = 'Active'
      WITH SYSTEM_MODE
      LIMIT 2
      FOR UPDATE
    ];
    if (carts.size() != 1)
      throw new AuraHandledException(
        'Choose products in your shopping bag first.'
      );
    Id cartId = carts[0].Id;
    List<Jewellery_Order__c> orders = [
      SELECT
        Id,
        Shipping_Address__c,
        Shipping_City__c,
        Shipping_State__c,
        Shipping_Postal_Code__c,
        Shipping_Country__c
      FROM Jewellery_Order__c
      WHERE
        Shopping_Cart__c = :cartId
        AND Order_Status__c = 'pending'
        AND Payment_Status__c = 'Pending'
      WITH SYSTEM_MODE
      ORDER BY CreatedDate DESC, Id DESC
      LIMIT 1
    ];
    Jewellery_Order__c o;
    List<Payment__c> existing = new List<Payment__c>();
    if (!orders.isEmpty()) {
      o = orders[0];
      existing = [
        SELECT
          Id,
          Payment_Status__c,
          Gateway_Response__c,
          Razorpay_Order_ID__c,
          Transaction_ID__c
        FROM Payment__c
        WHERE Jewellery_Order__c = :o.Id AND Payment_Status__c = 'Pending'
        WITH SYSTEM_MODE
        LIMIT 2
      ];
      if (existing.size() > 1)
        throw new AuraHandledException(
          'Previous payment attempts require review.'
        );
      if (
        !existing.isEmpty() &&
        GVCheckoutService.attempt(existing[0]).state != 'New'
      ) {
        String address =
          delivery.fullName.trim() +
          '\n' +
          delivery.phone.trim() +
          '\n' +
          delivery.street.trim();
        if (
          GVCheckoutService.attempt(existing[0]).state != 'Legacy review' &&
          sameSelection(cartId, o.Id) &&
          o.Shipping_Address__c == address &&
          o.Shipping_City__c == delivery.city.trim() &&
          o.Shipping_State__c == delivery.state.trim() &&
          o.Shipping_Postal_Code__c == delivery.postalCode.trim() &&
          o.Shipping_Country__c == delivery.country.trim()
        )
          return summary(o.Id, cid);
        // An address change creates an independent checkout, never edits a payable snapshot.
        cartId = GVCheckoutService.forkCart(cartId, cid);
        o = null;
        existing.clear();
      }
    }
    Id independentCart = GVCheckoutService.editableCart(cartId, cid);
    if (independentCart != cartId) {
      cartId = independentCart;
      o = null;
      existing.clear();
    }
    Map<Id, Decimal> qty = new Map<Id, Decimal>();
    for (Cart_Item__c i : [
      SELECT Jewellery_Product__c, Quantity__c
      FROM Cart_Item__c
      WHERE Shopping_Cart__c = :cartId
      WITH SYSTEM_MODE
    ]) {
      GVCheckoutService.quantity(i.Quantity__c);
      if (qty.containsKey(i.Jewellery_Product__c))
        throw new AuraHandledException('Duplicate bag lines require support.');
      qty.put(i.Jewellery_Product__c, i.Quantity__c);
    }
    if (qty.isEmpty() || qty.size() > 25)
      throw new AuraHandledException('Choose between 1 and 25 products.');
    Map<Id, Jewellery_Product__c> products = new Map<Id, Jewellery_Product__c>(
      [
        SELECT
          Id,
          Name,
          Active__c,
          Price__c,
          Discount_Price__c,
          Available_Quantity__c
        FROM Jewellery_Product__c
        WHERE Id IN :qty.keySet()
        WITH SYSTEM_MODE
        FOR UPDATE
      ]
    );
    if (products.size() != qty.size())
      throw new AuraHandledException('Product unavailable.');
    Decimal total = 0;
    for (Id pid : qty.keySet()) {
      if (
        !products.get(pid).Active__c ||
        products.get(pid).Available_Quantity__c < qty.get(pid)
      )
        throw new AuraHandledException(
          'Insufficient stock for ' + products.get(pid).Name
        );
      total += GVCheckoutService.price(products.get(pid)) * qty.get(pid);
    }
    if (o == null)
      o = new Jewellery_Order__c(
        Customer__c = cid,
        Shopping_Cart__c = cartId,
        Order_Date__c = System.now(),
        Order_Status__c = 'pending',
        Payment_Status__c = 'Pending'
      );
    o.Subtotal__c = total.setScale(2);
    o.Discount_Amount__c = 0;
    o.Tax_Amount__c = 0;
    o.Shipping_Charges__c = 0;
    // Existing schema has one address text field: retain recipient, phone and street in the immutable snapshot.
    o.Shipping_Address__c =
      delivery.fullName.trim() +
      '\n' +
      delivery.phone.trim() +
      '\n' +
      delivery.street.trim();
    o.Shipping_City__c = delivery.city.trim();
    o.Shipping_State__c = delivery.state.trim();
    o.Shipping_Postal_Code__c = delivery.postalCode.trim();
    o.Shipping_Country__c = 'India';
    upsert as system o;
    delete as system [
      SELECT Id
      FROM Jewellery_Order_Item__c
      WHERE Jewellery_Order__c = :o.Id
      WITH SYSTEM_MODE
    ];
    List<Jewellery_Order_Item__c> lines = new List<Jewellery_Order_Item__c>();
    for (Id pid : qty.keySet())
      lines.add(
        new Jewellery_Order_Item__c(
          Jewellery_Order__c = o.Id,
          Jewellery_Product__c = pid,
          Quantity__c = qty.get(pid),
          Unit_Price__c = GVCheckoutService.price(products.get(pid)),
          Discount_Amount__c = 0
        )
      );
    insert as system lines;
    Payment__c p = existing.isEmpty()
      ? new Payment__c(Jewellery_Order__c = o.Id, Payment_Status__c = 'Pending')
      : existing[0];
    p.Payment_Amount__c = total.setScale(2);
    p.Gateway_Response__c = JSON.serialize(new GVCheckoutService.Attempt());
    upsert as system p;
    return summary(o.Id, cid);
  }
  private static Boolean sameSelection(Id cartId, Id orderId) {
    Map<Id, String> bag = new Map<Id, String>();
    for (Cart_Item__c line : [
      SELECT Jewellery_Product__c, Quantity__c, Unit_Price__c
      FROM Cart_Item__c
      WHERE Shopping_Cart__c = :cartId
      WITH SYSTEM_MODE
    ]) {
      if (line.Quantity__c == null || line.Unit_Price__c == null)
        return false;
      bag.put(
        line.Jewellery_Product__c,
        String.valueOf(line.Quantity__c.setScale(0)) +
          '|' +
          String.valueOf(line.Unit_Price__c.setScale(2))
      );
    }
    Map<Id, String> snapshot = new Map<Id, String>();
    for (Jewellery_Order_Item__c line : [
      SELECT Jewellery_Product__c, Quantity__c, Unit_Price__c
      FROM Jewellery_Order_Item__c
      WHERE Jewellery_Order__c = :orderId
      WITH SYSTEM_MODE
    ]) {
      if (line.Quantity__c == null || line.Unit_Price__c == null)
        return false;
      snapshot.put(
        line.Jewellery_Product__c,
        String.valueOf(line.Quantity__c.setScale(0)) +
          '|' +
          String.valueOf(line.Unit_Price__c.setScale(2))
      );
    }
    return bag == snapshot;
  }
  @AuraEnabled
  public static Summary loadOrder(Id orderId) {
    return summary(orderId, GVCheckoutService.customer());
  }
  private static Summary summary(Id oid, Id cid) {
    List<Jewellery_Order__c> orders = [
      SELECT
        Id,
        Name,
        Grand_Total__c,
        Shipping_Address__c,
        Shipping_City__c,
        Shipping_State__c,
        Shipping_Postal_Code__c,
        Shipping_Country__c
      FROM Jewellery_Order__c
      WHERE Id = :oid AND Customer__c = :cid
      WITH SYSTEM_MODE
    ];
    if (orders.isEmpty())
      throw new AuraHandledException('Order not found or access denied.');
    Jewellery_Order__c o = orders[0];
    Summary r = new Summary();
    r.orderId = o.Id;
    r.orderNumber = o.Name;
    r.total = o.Grand_Total__c;
    List<Payment__c> ps = [
      SELECT Id
      FROM Payment__c
      WHERE Jewellery_Order__c = :o.Id AND Payment_Status__c = 'Pending'
      WITH SYSTEM_MODE
      ORDER BY CreatedDate DESC, Id DESC
      LIMIT 1
    ];
    if (ps.isEmpty())
      ps = [
        SELECT Id
        FROM Payment__c
        WHERE Jewellery_Order__c = :o.Id
        WITH SYSTEM_MODE
        ORDER BY CreatedDate DESC, Id DESC
        LIMIT 1
      ];
    if (!ps.isEmpty())
      r.paymentId = ps[0].Id;
    r.delivery = new Delivery();
    // Preserve the existing stored snapshot; expose recipient, phone and street separately.
    String snapshot = text(o.Shipping_Address__c);
    Integer firstBreak = snapshot.indexOf('\n');
    Integer secondBreak = firstBreak < 0 ? -1 : snapshot.indexOf('\n', firstBreak + 1);
    r.delivery.fullName = '';
    r.delivery.phone = '';
    r.delivery.street = addressText(snapshot, 1000);
    if (secondBreak > firstBreak && firstBreak > 0) {
      String snapshotPhone = normalizePhone(snapshot.substring(firstBreak + 1, secondBreak));
      if (!String.isBlank(snapshotPhone)) {
        r.delivery.fullName = addressText(snapshot.substring(0, firstBreak), 120);
        r.delivery.phone = snapshotPhone;
        r.delivery.street = addressText(snapshot.substring(secondBreak + 1), 1000);
      }
    }
    r.delivery.city = text(o.Shipping_City__c);
    r.delivery.state = text(o.Shipping_State__c);
    r.delivery.postalCode = text(o.Shipping_Postal_Code__c);
    r.delivery.country = text(o.Shipping_Country__c);
    r.items = [
      SELECT
        Id,
        Jewellery_Product__r.Name,
        Jewellery_Product__r.Main_Image_URL__c,
        Quantity__c,
        Unit_Price__c,
        Line_Total__c
      FROM Jewellery_Order_Item__c
      WHERE Jewellery_Order__c = :oid
      WITH SYSTEM_MODE
    ];
    return r;
  }
}
