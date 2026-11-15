/** Address, server-priced immutable order snapshot, and same-purchase deduplication. */
public without sharing class GVCheckoutController {
  public class Delivery {
    @AuraEnabled
    public String fullName { get; set; }
    @AuraEnabled
    public String phone { get; set; }
    @AuraEnabled
    public String street { get; set; }
    @AuraEnabled
    public String city { get; set; }
    @AuraEnabled
    public String state { get; set; }
    @AuraEnabled
    public String postalCode { get; set; }
    @AuraEnabled
    public String country { get; set; }

    public Delivery() {
      fullName = '';
      phone = '';
      street = '';
      city = '';
      state = '';
      postalCode = '';
      country = 'India';
    }
  }

  public class Summary {
    @AuraEnabled
    public Id orderId;
    @AuraEnabled
    public Id paymentId;
    @AuraEnabled
    public Id cartId;
    @AuraEnabled
    public String orderNumber;
    @AuraEnabled
    public Decimal total;
    @AuraEnabled
    public Delivery delivery;
    @AuraEnabled
    public List<GVCheckoutService.Item> items;
  }
  private static String clean(String value) {
    String text = value == null ? '' : value.trim();
    return text.equalsIgnoreCase('null') || text.equalsIgnoreCase('undefined')
      ? ''
      : text;
  }
  private static Boolean phoneOnly(String value) {
    return Pattern.matches('^\\+?[0-9][0-9\\s().-]{8,}$', clean(value));
  }
  private static String addressText(String value, Integer maximum) {
    String text = clean(value);
    return phoneOnly(text) || text.length() > maximum ? '' : text;
  }
  private static String phone(String value) {
    String text = clean(value);
    if (!Pattern.matches('(?:\\+91\\s?)?[6-9][0-9]{9}', text))
      return '';
    text = text.replaceAll('\\s', '');
    return text.startsWith('+91') ? text.substring(3) : text;
  }
  @AuraEnabled
  public static Delivery loadDelivery() {
    Id cid = GVCheckoutService.customer();
    Contact owner = [
      SELECT
        Name,
        MobilePhone,
        Phone,
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
    d.fullName = addressText(owner.Name, 120);
    d.phone = phone(owner.MobilePhone);
    if (d.phone == '')
      d.phone = phone(owner.Phone);
    d.street = addressText(owner.MailingStreet, 1000);
    d.city = addressText(owner.MailingCity, 50);
    d.state = addressText(owner.MailingState, 50);
    d.postalCode = Pattern.matches(
        '[1-9][0-9]{5}',
        clean(owner.MailingPostalCode)
      )
      ? clean(owner.MailingPostalCode)
      : '';
    return d;
  }
  // private static void normalizeDelivery(Delivery d) {
  //   d.fullName = clean(d.fullName);
  //   String normalizedPhone = phone(d.phone);
  //   d.phone = normalizedPhone == '' ? clean(d.phone) : normalizedPhone;
  //   d.street = clean(d.street);
  //   d.city = clean(d.city);
  //   d.state = clean(d.state);
  //   d.postalCode = clean(d.postalCode);
  //   d.country = clean(d.country);
  // }

  private static void normalizeDelivery(Delivery d) {
    d.fullName = clean(d.fullName);
    d.phone = clean(d.phone).replaceAll('[^0-9]', '');

    if (d.phone.length() == 12 && d.phone.startsWith('91')) {
      d.phone = d.phone.substring(2);
    }

    d.street = clean(d.street);
    d.city = clean(d.city);
    d.state = clean(d.state);
    d.postalCode = clean(d.postalCode);
    d.country = 'India';

    if (
      String.isBlank(d.fullName) ||
      String.isBlank(d.street) ||
      String.isBlank(d.city) ||
      String.isBlank(d.state) ||
      !Pattern.matches('^[6-9][0-9]{9}$', d.phone) ||
      !Pattern.matches('^[1-9][0-9]{5}$', d.postalCode)
    ) {
      throw new AuraHandledException(
        'Enter your name, mobile number and complete Indian delivery address.'
      );
    }

    if (
      d.fullName.length() > 120 ||
      d.street.length() > 1000 ||
      d.city.length() > 50 ||
      d.state.length() > 50
    ) {
      throw new AuraHandledException(
        'Delivery address is too long. Please shorten it.'
      );
    }
  }

  private static String snapshot(Delivery d) {
    return d.fullName + '\n' + d.phone + '\n' + d.street;
  }
  @AuraEnabled
  public static Summary prepareOrder(Delivery delivery) {
    if (delivery == null)
      delivery = new Delivery();
    normalizeDelivery(delivery);
    Id cid = GVCheckoutService.customer();
    GVCheckoutService.lockCustomer(cid);
    Shopping_Cart__c cart = GVCheckoutService.cart(cid, false);
    if (cart == null)
      throw new AuraHandledException('Choose jewellery in your bag first.');
    List<GVCheckoutService.Item> items = GVCheckoutService.cartItems(cart.Id);
    if (items.isEmpty() || items.size() > 25)
      throw new AuraHandledException('Choose 1 to 25 jewellery pieces.');
    Decimal total = 0;
    Set<Id> seen = new Set<Id>();
    for (GVCheckoutService.Item item : items) {
      GVCheckoutService.quantity(item.quantity);
      if (!item.available)
        throw new AuraHandledException(
          'Some jewellery is no longer available in the requested quantity.'
        );
      if (seen.contains(item.productId))
        throw new AuraHandledException(
          'Duplicate bag lines require support review.'
        );
      seen.add(item.productId);
      total += item.lineTotal;
    }
    total = total.setScale(2);
    if (total < 1)
      throw new AuraHandledException('The minimum payable amount is INR 1.');
    String address = snapshot(delivery);
    String key = GVCheckoutService.fingerprint(
      address,
      delivery.city,
      delivery.state,
      delivery.postalCode,
      delivery.country,
      items,
      total
    );
    // Same customer + same delivery + same server-priced items = one logical purchase.
    List<Payment__c> pending = [
      SELECT
        Id,
        Jewellery_Order__c,
        Payment_Amount__c,
        Gateway_Response__c,
        Razorpay_Order_ID__c,
        Transaction_ID__c,
        Jewellery_Order__r.Shipping_Address__c,
        Jewellery_Order__r.Shipping_City__c,
        Jewellery_Order__r.Shipping_State__c,
        Jewellery_Order__r.Shipping_Postal_Code__c,
        Jewellery_Order__r.Shipping_Country__c
      FROM Payment__c
      WHERE
        Jewellery_Order__r.Customer__c = :cid
        AND Payment_Status__c = 'Pending'
        AND Payment_Amount__c = :total
      WITH SYSTEM_MODE
    ];
    Set<Id> legacyOrders = new Set<Id>();
    for (Payment__c p : pending)
      if (GVCheckoutService.attempt(p).fingerprint == null)
        legacyOrders.add(p.Jewellery_Order__c);
    Map<Id, List<GVCheckoutService.Item>> legacyItems = GVCheckoutService.orderItems(
      legacyOrders
    );
    for (Payment__c p : pending) {
      GVCheckoutService.Attempt a = GVCheckoutService.attempt(p);
      String candidate = a.fingerprint;
      if (candidate == null)
        candidate = GVCheckoutService.fingerprint(
          p.Jewellery_Order__r.Shipping_Address__c,
          p.Jewellery_Order__r.Shipping_City__c,
          p.Jewellery_Order__r.Shipping_State__c,
          p.Jewellery_Order__r.Shipping_Postal_Code__c,
          p.Jewellery_Order__r.Shipping_Country__c,
          legacyItems.get(p.Jewellery_Order__c),
          p.Payment_Amount__c
        );

      if (candidate != key) {
        continue;
      }

      // Verify that the existing order has a complete
      // saved delivery address before reusing it.
      Boolean completeAddress =
        !String.isBlank(p.Jewellery_Order__r.Shipping_Address__c) &&
        !String.isBlank(p.Jewellery_Order__r.Shipping_City__c) &&
        !String.isBlank(p.Jewellery_Order__r.Shipping_State__c) &&
        !String.isBlank(p.Jewellery_Order__r.Shipping_Postal_Code__c) &&
        !String.isBlank(p.Jewellery_Order__r.Shipping_Country__c);

      if (!completeAddress) {
        throw new AuraHandledException(
          'This checkout has incomplete saved delivery details. ' +
          'Please contact GoldVuee support before continuing payment.'
        );
      }

      // Reuse the existing payment without modifying
      // its order amount or saved shipping address.
      if (a.version == 2 && a.state != 'New' && a.cartId != cart.Id) {
        a.cartId = cart.Id;
        p.Gateway_Response__c = JSON.serialize(a);
        update as system p;
      }

      return summary(p.Jewellery_Order__c, cid);
    }
    // Only this rebuild's never-initialized draft can be rewritten. Historical/payable snapshots stay intact.
    Payment__c draft;
    Jewellery_Order__c record;
    for (Payment__c p : [
      SELECT
        Id,
        Jewellery_Order__c,
        Gateway_Response__c,
        Razorpay_Order_ID__c,
        Transaction_ID__c
      FROM Payment__c
      WHERE
        Jewellery_Order__r.Customer__c = :cid
        AND Jewellery_Order__r.Shopping_Cart__c = :cart.Id
        AND Payment_Status__c = 'Pending'
      WITH SYSTEM_MODE
    ]) {
      GVCheckoutService.Attempt a = GVCheckoutService.attempt(p);
      if (a.version == 2 && a.state == 'New') {
        draft = p;
        record = new Jewellery_Order__c(Id = p.Jewellery_Order__c);
        break;
      }
    }
    if (record == null)
      record = new Jewellery_Order__c(
        Customer__c = cid,
        Shopping_Cart__c = cart.Id,
        Order_Date__c = System.now(),
        Order_Status__c = 'pending',
        Payment_Status__c = 'Pending'
      );
    record.Subtotal__c = total;
    record.Discount_Amount__c = 0;
    record.Tax_Amount__c = 0;
    record.Shipping_Charges__c = 0;
    record.Shipping_Address__c = address;
    record.Shipping_City__c = delivery.city;
    record.Shipping_State__c = delivery.state;
    record.Shipping_Postal_Code__c = delivery.postalCode;
    record.Shipping_Country__c = delivery.country;
    upsert as system record;
    delete as system [
      SELECT Id
      FROM Jewellery_Order_Item__c
      WHERE Jewellery_Order__c = :record.Id
      WITH SYSTEM_MODE
    ];
    List<Jewellery_Order_Item__c> lines = new List<Jewellery_Order_Item__c>();
    for (GVCheckoutService.Item item : items)
      lines.add(
        new Jewellery_Order_Item__c(
          Jewellery_Order__c = record.Id,
          Jewellery_Product__c = item.productId,
          Quantity__c = item.quantity,
          Unit_Price__c = item.unitPrice,
          Discount_Amount__c = 0
        )
      );
    insert as system lines;
    GVCheckoutService.Attempt a = new GVCheckoutService.Attempt();
    a.fingerprint = key;
    if (draft == null)
      draft = new Payment__c(
        Jewellery_Order__c = record.Id,
        Payment_Status__c = 'Pending'
      );
    draft.Payment_Amount__c = total;
    draft.Gateway_Response__c = JSON.serialize(a);
    upsert as system draft;
    return summary(record.Id, cid);
  }
  @AuraEnabled
  public static Summary loadOrder(Id orderId) {
    return summary(orderId, GVCheckoutService.customer());
  }
  private static Summary summary(Id orderId, Id cid) {
    List<Jewellery_Order__c> rows = [
      SELECT
        Id,
        Name,
        Shopping_Cart__c,
        Grand_Total__c,
        Shipping_Address__c,
        Shipping_City__c,
        Shipping_State__c,
        Shipping_Postal_Code__c,
        Shipping_Country__c
      FROM Jewellery_Order__c
      WHERE Id = :orderId AND Customer__c = :cid
      WITH SYSTEM_MODE
    ];
    if (rows.isEmpty())
      throw new AuraHandledException('Order not found or access denied.');
    Jewellery_Order__c record = rows[0];
    Summary result = new Summary();
    result.orderId = record.Id;
    result.cartId = record.Shopping_Cart__c;
    result.orderNumber = record.Name;
    result.total = record.Grand_Total__c;
    result.items = GVCheckoutService.orderItems(record.Id);
    List<Payment__c> payments = [
      SELECT Id
      FROM Payment__c
      WHERE Jewellery_Order__c = :record.Id
      WITH SYSTEM_MODE
      ORDER BY CreatedDate DESC, Id DESC
      LIMIT 1
    ];
    if (!payments.isEmpty())
      result.paymentId = payments[0].Id;
    Delivery d = new Delivery();
    String saved = record.Shipping_Address__c == null
      ? ''
      : record.Shipping_Address__c;
    Integer first = saved.indexOf('\n');
    Integer second = first < 0 ? -1 : saved.indexOf('\n', first + 1);
    d.street = saved;
    if (first >= 0 && second > first) {
      d.fullName = saved.substring(0, first);
      d.phone = clean(saved.substring(first + 1, second));
      d.street = saved.substring(second + 1);
    }
    d.street = clean(d.street);
    d.city = clean(record.Shipping_City__c);
    d.state = clean(record.Shipping_State__c);
    d.postalCode = clean(record.Shipping_Postal_Code__c);
    d.country = clean(record.Shipping_Country__c);
    result.delivery = d;
    return result;
  }
}
