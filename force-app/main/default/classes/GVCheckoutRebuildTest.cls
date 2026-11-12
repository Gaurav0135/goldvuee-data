@IsTest
private class GVCheckoutRebuildTest {
  @IsTest
  static void bulkInventoryAndIdempotency() {
    Jewellery_Category__c category = new Jewellery_Category__c(
      Name = 'Rebuild category'
    );
    insert as system category;
    Jewellery_Product__c p = new Jewellery_Product__c(
      Name = 'Rebuild test',
      Category__c = category.Id,
      Product_Code__c = 'REBUILD-1',
      SKU__c = 'REBUILD-1',
      Weight__c = 1,
      Price__c = 100,
      Stock_Quantity__c = 3,
      Reserved_Quantity__c = 0,
      Active__c = true
    );
    insert as system p;
    Id rid = GVInventoryService.reserveStock(p.Id, 2, null);
    Boolean rejected = false;
    try {
      GVInventoryService.reserveStock(p.Id, 2, null);
    } catch (GVInventoryService.InventoryException e) {
      rejected = true;
    }
    System.assert(rejected, 'Cannot reserve more than available stock.');
    GVInventoryService.commitReservation(rid);
    GVInventoryService.commitReservation(rid);
    p = [
      SELECT Stock_Quantity__c, Reserved_Quantity__c
      FROM Jewellery_Product__c
      WHERE Id = :p.Id
      WITH SYSTEM_MODE
    ];
    System.assertEquals(1, p.Stock_Quantity__c);
    System.assertEquals(0, p.Reserved_Quantity__c);
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Inventory_Movement__c
        WHERE Jewellery_Product__c = :p.Id
        WITH SYSTEM_MODE
      ]
    );
  }
  @IsTest
  static void rejectAnonymousAndCOD() {
    Boolean rejected = false;
    try {
      GVCheckoutEngine.customer();
    } catch (AuraHandledException e) {
      rejected = true;
    }
    System.assert(rejected);
    Payment__c p = new Payment__c(
      Payment_Amount__c = 10,
      Payment_Status__c = 'Pending',
      Payment_Method__c = 'COD'
    );
    Database.SaveResult r = Database.insert(p, false);
    System.assert(!r.isSuccess());
  }
  @IsTest
  static void stockInvariant() {
    Jewellery_Product__c p = new Jewellery_Product__c(
      Name = 'Invalid stock',
      Product_Code__c = 'REBUILD-2',
      SKU__c = 'REBUILD-2',
      Weight__c = 1,
      Price__c = 100,
      Stock_Quantity__c = 1,
      Reserved_Quantity__c = 2,
      Active__c = true
    );
    System.assert(!Database.insert(p, false).isSuccess());
  }
}
