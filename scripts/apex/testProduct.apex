
/**
 * GOLDVUEE | PRODUCT DETAILS TEST
 *
 * Tests getProductById() using an existing
 * active jewellery product.
 *
 * No records are created or modified.
 */

// Find one active product.
List<Jewellery_Product__c> samples = [
    SELECT Id, Name
    FROM Jewellery_Product__c
    WHERE Active__c = true
    ORDER BY Name
    LIMIT 1
];

if (!samples.isEmpty()) {

    // Retrieve the product through our new controller method.
    Jewellery_Product__c product =
        GVProductController.getProductById(
            samples[0].Id
        );

    System.debug('PRODUCT NAME: ' + product.Name);
    System.debug('PRODUCT SKU: ' + product.SKU__c);
    System.debug('PRODUCT PRICE: ' + product.Price__c);
    System.debug('PRODUCT METAL: ' + product.Metal_Type__c);
    System.debug('PRODUCT PURITY: ' + product.Purity__c);
    System.debug('PRODUCT WEIGHT: ' + product.Weight__c);
    System.debug('PRODUCT STOCK: ' + product.Stock_Quantity__c);
    System.debug('PRODUCT STATUS: ' + product.Availability_Status__c);

} else {
    System.debug('No active products found for testing.');
}
