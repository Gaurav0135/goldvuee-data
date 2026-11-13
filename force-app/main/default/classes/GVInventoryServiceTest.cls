@IsTest
private class GVInventoryServiceTest {
  @TestSetup
  static void setupData() {
    Jewellery_Category__c category = new Jewellery_Category__c(
      Name = 'GV Inventory Test Category'
    );
    insert category;

    Jewellery_Product__c product = new Jewellery_Product__c(
      Name = 'GV Inventory Test Necklace',
      SKU__c = 'GV-INV-TEST-001',
      Product_Code__c = 'GV-INV-001',
      Category__c = category.Id,
      Weight__c = 10.000,
      Price__c = 1000,
      Stock_Quantity__c = 10,
      Reserved_Quantity__c = 0,
      Active__c = true
    );

    insert product;
  }

  private static Jewellery_Product__c getProduct() {
    return [
      SELECT
        Id,
        Name,
        Active__c,
        Stock_Quantity__c,
        Reserved_Quantity__c,
        Available_Quantity__c
      FROM Jewellery_Product__c
      WHERE SKU__c = 'GV-INV-TEST-001'
      LIMIT 1
    ];
  }

  // TEST 1: Successful reservation
  @IsTest
  static void testSuccessfulReservation() {
    Jewellery_Product__c product = getProduct();

    Test.startTest();
    Id reservationId = GVInventoryService.reserveStock(product.Id, 3, null);
    Test.stopTest();

    Jewellery_Product__c updatedProduct = getProduct();

    System.assertNotEquals(null, reservationId);
    System.assertEquals(10, updatedProduct.Stock_Quantity__c);
    System.assertEquals(3, updatedProduct.Reserved_Quantity__c);
    System.assertEquals(7, updatedProduct.Available_Quantity__c);

    Stock_Reservation__c reservation = [
      SELECT Reservation_Status__c, Reserved_Quantity__c, Expires_At__c
      FROM Stock_Reservation__c
      WHERE Id = :reservationId
    ];

    System.assertEquals('Active', reservation.Reservation_Status__c);
    System.assertNotEquals(null, reservation.Expires_At__c);
  }

  // TEST 2: Insufficient stock
  @IsTest
  static void testInsufficientStock() {
    Jewellery_Product__c product = getProduct();
    Boolean failed = false;

    Test.startTest();
    try {
      GVInventoryService.reserveStock(product.Id, 20, null);
    } catch (GVInventoryService.InventoryException e) {
      failed = true;
    }
    Test.stopTest();

    System.assert(failed, 'Reservation should fail.');
    System.assertEquals(0, getProduct().Reserved_Quantity__c);
  }

  // TEST 3: Invalid quantity
  @IsTest
  static void testInvalidQuantity() {
    Boolean failed = false;

    try {
      GVInventoryService.reserveStock(getProduct().Id, -1, null);
    } catch (GVInventoryService.InventoryException e) {
      failed = true;
    }

    System.assert(failed, 'Negative quantity must fail.');
  }

  // TEST 4: Inactive product
  @IsTest
  static void testInactiveProduct() {
    Jewellery_Product__c product = getProduct();
    product.Active__c = false;
    update product;

    Boolean failed = false;

    try {
      GVInventoryService.reserveStock(product.Id, 1, null);
    } catch (GVInventoryService.InventoryException e) {
      failed = true;
    }

    System.assert(failed, 'Inactive product must fail.');
  }

