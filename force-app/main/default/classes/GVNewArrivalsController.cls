public with sharing class GVNewArrivalsController {
    public class ProductInfo {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String category;
        @AuraEnabled public Decimal price;
        @AuraEnabled public Decimal discountPrice;
        @AuraEnabled public Decimal availableQuantity;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public String imageUrl;
        @AuraEnabled public String metal;
        @AuraEnabled public String gender;
        @AuraEnabled public String purity;
        @AuraEnabled public String stone;
        @AuraEnabled public Boolean featured;
        @AuraEnabled public Boolean bestseller;
        @AuraEnabled public Boolean isNew;
    }

    @AuraEnabled(cacheable=true)
    public static List<ProductInfo> getNewArrivals() {
        List<ProductInfo> results = new List<ProductInfo>();
        for (Jewellery_Product__c product : [
            SELECT Id, Name, Category__r.Name, Price__c, Discount_Price__c,
                Available_Quantity__c, CreatedDate, Main_Image_URL__c,
                Metal_Type__c, Gender__c, Purity__c, Stone_Type__c,
                Featured_Product__c, Bestseller__c, New_Arrival__c
            FROM Jewellery_Product__c
            WHERE Active__c = true AND New_Arrival__c = true
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 24
        ]) {
            ProductInfo item = new ProductInfo();
            item.id = product.Id;
            item.name = product.Name;
            item.category = product.Category__r != null ? product.Category__r.Name : 'Uncategorized';
            item.price = product.Price__c;
            item.discountPrice = product.Discount_Price__c;
            item.availableQuantity = product.Available_Quantity__c;
            item.createdDate = product.CreatedDate;
            item.imageUrl = product.Main_Image_URL__c;
            item.metal = product.Metal_Type__c;
            item.gender = product.Gender__c;
            item.purity = product.Purity__c;
            item.stone = product.Stone_Type__c;
            item.featured = product.Featured_Product__c;
            item.bestseller = product.Bestseller__c;
            item.isNew = product.New_Arrival__c;
            results.add(item);
        }
        return results;
    }
}
