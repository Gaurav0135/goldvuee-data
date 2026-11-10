
/**
 * ============================================================
 * GOLDVUEE | PRODUCT CONTROLLER
 * ============================================================
 *
 * Used by:
 * 1. gvProductCatalog  - Jewellery Collections page
 * 2. gvProductDetails  - Individual Product Details page
 *
 * Features:
 * - Retrieve active jewellery products.
 * - Filter by category and search term.
 * - Return data for all eight catalogue filters.
 * - Retrieve one product using its Salesforce record ID.
 * - Return product specifications and inventory details.
 *
 * Security:
 * - with sharing enforces Salesforce sharing rules.
 * - AccessLevel.USER_MODE enforces user permissions.
 * - SOQL bind variables protect against injection.
 *
 * ============================================================
 */
public with sharing class GVProductController {

    // ========================================================
    // METHOD 1: GET ALL PRODUCTS
    // ========================================================
    // Existing method used by gvProductCatalog.
    // Preserved to avoid breaking the Collections page.
    // ========================================================

    @AuraEnabled(cacheable=true)
    public static List<Jewellery_Product__c> getProducts(
        Id categoryId,
        String searchTerm
    ) {

        // Maximum number of products returned.
        Integer maxProducts = 100;

        // Prepare optional product-name search.
        String searchPattern = String.isBlank(searchTerm)
            ? null
            : '%' + searchTerm.trim() + '%';

        // Retrieve product information and filter fields.
        String query =
            'SELECT ' +
            'Id, ' +
            'Name, ' +
            'Product_Code__c, ' +
            'SKU__c, ' +
            'Category__c, ' +
            'Category__r.Name, ' +
            'Description__c, ' +
            'Price__c, ' +
            'Discount_Price__c, ' +
            'Main_Image_URL__c, ' +
            'Availability_Status__c, ' +
            'Stock_Quantity__c, ' +
            'Metal_Type__c, ' +
            'Gender__c, ' +
            'Purity__c, ' +
            'Stone_Type__c, ' +
            'Featured_Product__c, ' +
            'Bestseller__c, ' +
            'New_Arrival__c ' +
            'FROM Jewellery_Product__c ' +
            'WHERE Active__c = true ';

        // Optional category filter.
        if (categoryId != null) {
            query += 'AND Category__c = :categoryId ';
        }

        // Optional search filter.
        if (searchPattern != null) {
            query += 'AND Name LIKE :searchPattern ';
        }

        // Sort products alphabetically.
        query +=
            'ORDER BY Name ASC ' +
            'LIMIT :maxProducts';

        // Named SOQL bind values.
        Map<String, Object> bindValues =
            new Map<String, Object>{
                'categoryId' => categoryId,
                'searchPattern' => searchPattern,
                'maxProducts' => maxProducts
            };

        // Execute using Salesforce user-mode security.
        List<Jewellery_Product__c> products =
            Database.queryWithBinds(
                query,
                bindValues,
                AccessLevel.USER_MODE
            );

        return products;
    }


    // ========================================================
    // METHOD 2: GET PRODUCT BY ID
    // ========================================================
    //
    // NEW METHOD
    //
    // Purpose:
    // Retrieve complete information for one jewellery item.
    //
    // Example:
    // Customer clicks "Antique Temple Gold Necklace".
    //
    // LWC sends the product's Salesforce record ID.
    //
    // Apex retrieves:
    // - Product name and description
    // - Product image
    // - Original and discounted price
    // - Metal type, purity, weight and stone type
    // - SKU and product code
    // - Stock quantity and availability
    // - Category and product badges
    //
    // Only active products are accessible.
    //
    // ========================================================

    @AuraEnabled(cacheable=true)
    public static Jewellery_Product__c getProductById(
        Id productId
    ) {

        // ----------------------------------------------------
        // 1. VALIDATE PRODUCT ID
        // ----------------------------------------------------
        // Prevent a query when no product ID is provided.

        if (productId == null) {
            throw new AuraHandledException(
                'A valid product ID is required.'
            );
        }


        // ----------------------------------------------------
        // 2. RETRIEVE PRODUCT DETAILS
        // ----------------------------------------------------
        // USER_MODE enforces object, field and record access.
        //
        // Active__c = true prevents inactive products
        // from appearing in the storefront.
        //
        // LIMIT 1 ensures a single product is returned.

        List<Jewellery_Product__c> products = [
            SELECT
                Id,
                Name,
                Product_Code__c,
                SKU__c,
                Category__c,
                Category__r.Name,
                Description__c,
                Price__c,
                Discount_Price__c,
                Main_Image_URL__c,
                Availability_Status__c,
                Stock_Quantity__c,
                Metal_Type__c,
                Gender__c,
                Purity__c,
                Stone_Type__c,
                Weight__c,
                Featured_Product__c,
                Bestseller__c,
                New_Arrival__c
            FROM Jewellery_Product__c
            WHERE
                Id = :productId
                AND Active__c = true
            WITH USER_MODE
            LIMIT 1
        ];


        // ----------------------------------------------------
        // 3. HANDLE PRODUCT NOT FOUND
        // ----------------------------------------------------
        // Also handles products that are inactive or
        // inaccessible to the current user.

        if (products.isEmpty()) {
            throw new AuraHandledException(
                'This jewellery product is unavailable.'
            );
        }


        // ----------------------------------------------------
        // 4. RETURN PRODUCT TO LIGHTNING WEB COMPONENT
        // ----------------------------------------------------

        return products[0];
    }
}
