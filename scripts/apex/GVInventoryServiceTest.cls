
@IsTest
private class GVInventoryServiceTest {

    @TestSetup
    static void setupData() {
        Jewellery_Product__c product =
            new Jewellery_Product__c(
                Name = 'GV Inventory Test Necklace',
                SKU__c = 'GV-INV-TEST-001',
                Product_Code__c = 'GV-INV-001',
                Price__c = 1000,
                Stock_Quantity__c = 10,
                Reserved_Quantity__c = 0,
                Active__c = true
            );

        insert product;
    }

    @IsTest
    static void testSuccessfulReservation() {
        Jewellery_Product__c product = [
            SELECT Id
            FROM Jewellery_Product__c
            LIMIT 1
        ];

        Test.startTest();

        Id reservationId = GVInventoryService.reserveStock(
            product.Id,
            3,
            null
        );

        Test.stopTest();

        Jewellery_Product__c updatedProduct = [
            SELECT Stock_Quantity__c,
                   Reserved_Quantity__c,
                   Available_Quantity__c
            FROM Jewellery_Product__c
            WHERE Id = :product.Id
        ];

        System.assertNotEquals(
            null,
            reservationId,
            'Reservation should be created.'
        );

        System.assertEquals(
            10,
            updatedProduct.Stock_Quantity__c,
            'Physical stock must remain unchanged.'
        );

        System.assertEquals(
            3,
            updatedProduct.Reserved_Quantity__c,
            'Reserved stock should increase.'
        );

        System.assertEquals(
            7,
            updatedProduct.Available_Quantity__c,
            'Available stock should decrease.'
        );

        Stock_Reservation__c reservation = [
            SELECT Reservation_Status__c,
                   Reserved_Quantity__c,
                   Jewellery_Product__c,
                   Expires_At__c
            FROM Stock_Reservation__c
            WHERE Id = :reservationId
        ];

        System.assertEquals(
            'Active',
            reservation.Reservation_Status__c
        );

        System.assertEquals(
            3,
            reservation.Reserved_Quantity__c
        );

        System.assertNotEquals(
            null,
            reservation.Expires_At__c
        );
    }

    @IsTest
    static void testInsufficientStock() {
        Jewellery_Product__c product = [
            SELECT Id
            FROM Jewellery_Product__c
            LIMIT 1
        ];

        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            GVInventoryService.reserveStock(
                product.Id,
                20,
                null
            );
        } catch (GVInventoryService.InventoryException e) {
            exceptionThrown = true;
        }

        Test.stopTest();

        System.assert(
            exceptionThrown,
            'Reservation exceeding stock must fail.'
        );

        Jewellery_Product__c updatedProduct = [
            SELECT Reserved_Quantity__c
            FROM Jewellery_Product__c
            WHERE Id = :product.Id
        ];

        System.assertEquals(
            0,
            updatedProduct.Reserved_Quantity__c,
            'Failed reservation must not change stock.'
        );
    }

    @IsTest
    static void testInvalidQuantity() {
        Jewellery_Product__c product = [
            SELECT Id
            FROM Jewellery_Product__c
            LIMIT 1
        ];

        Boolean exceptionThrown = false;

        try {
            GVInventoryService.reserveStock(
                product.Id,
                -1,
                null
            );
        } catch (GVInventoryService.InventoryException e) {
            exceptionThrown = true;
        }

        System.assert(
            exceptionThrown,
            'Negative reservation quantity must fail.'
        );
    }

    @IsTest
    static void testInactiveProduct() {
        Jewellery_Product__c product = [
            SELECT Id, Active__c
            FROM Jewellery_Product__c
            LIMIT 1
        ];

        product.Active__c = false;
        update product;

        Boolean exceptionThrown = false;

        try {
            GVInventoryService.reserveStock(
                product.Id,
                1,
                null
            );
        } catch (GVInventoryService.InventoryException e) {
            exceptionThrown = true;
        }

        System.assert(
            exceptionThrown,
            'Inactive product reservation must fail.'
        );
    }
}
