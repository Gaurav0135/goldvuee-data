/** Customer identity and row ownership are checked before all privileged cart operations. */
public without sharing class GVCartController {
  public class CartResponse {
    @AuraEnabled
    public Id cartId;
    @AuraEnabled
    public Decimal totalAmount = 0;
    @AuraEnabled
    public Integer itemCount = 0;
    @AuraEnabled
    public List<Cart_Item__c> items = new List<Cart_Item__c>();
  }
  @AuraEnabled
  public static CartResponse getCart() {
    Id cid = GVCheckoutEngine.customer();
    CartResponse result = new CartResponse();
    List<Shopping_Cart__c> carts = [
      SELECT Id, Total_Amount__c
      FROM Shopping_Cart__c
      WHERE Customer__c = :cid AND Cart_Status__c = 'Active'
      WITH SYSTEM_MODE
      LIMIT 2
    ];
    if (carts.isEmpty())
      return result;
    if (carts.size() > 1)
      throw new AuraHandledException('Multiple active bags require support.');
    result.cartId = carts[0].Id;
    result.items = [
      SELECT
        Id,
        Name,
        Shopping_Cart__c,
        Jewellery_Product__c,
        Jewellery_Product__r.Name,
        Jewellery_Product__r.Main_Image_URL__c,
        Jewellery_Product__r.Available_Quantity__c,
        Quantity__c,
        Unit_Price__c,
        Line_Total__c
      FROM Cart_Item__c
      WHERE Shopping_Cart__c = :result.cartId
      WITH SYSTEM_MODE
      ORDER BY CreatedDate
    ];
    for (Cart_Item__c item : result.items) {
      result.itemCount += Integer.valueOf(item.Quantity__c);
      result.totalAmount += item.Line_Total__c;
    }
    return result;
  }
  @AuraEnabled
  public static CartResponse addToCart(Id productId, Integer quantity) {
    Id cid = GVCheckoutEngine.customer();
    GVCheckoutEngine.lockCustomer(cid);
    Shopping_Cart__c cart = GVCheckoutEngine.activeCart(cid, true);
    GVCheckoutEngine.assertMutable(cart.Id);
    List<Cart_Item__c> items = [
      SELECT Id, Quantity__c
      FROM Cart_Item__c
      WHERE Shopping_Cart__c = :cart.Id AND Jewellery_Product__c = :productId
      WITH SYSTEM_MODE
    ];
    if (items.size() > 1)
      throw new AuraHandledException('Duplicate bag lines require support.');
    Integer qty = quantity;
    if (!items.isEmpty() && qty != null)
      qty += Integer.valueOf(items[0].Quantity__c);
    Decimal price = validateProduct(productId, qty);
    if (items.isEmpty())
      insert as system new Cart_Item__c(
        Shopping_Cart__c = cart.Id,
        Jewellery_Product__c = productId,
        Quantity__c = qty,
        Unit_Price__c = price
      );
    else
      update as system new Cart_Item__c(
        Id = items[0].Id,
        Quantity__c = qty,
        Unit_Price__c = price
      );
    return getCart();
  }
  @AuraEnabled
  public static CartResponse updateCartItem(Id cartItemId, Integer quantity) {
    Id cid = GVCheckoutEngine.customer();
    GVCheckoutEngine.lockCustomer(cid);
    Cart_Item__c item = ownedItem(cartItemId, cid);
    GVCheckoutEngine.assertMutable(item.Shopping_Cart__c);
    update as system new Cart_Item__c(
      Id = item.Id,
      Quantity__c = quantity,
      Unit_Price__c = validateProduct(item.Jewellery_Product__c, quantity)
    );
    return getCart();
  }
  @AuraEnabled
  public static CartResponse removeCartItem(Id cartItemId) {
    Id cid = GVCheckoutEngine.customer();
    GVCheckoutEngine.lockCustomer(cid);
    Cart_Item__c item = ownedItem(cartItemId, cid);
    GVCheckoutEngine.assertMutable(item.Shopping_Cart__c);
    delete as system item;
    return getCart();
  }
  private static Cart_Item__c ownedItem(Id iid, Id cid) {
    List<Cart_Item__c> rows = [
      SELECT Id, Shopping_Cart__c, Jewellery_Product__c
      FROM Cart_Item__c
      WHERE
        Id = :iid
        AND Shopping_Cart__r.Customer__c = :cid
        AND Shopping_Cart__r.Cart_Status__c = 'Active'
      WITH SYSTEM_MODE
    ];
    if (rows.isEmpty())
      throw new AuraHandledException('Bag item not found or access denied.');
    return rows[0];
  }
  private static Decimal validateProduct(Id pid, Integer qty) {
    if (qty == null || qty < 1 || qty > 100)
      throw new AuraHandledException('Quantity must be between 1 and 100.');
    List<Jewellery_Product__c> rows = [
      SELECT Id, Active__c, Price__c, Discount_Price__c, Available_Quantity__c
      FROM Jewellery_Product__c
      WHERE Id = :pid AND Active__c = TRUE
      WITH SYSTEM_MODE
    ];
    if (rows.isEmpty() || rows[0].Available_Quantity__c < qty)
      throw new AuraHandledException('Insufficient available stock.');
    return GVCheckoutEngine.price(rows[0]);
  }
}
