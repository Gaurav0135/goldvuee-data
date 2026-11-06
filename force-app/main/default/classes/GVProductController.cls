/**
 * GoldVuee | Product Catalogue Backend
 *
 * Purpose:
 * Supplies jewellery product data to the Experience Cloud
 * storefront through Lightning Web Components.
 *
 * Features:
 * 1. Retrieve active products.
 * 2. Filter products by jewellery category.
 * 3. Search products by name.
 * 4. Return pricing, images and availability.
 *
 * Security:
 * Uses sharing rules and user-mode queries to respect
 * Salesforce object, field and record permissions.
 */
public with sharing class GVProductController {

    /**
     * Fetches active jewellery products for the storefront.
     *
     * @param categoryId Optional Jewellery Category record ID.
     * @param searchTerm Optional product name search.
     * @return A list of matching jewellery products.
     */
    @AuraEnabled(cacheable=true)
    public static List<Jewellery_Product__c> getProducts(
        Id categoryId,
        String searchTerm
    ) {
        // Only active products should appear in the catalogue.
        // The maximum result count keeps storefront queries bounded.
        Integer maxProducts = 100;

        // Normalize search input to avoid unnecessary filtering.
        String searchPattern = String.isBlank(searchTerm)
            ? null
            : '%' + searchTerm.trim() + '%';

        // User-mode SOQL enforces the current user's permissions.
        // Static bind variables protect against SOQL injection.
        if (categoryId != null && searchPattern != null) {
            return [
                SELECT Id, Name, category__c, category__r.Name,
                       description__c, price__c, discount_price__c,
                       main_image_url__c, availability_status__c,
                       featured_product__c, bestseller__c,
                       new_arrival__c
                FROM Jewellery_Product__c
                WHERE active__c = true
                  AND category__c = :categoryId
                  AND Name LIKE :searchPattern
                WITH USER_MODE
                ORDER BY Name
                LIMIT :maxProducts
            ];
        }

        if (categoryId != null) {
            return [
                SELECT Id, Name, category__c, category__r.Name,
                       description__c, price__c, discount_price__c,
                       main_image_url__c, availability_status__c,
                       featured_product__c, bestseller__c,
                       new_arrival__c
                FROM Jewellery_Product__c
                WHERE active__c = true
                  AND category__c = :categoryId
                WITH USER_MODE
                ORDER BY Name
                LIMIT :maxProducts
            ];
        }

        if (searchPattern != null) {
            return [
                SELECT Id, Name, category__c, category__r.Name,
                       description__c, price__c, discount_price__c,
                       main_image_url__c, availability_status__c,
                       featured_product__c, bestseller__c,
                       new_arrival__c
                FROM Jewellery_Product__c
                WHERE active__c = true
                  AND Name LIKE :searchPattern
                WITH USER_MODE
                ORDER BY Name
                LIMIT :maxProducts
            ];
        }

        // Default: show all active products.
        return [
            SELECT Id, Name, category__c, category__r.Name,
                   description__c, price__c, discount_price__c,
                   main_image_url__c, availability_status__c,
                   featured_product__c, bestseller__c,
                   new_arrival__c
            FROM Jewellery_Product__c
            WHERE active__c = true
            WITH USER_MODE
            ORDER BY Name
            LIMIT :maxProducts
        ];
    }
}