  // TEST 5: Successful stock commitment
  @IsTest
  static void testCommitReservation() {
    Id productId = getProduct().Id;

    Test.startTest();

    Id reservationId = GVInventoryService.reserveStock(productId, 2, null);

    GVInventoryService.commitReservation(reservationId);

    Test.stopTest();

    Jewellery_Product__c product = getProduct();

    System.assertEquals(8, product.Stock_Quantity__c);
    System.assertEquals(0, product.Reserved_Quantity__c);
    System.assertEquals(8, product.Available_Quantity__c);

    Stock_Reservation__c reservation = [
      SELECT Reservation_Status__c
      FROM Stock_Reservation__c
      WHERE Id = :reservationId
    ];

    System.assertEquals('Committed', reservation.Reservation_Status__c);

    List<Inventory_Movement__c> movements = [
      SELECT Movement_Type__c, Quantity__c, Stock_Before__c, Stock_After__c
      FROM Inventory_Movement__c
      WHERE Jewellery_Product__c = :productId
    ];

    System.assertEquals(1, movements.size());
    System.assertEquals('Sale', movements[0].Movement_Type__c);
    System.assertEquals(2, movements[0].Quantity__c);
    System.assertEquals(10, movements[0].Stock_Before__c);
    System.assertEquals(8, movements[0].Stock_After__c);
  }

  // TEST 6: Successful release
  @IsTest
  static void testReleaseReservation() {
    Id productId = getProduct().Id;

    Test.startTest();

    Id reservationId = GVInventoryService.reserveStock(productId, 4, null);

    GVInventoryService.releaseReservation(reservationId);

    Test.stopTest();

    Jewellery_Product__c product = getProduct();

    System.assertEquals(10, product.Stock_Quantity__c);
    System.assertEquals(0, product.Reserved_Quantity__c);
    System.assertEquals(10, product.Available_Quantity__c);

    Stock_Reservation__c reservation = [
      SELECT Reservation_Status__c, Released_At__c
      FROM Stock_Reservation__c
      WHERE Id = :reservationId
    ];

    System.assertEquals('Released', reservation.Reservation_Status__c);
    System.assertNotEquals(null, reservation.Released_At__c);
  }

  // TEST 7: Duplicate commitment prevention
  @IsTest
  static void testDuplicateCommit() {
    Id productId = getProduct().Id;

    Test.startTest();

    Id reservationId = GVInventoryService.reserveStock(productId, 2, null);

    GVInventoryService.commitReservation(reservationId);

    GVInventoryService.commitReservation(reservationId);

    Test.stopTest();

    System.assertEquals(8, getProduct().Stock_Quantity__c);

    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Inventory_Movement__c
        WHERE Jewellery_Product__c = :productId
      ]
    );
  }

  // TEST 8: Duplicate release prevention
  @IsTest
  static void testDuplicateRelease() {
    Id productId = getProduct().Id;

    Test.startTest();

    Id reservationId = GVInventoryService.reserveStock(productId, 3, null);

    GVInventoryService.releaseReservation(reservationId);

    GVInventoryService.releaseReservation(reservationId);

    Test.stopTest();

    System.assertEquals(0, getProduct().Reserved_Quantity__c);

    System.assertEquals(10, getProduct().Stock_Quantity__c);
  }

  // TEST 9: Committed reservations cannot be released
  @IsTest
  static void testCannotReleaseCommitted() {
    Id productId = getProduct().Id;

    Id reservationId = GVInventoryService.reserveStock(productId, 2, null);

    GVInventoryService.commitReservation(reservationId);

    Boolean failed = false;

    try {
      GVInventoryService.releaseReservation(reservationId);
    } catch (GVInventoryService.InventoryException e) {
      failed = true;
    }

    System.assert(failed, 'Committed reservation must not be released.');

    System.assertEquals(8, getProduct().Stock_Quantity__c);
  }

  // TEST 10: Expired reservation release
  @IsTest
  static void testExpiredReservation() {
    Id productId = getProduct().Id;

    Id reservationId = GVInventoryService.reserveStock(productId, 2, null);

    Stock_Reservation__c reservation = new Stock_Reservation__c(
      Id = reservationId,
      Expires_At__c = System.now().addMinutes(-1)
    );

    update reservation;

    Test.startTest();

    GVInventoryService.releaseReservation(reservationId);

    Test.stopTest();

    Stock_Reservation__c updatedReservation = [
      SELECT Reservation_Status__c
      FROM Stock_Reservation__c
      WHERE Id = :reservationId
    ];

    System.assertEquals('Expired', updatedReservation.Reservation_Status__c);

    System.assertEquals(0, getProduct().Reserved_Quantity__c);
  }
}