public with sharing class GVNewArrivalsController {

    public class ProductInfo {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String category;
        @AuraEnabled public Decimal price;
        @AuraEnabled public Decimal discountPrice;
        @AuraEnabled public Decimal availableQuantity;
        @AuraEnabled public Datetime createdDate;
    }

    @AuraEnabled(cacheable=true)
    public static List<ProductInfo> getNewArrivals() {

        List<ProductInfo> results = new List<ProductInfo>();

        List<Jewellery_Product__c> products = [
            SELECT Id, Name, Category__c, Category__r.Name,
                Price__c, Discount_Price__c,
                Available_Quantity__c, CreatedDate
            FROM Jewellery_Product__c
            WHERE Active__c = true
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 24
        ];

        for (Jewellery_Product__c product : products) {
            ProductInfo item = new ProductInfo();

            item.id = product.Id;
            item.name = product.Name;
            item.category = product.Category__r != null
                ? product.Category__r.Name
                : 'Uncategorized';
            item.price = product.Price__c;
            item.discountPrice = product.Discount_Price__c;
            item.availableQuantity = product.Available_Quantity__c;
            item.createdDate = product.CreatedDate;

            results.add(item);
        }

        return results;
    }
}