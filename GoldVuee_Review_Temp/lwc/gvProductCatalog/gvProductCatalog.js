
import { LightningElement, wire } from 'lwc';
import getProducts from '@salesforce/apex/GVProductController.getProducts';

/**
 * ============================================================
 * GOLDVUEE | PRODUCT CATALOGUE
 * ============================================================
 *
 * Features:
 * 1. Load active jewellery products from Salesforce.
 * 2. Filter by Metal Type.
 * 3. Filter by Jewellery Category.
 * 4. Filter by Shop For (Gender).
 * 5. Filter by Purity.
 * 6. Filter by Stone Type.
 * 7. Filter by Collections.
 * 8. Filter by Availability.
 * 9. Filter by Budget.
 * 10. Search by product name or category.
 * 11. Sort by featured, price or name.
 * 12. Clear all filters.
 * 13. Navigate to individual Product Details pages.
 *
 * Filtering:
 * OR within a filter group.
 * AND between different filter groups.
 *
 * Backend:
 * GVProductController.getProducts()
 *
 * ============================================================
 */

const FALLBACK_IMAGE =
    'https://placehold.co/800x800/f8f3ee/6b1834?text=GoldVuee';

export default class GvProductCatalog extends LightningElement {

    // ==================================================
    // 1. PRODUCT DATA AND GENERAL UI STATE
    // ==================================================

    products = [];
    searchTerm = '';
    sortBy = 'featured';
    isLoading = true;
    errorMessage = '';

    showFilters = true;

    // Only one filter accordion is open at a time.
    openSection = 'metal';

    // ==================================================
    // 2. SELECTED FILTER VALUES
    // ==================================================

    selectedMetals = [];
    selectedCategories = [];
    selectedGenders = [];
    selectedPurities = [];
    selectedStones = [];
    selectedCollections = [];
    selectedAvailability = [];

    maxBudget = 0;
    budgetMaximum = 0;

    // ==================================================
    // 3. CURRENCY FORMATTER
    // ==================================================

    currencyFormatter = new Intl.NumberFormat('en-IN', {
        style: 'currency',
        currency: 'INR',
        maximumFractionDigits: 0
    });

    // ==================================================
    // 4. LOAD PRODUCTS FROM SALESFORCE
    // ==================================================

    @wire(getProducts, {
        categoryId: null,
        searchTerm: null
    })
    wiredProducts({ data, error }) {

        if (data) {
            this.errorMessage = '';

            this.products = data.map(record => {

                const originalPrice =
                    Number(record.Price__c || 0);

                const discountPrice =
                    Number(record.Discount_Price__c || 0);

                const hasDiscount =
                    discountPrice > 0 &&
                    discountPrice < originalPrice;

                const sellingPrice = hasDiscount
                    ? discountPrice
                    : originalPrice;

                return {

                    // Salesforce product record ID.
                    id: record.Id,

                    // ======================================
                    // NEW: PRODUCT DETAILS NAVIGATION
                    // ======================================
                    // Each product receives its own URL.
                    //
                    // Example:
                    // /goldvuee/product-details
                    //     ?c__productId=RECORD_ID
                    //
                    // The Product Details LWC reads this ID
                    // using CurrentPageReference.
                    //
                    // encodeURIComponent safely encodes
                    // the product ID for the URL.

                    detailsUrl:
                        '/goldvuee/product-details?c__productId=' +
                        encodeURIComponent(record.Id),

                    // PRODUCT BASIC INFORMATION
                    name: record.Name,

                    category:
                        record.Category__r?.Name || 'Jewellery',

                    // PRODUCT FILTER FIELDS
                    metal: record.Metal_Type__c || '',
                    gender: record.Gender__c || '',
                    purity: record.Purity__c || '',
                    stone: record.Stone_Type__c || '',

                    // PRODUCT IMAGE
                    image:
                        record.Main_Image_URL__c ||
                        FALLBACK_IMAGE,

                    // INVENTORY AVAILABILITY
                    availability:
                        record.Availability_Status__c || '',

                    // COLLECTION BADGES
                    isNew:
                        record.New_Arrival__c === true,

                    bestseller:
                        record.Bestseller__c === true,

                    featured:
                        record.Featured_Product__c === true,

                    // PRODUCT PRICING
                    sellingPrice,
                    hasDiscount,

                    formattedPrice:
                        this.currencyFormatter.format(
                            sellingPrice
                        ),

                    formattedOriginalPrice:
                        this.currencyFormatter.format(
                            originalPrice
                        )
                };
            });

            // ==========================================
            // CALCULATE MAXIMUM BUDGET
            // ==========================================
            // Uses actual selling prices from Salesforce.

            const highestPrice = Math.max(
                0,
                ...this.products.map(
                    product => product.sellingPrice
                )
            );

            this.budgetMaximum = Math.max(
                1000,
                Math.ceil(highestPrice / 1000) * 1000
            );

            this.maxBudget = this.budgetMaximum;

            this.isLoading = false;

        } else if (error) {

            this.products = [];

            this.errorMessage =
                'Unable to load jewellery. Please try again later.';

            this.isLoading = false;

            console.error(
                'GoldVuee catalogue error:',
                error
            );
        }
    }

