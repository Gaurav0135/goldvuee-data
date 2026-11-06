import { LightningElement, wire } from 'lwc';
import getProducts from '@salesforce/apex/GVProductController.getProducts';

const FALLBACK_IMAGE =
    'https://placehold.co/800x800/f8f3ee/6b1834?text=GoldVuee';

export default class GvProductCatalog extends LightningElement {

    // ==========================================
    // 1. COMPONENT PROPERTIES
    // ==========================================

    products = [];
    searchTerm = '';
    isLoading = true;
    errorMessage = '';

    // ==========================================
    // 2. CURRENCY FORMATTER
    // ==========================================

    currencyFormatter = new Intl.NumberFormat('en-IN', {
        style: 'currency',
        currency: 'INR',
        maximumFractionDigits: 0
    });

    // ==========================================
    // 3. FETCH PRODUCTS FROM APEX
    // ==========================================

    @wire(getProducts, {
        categoryId: null,
        searchTerm: null
    })
    wiredProducts({ data, error }) {

        this.isLoading = false;

        if (data) {

            console.log(
                'GoldVuee Product Data:',
                JSON.stringify(data)
            );

            this.errorMessage = '';

            // Map Salesforce records to UI products
            this.products = data.map(record => {

                // Product prices
                const originalPrice = Number(
                    record.Price__c || 0
                );

                const discountPrice = Number(
                    record.Discount_Price__c || 0
                );

                // Validate discount
                const hasDiscount =
                    discountPrice > 0 &&
                    discountPrice < originalPrice;

                // Return formatted product object
                return {
                    id: record.Id,

                    name: record.Name,

                    category:
                        record.Category__r?.Name ||
                        'Jewellery',

                    image:
                        record.Main_Image_URL__c ||
                        FALLBACK_IMAGE,

                    availability:
                        record.Availability_Status__c || '',

                    isNew:
                        record.New_Arrival__c === true,

                    hasDiscount: hasDiscount,

                    formattedPrice:
                        this.currencyFormatter.format(
                            hasDiscount
                                ? discountPrice
                                : originalPrice
                        ),

                    formattedOriginalPrice:
                        this.currencyFormatter.format(
                            originalPrice
                        )
                };

            });

        } else if (error) {

            this.products = [];

            this.errorMessage =
                'Unable to load jewellery. Please try again later.';

            console.error(
                'GoldVuee catalogue error:',
                error
            );
        }
    }

    // ==========================================
    // 4. SEARCH HANDLER
    // ==========================================

    handleSearch(event) {
        this.searchTerm = event.target.value;
    }

    // ==========================================
    // 5. FILTER PRODUCTS
    // ==========================================

    get filteredProducts() {

        const term = this.searchTerm
            .trim()
            .toLowerCase();

        if (!term) {
            return this.products;
        }

        return this.products.filter(product =>
            product.name.toLowerCase().includes(term) ||
            product.category.toLowerCase().includes(term)
        );
    }

    // ==========================================
    // 6. PRODUCT COUNT
    // ==========================================

    get productCount() {
        return this.filteredProducts.length;
    }

    // ==========================================
    // 7. PRODUCT AVAILABILITY
    // ==========================================

    get hasProducts() {
        return this.filteredProducts.length > 0;
    }
}
