
/**
 * GOLDVUEE | INVENTORY SERVICE
 *
 * New checkout architecture:
 * - No inventory reservation for new payments.
 * - Deduct inventory after verified Razorpay capture.
 * - Prevent duplicate deductions per order.
 * - Record every stock sale.
 *
 * Legacy reservation methods are preserved for
 * existing orders and backward compatibility.
 */
public without sharing class GVInventoryService {

  public class InventoryException extends Exception {}

  // ==========================================
  // NEW: DIRECT PAYMENT STOCK DEDUCTION
  // ==========================================

  /**
   * TRUSTED INTERNAL METHOD ONLY.
   *
   * Must be invoked from verified payment finalization,
   * in the same transaction that confirms the order.
   *
   * This method does not verify Razorpay independently.
   */
  public static void deductOnPayment(Id orderId) {

    if (orderId == null)
      throw new InventoryException(
        'Order ID is required.'
      );

    // Serialize attempts to finalize the same order.
    Jewellery_Order__c orderRecord = [
      SELECT
        Id,
        Order_Status__c,
        Payment_Status__c
      FROM Jewellery_Order__c
      WHERE Id = :orderId
      WITH SYSTEM_MODE
      FOR UPDATE
    ];

    if (
      orderRecord.Order_Status__c != 'pending' ||
      orderRecord.Payment_Status__c != 'Pending'
    )
      throw new InventoryException(
        'Order is not awaiting payment finalization.'
      );

    // Prevent duplicate stock deduction.
    List<Inventory_Movement__c> existingSales = [
      SELECT Id
      FROM Inventory_Movement__c
      WHERE Jewellery_Order__c = :orderId
        AND Movement_Type__c = 'Sale'
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    if (!existingSales.isEmpty())
      throw new InventoryException(
        'Inventory already deducted or requires review.'
      );

    // Read products and quantities from the order.
    Map<Id, Decimal> quantities =
      new Map<Id, Decimal>();

    for (Jewellery_Order_Item__c line : [
      SELECT
        Jewellery_Product__c,
        Quantity__c
      FROM Jewellery_Order_Item__c
      WHERE Jewellery_Order__c = :orderId
      WITH SYSTEM_MODE
    ]) {

      validate(
        line.Jewellery_Product__c,
        line.Quantity__c
      );

      Id pid = line.Jewellery_Product__c;

      quantities.put(
        pid,
        (quantities.containsKey(pid)
          ? quantities.get(pid)
          : 0) + line.Quantity__c
      );
    }

    if (
      quantities.isEmpty() ||
      quantities.size() > 25
    )
      throw new InventoryException(
        'Invalid order items.'
      );

    // Lock products before changing stock.
    Map<Id, Jewellery_Product__c> products =
      lockProducts(quantities.keySet());

    List<Jewellery_Product__c> updates =
      new List<Jewellery_Product__c>();

    List<Inventory_Movement__c> movements =
      new List<Inventory_Movement__c>();

    for (Id pid : quantities.keySet()) {

      Jewellery_Product__c product =
        products.get(pid);

      Decimal qty = quantities.get(pid);

      Decimal beforeStock =
        zero(product.Stock_Quantity__c);

      Decimal legacyReserved =
        zero(product.Reserved_Quantity__c);

      // Existing legacy reservations still protect stock.
      if (
        product.Active__c != true ||
        beforeStock - legacyReserved < qty
      )
        throw new InventoryException(
          'Insufficient available stock for ' +
          product.Name
        );

      Decimal afterStock = beforeStock - qty;

      product.Stock_Quantity__c = afterStock;

      updates.add(product);

      movements.add(
        new Inventory_Movement__c(
          Jewellery_Product__c = pid,
          Jewellery_Order__c = orderId,
          Movement_Type__c = 'Sale',
          Quantity__c = qty,
          Stock_Before__c = beforeStock,
          Stock_After__c = afterStock,
          Movement_Date__c = System.now(),
          Reason__c = 'Verified Razorpay payment'
        )
      );
    }

    Savepoint sp = Database.setSavepoint();

    try {

      update as system updates;
      insert as system movements;

    } catch (Exception e) {

      Database.rollback(sp);
      throw e;
    }
  }

  // ==========================================
  // LEGACY: RESERVE ONE PRODUCT
  // ==========================================

  public static Id reserveStock(
    Id productId,
    Decimal quantity,
    Id orderId
  ) {

    return reserve(
      new Map<Id, Decimal>{
        productId => quantity
      },
      orderId
    ).get(productId);
  }

  // ==========================================
  // LEGACY: RESERVE INVENTORY
  // ==========================================

  public static Map<Id, Id> reserve(
    Map<Id, Decimal> quantities,
    Id orderId
  ) {

    if (
      quantities == null ||
      quantities.isEmpty() ||
      quantities.size() > 25
    )
      throw new InventoryException(
        'Choose between 1 and 25 products.'
      );

    for (Id pid : quantities.keySet())
      validate(pid, quantities.get(pid));

    Map<Id, Jewellery_Product__c> products =
      lockProducts(quantities.keySet());

    Map<Id, Stock_Reservation__c> existing =
      new Map<Id, Stock_Reservation__c>();

    if (orderId != null) {

      for (Stock_Reservation__c r : [
        SELECT
          Id,
          Jewellery_Product__c,
          Reserved_Quantity__c,
          Expires_At__c
        FROM Stock_Reservation__c
        WHERE Jewellery_Order__c = :orderId
          AND Reservation_Status__c = 'Active'
        WITH SYSTEM_MODE
        FOR UPDATE
      ]) {

        if (existing.containsKey(r.Jewellery_Product__c))
          throw new InventoryException(
            'Duplicate active reservation.'
          );

        existing.put(
          r.Jewellery_Product__c,
          r
        );
      }
    }

    List<Stock_Reservation__c> inserts =
      new List<Stock_Reservation__c>();

    List<Jewellery_Product__c> changes =
      new List<Jewellery_Product__c>();

    Map<Id, Id> result = new Map<Id, Id>();

    for (Id pid : quantities.keySet()) {

      Decimal qty = quantities.get(pid);
      Jewellery_Product__c product = products.get(pid);

      if (existing.containsKey(pid)) {

        Stock_Reservation__c r =
          existing.get(pid);

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
        zero(product.Stock_Quantity__c) -
        zero(product.Reserved_Quantity__c) < qty
      )
        throw new InventoryException(
          'Insufficient available stock for ' +
          product.Name
        );

      product.Reserved_Quantity__c =
        zero(product.Reserved_Quantity__c) + qty;

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

    Savepoint sp = Database.setSavepoint();

    try {
      update as system changes;
      insert as system inserts;
    } catch (Exception e) {
      Database.rollback(sp);
      throw e;
    }

    for (Stock_Reservation__c r : inserts)
      result.put(r.Jewellery_Product__c, r.Id);

    return result;
  }

  // ==========================================
  // LEGACY: COMMIT RESERVATION
  // ==========================================

  public static void commitReservation(
    Id reservationId
  ) {
    change(
      new Set<Id>{ reservationId },
      true
    );
  }

  // ==========================================
  // LEGACY: RELEASE RESERVATION
  // ==========================================

  public static void releaseReservation(
    Id reservationId
  ) {
    change(
      new Set<Id>{ reservationId },
      false
    );
  }

  // ==========================================
  // LEGACY: CHANGE RESERVATION
  // ==========================================

  public static void change(
    Set<Id> ids,
    Boolean commitStock
  ) {

    if (
      ids == null ||
      ids.isEmpty() ||
      ids.contains(null)
    )
      throw new InventoryException(
        'Reservation ID is required.'
      );

    Set<Id> pids = new Set<Id>();

    for (Stock_Reservation__c r : [
      SELECT Jewellery_Product__c
      FROM Stock_Reservation__c
      WHERE Id IN :ids
      WITH SYSTEM_MODE
    ])
      pids.add(r.Jewellery_Product__c);

    if (pids.isEmpty())
      throw new InventoryException(
        'Reservation not found.'
      );

    Map<Id, Jewellery_Product__c> products =
      lockProducts(pids);

    List<Stock_Reservation__c> changes =
      new List<Stock_Reservation__c>();

    List<Inventory_Movement__c> moves =
      new List<Inventory_Movement__c>();

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
      throw new InventoryException(
        'Reservation not found.'
      );

    for (Stock_Reservation__c r : rows) {

      if (
        commitStock &&
        r.Reservation_Status__c == 'Committed'
      )
        continue;

      if (
        !commitStock &&
        new Set<String>{
          'Released',
          'Release',
          'Expired'
        }.contains(r.Reservation_Status__c)
      )
        continue;

      if (r.Reservation_Status__c != 'Active')
        throw new InventoryException(
          'Reservation is not active.'
        );

      if (
        commitStock &&
        (
          r.Expires_At__c == null ||
          r.Expires_At__c <= System.now()
        )
      )
        throw new InventoryException(
          'Reservation expired; payment requires reconciliation.'
        );

      validate(
        r.Jewellery_Product__c,
        r.Reserved_Quantity__c
      );

      Jewellery_Product__c product =
        products.get(r.Jewellery_Product__c);

      Decimal qty = r.Reserved_Quantity__c;

      if (
        zero(product.Reserved_Quantity__c) < qty ||
        (
          commitStock &&
          zero(product.Stock_Quantity__c) < qty
        )
      )
        throw new InventoryException(
          'Inventory quantities are inconsistent.'
        );

      Decimal before =
        zero(product.Stock_Quantity__c);

      product.Reserved_Quantity__c =
        zero(product.Reserved_Quantity__c) - qty;

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

        r.Reservation_Status__c =
          r.Expires_At__c != null &&
          r.Expires_At__c <= System.now()
            ? 'Expired'
            : 'Released';

        r.Released_At__c = System.now();
      }

      dirty.add(product.Id);
      changes.add(r);
    }

    List<Jewellery_Product__c> productChanges =
      new List<Jewellery_Product__c>();

    for (Id pid : dirty)
      productChanges.add(products.get(pid));

    Savepoint sp = Database.setSavepoint();

    try {

      update as system productChanges;
      update as system changes;
      insert as system moves;

    } catch (Exception e) {

      Database.rollback(sp);
      throw e;
    }
  }

  // ==========================================
  // LOCK PRODUCTS
  // ==========================================

  private static Map<Id, Jewellery_Product__c>
    lockProducts(Set<Id> ids) {

    Map<Id, Jewellery_Product__c> result =
      new Map<Id, Jewellery_Product__c>([
        SELECT
          Id,
          Name,
          Active__c,
          Stock_Quantity__c,
          Reserved_Quantity__c
        FROM Jewellery_Product__c
        WHERE Id IN :ids
        WITH SYSTEM_MODE
        FOR UPDATE
      ]);

    if (result.size() != ids.size())
      throw new InventoryException(
        'Product not found.'
      );

    return result;
  }

  // ==========================================
  // VALIDATE QUANTITY
  // ==========================================

  private static void validate(
    Id pid,
    Decimal qty
  ) {

    if (
      pid == null ||
      qty == null ||
      qty <= 0 ||
      qty != qty.setScale(0)
    )
      throw new InventoryException(
        'Invalid product or quantity.'
      );
  }

  // ==========================================
  // NULL-SAFE DECIMAL
  // ==========================================

  private static Decimal zero(Decimal value) {
    return value == null ? 0 : value;
  }
}