    // ==================================================
    // 5. SIDEBAR SHOW / HIDE
    // ==================================================

    toggleFilters() {
        this.showFilters = !this.showFilters;
    }

    get filterToggleLabel() {
        return this.showFilters
            ? 'Hide Filters'
            : 'Show Filters';
    }

    get catalogLayoutClass() {
        return this.showFilters
            ? 'catalog-layout'
            : 'catalog-layout filters-hidden';
    }

    // ==================================================
    // 6. ACCORDION CONTROLS
    // ==================================================

    toggleSection(event) {

        const section =
            event.currentTarget.dataset.section;

        this.openSection =
            this.openSection === section
                ? ''
                : section;
    }

    get metalOpen() {
        return this.openSection === 'metal';
    }

    get categoryOpen() {
        return this.openSection === 'category';
    }

    get genderOpen() {
        return this.openSection === 'gender';
    }

    get purityOpen() {
        return this.openSection === 'purity';
    }

    get stoneOpen() {
        return this.openSection === 'stone';
    }

    get collectionOpen() {
        return this.openSection === 'collection';
    }

    get availabilityOpen() {
        return this.openSection === 'availability';
    }

    get budgetOpen() {
        return this.openSection === 'budget';
    }

    // Accordion indicators.
    get metalArrow() {
        return this.metalOpen ? '−' : '+';
    }

    get categoryArrow() {
        return this.categoryOpen ? '−' : '+';
    }

    get genderArrow() {
        return this.genderOpen ? '−' : '+';
    }

    get purityArrow() {
        return this.purityOpen ? '−' : '+';
    }

    get stoneArrow() {
        return this.stoneOpen ? '−' : '+';
    }

    get collectionArrow() {
        return this.collectionOpen ? '−' : '+';
    }

    get availabilityArrow() {
        return this.availabilityOpen ? '−' : '+';
    }

    get budgetArrow() {
        return this.budgetOpen ? '−' : '+';
    }

    // ==================================================
    // 7. BUILD FILTER OPTIONS FROM SALESFORCE DATA
    // ==================================================
    // Only values used by retrieved products are shown.
    // This prevents irrelevant options from appearing.

    buildOptions(fieldName, selectedValues) {

        const values = [
            ...new Set(
                this.products
                    .map(product => product[fieldName])
                    .filter(Boolean)
            )
        ].sort((a, b) => a.localeCompare(b));

        return values.map(value => ({
            value,

            label: this.getDisplayLabel(
                fieldName,
                value
            ),

            checked: selectedValues.includes(value)
        }));
    }

    // Display friendly labels without changing
    // Salesforce picklist API values.

    getDisplayLabel(fieldName, value) {

        if (fieldName === 'gender') {

            const genderLabels = {
                women: 'Women',
                Men: 'Men',
                Kid: 'Kids'
            };

            return genderLabels[value] || value;
        }

        return value;
    }

    get metalOptions() {
        return this.buildOptions(
            'metal',
            this.selectedMetals
        );
    }

    get categoryOptions() {
        return this.buildOptions(
            'category',
            this.selectedCategories
        );
    }

    get genderOptions() {
        return this.buildOptions(
            'gender',
            this.selectedGenders
        );
    }

    get purityOptions() {
        return this.buildOptions(
            'purity',
            this.selectedPurities
        );
    }

    get stoneOptions() {
        return this.buildOptions(
            'stone',
            this.selectedStones
        );
    }

    // ==================================================
    // 8. COLLECTION FILTER OPTIONS
    // ==================================================
    // Uses existing Salesforce checkbox fields.

    get collectionOptions() {

        return [
            {
                value: 'new',
                label: 'New Arrivals',
                checked:
                    this.selectedCollections.includes('new')
            },
            {
                value: 'bestseller',
                label: 'Bestsellers',
                checked:
                    this.selectedCollections.includes(
                        'bestseller'
                    )
            },
            {
                value: 'featured',
                label: 'GoldVuee Signature Picks',
                checked:
                    this.selectedCollections.includes(
                        'featured'
                    )
            }
        ];
    }

    // ==================================================
    // 9. AVAILABILITY FILTER OPTIONS
    // ==================================================

    get availabilityOptions() {
        return this.buildOptions(
            'availability',
            this.selectedAvailability
        );
    }

