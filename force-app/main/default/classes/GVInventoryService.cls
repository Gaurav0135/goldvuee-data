/** Inventory writes lock products before reservations and roll back each bulk mutation on DML failure. */
public without sharing class GVInventoryService {
  public class InventoryException extends Exception {
  }
  public static Id reserveStock(Id productId, Decimal quantity, Id orderId) {
    return reserve(new Map<Id, Decimal>{ productId => quantity }, orderId)
      .get(productId);
  }
  public static Map<Id, Id> reserve(Map<Id, Decimal> quantities, Id orderId) {
    if (quantities == null || quantities.isEmpty() || quantities.size() > 25)
      throw new InventoryException('Choose between 1 and 25 products.');
    for (Id pid : quantities.keySet())
      validate(pid, quantities.get(pid));
    Map<Id, Jewellery_Product__c> products = lockProducts(quantities.keySet());
    Map<Id, Stock_Reservation__c> existing = new Map<Id, Stock_Reservation__c>();
    if (orderId != null)
      for (Stock_Reservation__c r : [
        SELECT Id, Jewellery_Product__c, Reserved_Quantity__c, Expires_At__c
        FROM Stock_Reservation__c
        WHERE Jewellery_Order__c = :orderId AND Reservation_Status__c = 'Active'
        WITH SYSTEM_MODE
        FOR UPDATE
      ]) {
        if (existing.containsKey(r.Jewellery_Product__c))
          throw new InventoryException('Duplicate active reservation.');
        existing.put(r.Jewellery_Product__c, r);
      }
    List<Stock_Reservation__c> inserts = new List<Stock_Reservation__c>();
    List<Jewellery_Product__c> changes = new List<Jewellery_Product__c>();
    Map<Id, Id> result = new Map<Id, Id>();
    for (Id pid : quantities.keySet()) {
      Decimal qty = quantities.get(pid);
      Jewellery_Product__c product = products.get(pid);
      if (existing.containsKey(pid)) {
        Stock_Reservation__c r = existing.get(pid);
        if (
          r.Reserved_Quantity__c != qty ||
          r.Expires_At__c == null ||
          r.Expires_At__c <= System.now()
        )
          throw new InventoryException(
            'Reservation must be reconciled before renewal.'
          );
        result.put(pid, r.Id);
        continue;
      }
      if (
        product.Active__c != true ||
        zero(product.Stock_Quantity__c) - zero(product.Reserved_Quantity__c) <
        qty
      )
        throw new InventoryException(
          'Insufficient available stock for ' + product.Name
        );
      product.Reserved_Quantity__c = zero(product.Reserved_Quantity__c) + qty;
      changes.add(product);
      inserts.add(
        new Stock_Reservation__c(
          Jewellery_Product__c = pid,
          Jewellery_Order__c = orderId,
          Reserved_Quantity__c = qty,
          Reservation_Status__c = 'Active',
          Reserved_At__c = System.now(),
          Expires_At__c = System.now().addMinutes(15),
          Reservation_Reason__c = 'Checkout'
        )
      );
    }
    Savepoint reservationSavepoint=Database.setSavepoint();
    try {update as system changes;insert as system inserts;}
    catch(Exception e){Database.rollback(reservationSavepoint);throw e;}
    for (Stock_Reservation__c r : inserts)
      result.put(r.Jewellery_Product__c, r.Id);
    return result;
  }
  public static void commitReservation(Id reservationId) {
    change(new Set<Id>{ reservationId }, true);
  }
  public static void releaseReservation(Id reservationId) {
    change(new Set<Id>{ reservationId }, false);
  }
  public static void change(Set<Id> ids, Boolean commitStock) {
    if (ids == null || ids.isEmpty() || ids.contains(null))
      throw new InventoryException('Reservation ID is required.');
    Set<Id> pids = new Set<Id>();
    for (Stock_Reservation__c r : [
      SELECT Jewellery_Product__c
      FROM Stock_Reservation__c
      WHERE Id IN :ids
      WITH SYSTEM_MODE
    ])
      pids.add(r.Jewellery_Product__c);
    if (pids.isEmpty())
      throw new InventoryException('Reservation not found.');
    Map<Id, Jewellery_Product__c> products = lockProducts(pids);
    List<Stock_Reservation__c> changes = new List<Stock_Reservation__c>();
    List<Inventory_Movement__c> moves = new List<Inventory_Movement__c>();
    Set<Id> dirty = new Set<Id>();
    List<Stock_Reservation__c> rows = [
      SELECT
        Id,
        Jewellery_Product__c,
        Jewellery_Order__c,
        Reserved_Quantity__c,
        Reservation_Status__c,
        Expires_At__c
      FROM Stock_Reservation__c
      WHERE Id IN :ids
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    if (rows.size() != ids.size())
      throw new InventoryException('Reservation not found.');
    for (Stock_Reservation__c r : rows) {
      if (commitStock && r.Reservation_Status__c == 'Committed')
        continue;
      if (
        !commitStock &&
        new Set<String>{ 'Released', 'Release', 'Expired' }
          .contains(r.Reservation_Status__c)
      )
        continue;
      if (r.Reservation_Status__c != 'Active')
        throw new InventoryException('Reservation is not active.');
      if (
        commitStock &&
        (r.Expires_At__c == null ||
        r.Expires_At__c <= System.now())
      )
        throw new InventoryException(
          'Reservation expired; payment requires reconciliation.'
        );
      validate(r.Jewellery_Product__c, r.Reserved_Quantity__c);
      Jewellery_Product__c product = products.get(r.Jewellery_Product__c);
      Decimal qty = r.Reserved_Quantity__c;
      if (
        zero(product.Reserved_Quantity__c) < qty ||
        (commitStock && zero(product.Stock_Quantity__c) < qty)
      )
        throw new InventoryException('Inventory quantities are inconsistent.');
      Decimal before = zero(product.Stock_Quantity__c);
      product.Reserved_Quantity__c = zero(product.Reserved_Quantity__c) - qty;
      if (commitStock) {
        product.Stock_Quantity__c = before - qty;
        r.Reservation_Status__c = 'Committed';
        moves.add(
          new Inventory_Movement__c(
            Jewellery_Product__c = product.Id,
            Jewellery_Order__c = r.Jewellery_Order__c,
            Movement_Type__c = 'Sale',
            Quantity__c = qty,
            Stock_Before__c = before,
            Stock_After__c = before - qty,
            Movement_Date__c = System.now(),
            Reason__c = 'Reservation ' + r.Id
          )
        );
      } else {
        r.Reservation_Status__c = r.Expires_At__c != null &&
          r.Expires_At__c <= System.now()
          ? 'Expired'
          : 'Released';
        r.Released_At__c = System.now();
      }
      dirty.add(product.Id);
      changes.add(r);
    }
    List<Jewellery_Product__c> productChanges = new List<Jewellery_Product__c>();
    for (Id pid : dirty)
      productChanges.add(products.get(pid));
    Savepoint mutationSavepoint=Database.setSavepoint();
    try {update as system productChanges;update as system changes;insert as system moves;}
    catch(Exception e){Database.rollback(mutationSavepoint);throw e;}
  }
  private static Map<Id, Jewellery_Product__c> lockProducts(Set<Id> ids) {
    Map<Id, Jewellery_Product__c> result = new Map<Id, Jewellery_Product__c>(
      [
        SELECT Id, Name, Active__c, Stock_Quantity__c, Reserved_Quantity__c
        FROM Jewellery_Product__c
        WHERE Id IN :ids
        WITH SYSTEM_MODE
        FOR UPDATE
      ]
    );
    if (result.size() != ids.size())
      throw new InventoryException('Product not found.');
    return result;
  }
  private static void validate(Id pid, Decimal qty) {
    if (pid == null || qty == null || qty <= 0 || qty != qty.setScale(0))
      throw new InventoryException('Invalid product or quantity.');
  }
  private static Decimal zero(Decimal value) {
    return value == null ? 0 : value;
  }
}