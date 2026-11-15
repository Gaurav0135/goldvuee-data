/** Current editable bag. Payment state is never queried by cart operations. */
public without sharing class GVCartController {
  public class CartResponse {
    @AuraEnabled
    public Id cartId;
    @AuraEnabled
    public Decimal totalAmount = 0;
    @AuraEnabled
    public Integer itemCount = 0;
    @AuraEnabled
    public List<GVCheckoutService.Item> items = new List<GVCheckoutService.Item>();
  }
  @AuraEnabled
  public static CartResponse getCart() {
    Id cid = GVCheckoutService.customer();
    CartResponse result = new CartResponse();
    Shopping_Cart__c cart = GVCheckoutService.cart(cid, false);
    if (cart == null)
      return result;
    result.cartId = cart.Id;
    result.items = GVCheckoutService.cartItems(cart.Id);
    for (GVCheckoutService.Item item : result.items) {
      result.itemCount += Integer.valueOf(item.quantity);
      result.totalAmount += item.lineTotal;
    }
    return result;
  }
  @AuraEnabled
  public static CartResponse addToCart(Id productId, Integer quantity) {
    GVCheckoutService.quantity(quantity);
    Id cid = GVCheckoutService.customer();
    GVCheckoutService.lockCustomer(cid);
    Shopping_Cart__c cart = GVCheckoutService.cart(cid, true);
    List<Cart_Item__c> rows = [
      SELECT Id, Quantity__c
      FROM Cart_Item__c
      WHERE Shopping_Cart__c = :cart.Id AND Jewellery_Product__c = :productId
      WITH SYSTEM_MODE
      LIMIT 2
    ];
    if (rows.size() > 1)
      throw new AuraHandledException(
        'Duplicate product lines require support review.'
      );
    Decimal units = quantity + (rows.isEmpty() ? 0 : rows[0].Quantity__c);
    Decimal price = validatedPrice(productId, units);
    if (rows.isEmpty()) {
      if (
        [
          SELECT COUNT()
          FROM Cart_Item__c
          WHERE Shopping_Cart__c = :cart.Id
          WITH SYSTEM_MODE
        ] >= 25
      )
        throw new AuraHandledException(
          'Choose up to 25 different jewellery pieces.'
        );
      insert as system new Cart_Item__c(
        Shopping_Cart__c = cart.Id,
        Jewellery_Product__c = productId,
        Quantity__c = units,
        Unit_Price__c = price
      );
    } else
      update as system new Cart_Item__c(
        Id = rows[0].Id,
        Quantity__c = units,
        Unit_Price__c = price
      );
    return getCart();
  }
  @AuraEnabled
  public static CartResponse updateCartItem(Id cartItemId, Integer quantity) {
    GVCheckoutService.quantity(quantity);
    Id cid = GVCheckoutService.customer();
    GVCheckoutService.lockCustomer(cid);
    Cart_Item__c line = currentLine(cartItemId, cid);
    if (line == null)
      throw new AuraHandledException(
        'This jewellery is no longer in your current bag. Refresh your bag.'
      );
    update as system new Cart_Item__c(
      Id = line.Id,
      Quantity__c = quantity,
      Unit_Price__c = validatedPrice(line.Jewellery_Product__c, quantity)
    );
    return getCart();
  }
  @AuraEnabled
  public static CartResponse removeCartItem(Id cartItemId) {
    Id cid = GVCheckoutService.customer();
    GVCheckoutService.lockCustomer(cid);
    Cart_Item__c line = currentLine(cartItemId, cid);
    if (line != null)
      delete as system line;
    return getCart();
  }
  // A tab may still hold a line ID from the frozen snapshot. Resolve its product into the current bag.
  private static Cart_Item__c currentLine(Id lineId, Id cid) {
    List<Cart_Item__c> owned = [
      SELECT Jewellery_Product__c
      FROM Cart_Item__c
      WHERE Id = :lineId AND Shopping_Cart__r.Customer__c = :cid
      WITH SYSTEM_MODE
    ];
    if (owned.isEmpty())
      throw new AuraHandledException('Bag item not found or access denied.');
    Shopping_Cart__c cart = GVCheckoutService.cart(cid, false);
    if (cart == null)
      return null;
    Id productId = owned[0].Jewellery_Product__c;
    List<Cart_Item__c> rows = [
      SELECT Id, Jewellery_Product__c
      FROM Cart_Item__c
      WHERE Shopping_Cart__c = :cart.Id AND Jewellery_Product__c = :productId
      WITH SYSTEM_MODE
      LIMIT 2
    ];
    if (rows.size() > 1)
      throw new AuraHandledException(
        'Duplicate product lines require support review.'
      );
    return rows.isEmpty() ? null : rows[0];
  }
  private static Decimal validatedPrice(Id productId, Decimal units) {
    GVCheckoutService.quantity(units);
    List<Jewellery_Product__c> products = [
      SELECT Id, Active__c, Price__c, Discount_Price__c, Available_Quantity__c
      FROM Jewellery_Product__c
      WHERE Id = :productId
      WITH SYSTEM_MODE
    ];
    if (
      products.isEmpty() ||
      !products[0].Active__c ||
      products[0].Available_Quantity__c < units
    )
      throw new AuraHandledException('The requested quantity is unavailable.');
    return GVCheckoutService.price(products[0]);
  }
}