    // ==================================================
    // 10. HANDLE CHECKBOX FILTER CHANGES
    // ==================================================

    handleFilterChange(event) {

        const group = event.target.dataset.group;
        const value = event.target.value;
        const checked = event.target.checked;

        const propertyMap = {
            metal: 'selectedMetals',
            category: 'selectedCategories',
            gender: 'selectedGenders',
            purity: 'selectedPurities',
            stone: 'selectedStones',
            collection: 'selectedCollections',
            availability: 'selectedAvailability'
        };

        const property = propertyMap[group];

        if (!property) {
            return;
        }

        const current = this[property];

        this[property] = checked
            ? [...current, value]
            : current.filter(item => item !== value);
    }

    // ==================================================
    // 11. BUDGET FILTER
    // ==================================================

    handleBudgetChange(event) {

        this.maxBudget =
            Number(event.target.value);
    }

    get formattedMaxBudget() {
        return this.currencyFormatter.format(
            this.maxBudget
        );
    }

    // ==================================================
    // 12. CLEAR ALL FILTERS
    // ==================================================

    clearFilters() {

        this.selectedMetals = [];
        this.selectedCategories = [];
        this.selectedGenders = [];
        this.selectedPurities = [];
        this.selectedStones = [];
        this.selectedCollections = [];
        this.selectedAvailability = [];

        this.maxBudget = this.budgetMaximum;

        this.searchTerm = '';
        this.sortBy = 'featured';
    }

    // ==================================================
    // 13. SEARCH AND SORT HANDLERS
    // ==================================================

    handleSearch(event) {
        this.searchTerm =
            event.target.value;
    }

    handleSortChange(event) {
        this.sortBy =
            event.target.value;
    }

    // ==================================================
    // 14. APPLY ALL FILTERS
    // ==================================================
    // OR within a group.
    // AND between different groups.

    get filteredProducts() {

        const term =
            this.searchTerm.trim().toLowerCase();

        const matching = this.products.filter(
            product => {

                // Search by product name or category.
                const matchesSearch =
                    !term ||
                    product.name
                        .toLowerCase()
                        .includes(term) ||
                    product.category
                        .toLowerCase()
                        .includes(term);

                // Metal Type.
                const matchesMetal =
                    !this.selectedMetals.length ||
                    this.selectedMetals.includes(
                        product.metal
                    );

                // Jewellery Category.
                const matchesCategory =
                    !this.selectedCategories.length ||
                    this.selectedCategories.includes(
                        product.category
                    );

                // Shop For.
                const matchesGender =
                    !this.selectedGenders.length ||
                    this.selectedGenders.includes(
                        product.gender
                    );

                // Purity.
                const matchesPurity =
                    !this.selectedPurities.length ||
                    this.selectedPurities.includes(
                        product.purity
                    );

                // Stone Type.
                const matchesStone =
                    !this.selectedStones.length ||
                    this.selectedStones.includes(
                        product.stone
                    );

                // Availability.
                const matchesAvailability =
                    !this.selectedAvailability.length ||
                    this.selectedAvailability.includes(
                        product.availability
                    );

                // Maximum selling price.
                const matchesBudget =
                    product.sellingPrice <= this.maxBudget;

                // Collections.
                // Match any selected collection type.
                const matchesCollections =
                    !this.selectedCollections.length ||
                    this.selectedCollections.some(
                        collection => {

                            if (collection === 'new') {
                                return product.isNew;
                            }

                            if (
                                collection === 'bestseller'
                            ) {
                                return product.bestseller;
                            }

                            if (
                                collection === 'featured'
                            ) {
                                return product.featured;
                            }

                            return false;
                        }
                    );

                // Product must satisfy all active groups.
                return (
                    matchesSearch &&
                    matchesMetal &&
                    matchesCategory &&
                    matchesGender &&
                    matchesPurity &&
                    matchesStone &&
                    matchesAvailability &&
                    matchesBudget &&
                    matchesCollections
                );
            }
        );

        // Sort a copy to avoid mutating product data.
        return [...matching].sort((a, b) => {

            if (this.sortBy === 'priceLow') {
                return (
                    a.sellingPrice - b.sellingPrice
                );
            }

            if (this.sortBy === 'priceHigh') {
                return (
                    b.sellingPrice - a.sellingPrice
                );
            }

            if (this.sortBy === 'name') {
                return a.name.localeCompare(
                    b.name
                );
            }

            // Default: featured products first.
            return (
                Number(b.featured) -
                Number(a.featured)
            );
        });
    }

    // ==================================================
    // 15. PRODUCT GRID HELPERS
    // ==================================================

    get productCount() {
        return this.filteredProducts.length;
    }

    get hasProducts() {
        return this.filteredProducts.length > 0;
    }
}
