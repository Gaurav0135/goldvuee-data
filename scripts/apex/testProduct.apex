
/*
 * GoldVuee | Product Catalogue Smoke Test
 *
 * Calls the product controller without filters
 * and displays the returned products in debug logs.
 */

List<Jewellery_Product__c> products =
    GVProductController.getProducts(null, null);

System.debug('Total active products: ' + products.size());

for (Jewellery_Product__c product : products) {
    System.debug(
        'Product: ' + product.Name +
        ' | Price: ' + product.price__c +
        ' | Category: ' +
        (product.category__r != null
            ? product.category__r.Name
            : 'Uncategorized')
    );
}
