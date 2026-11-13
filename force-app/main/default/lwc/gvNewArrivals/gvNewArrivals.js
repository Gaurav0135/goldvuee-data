import { LightningElement, wire } from 'lwc';
import getNewArrivals from '@salesforce/apex/GVNewArrivalsController.getNewArrivals';

const FALLBACK_IMAGE = 'https://placehold.co/800x800/f8f3ee/6b1834?text=GoldVuee';
const FILTER_GROUPS = {
    metal: 'selectedMetals', category: 'selectedCategories',
    gender: 'selectedGenders', purity: 'selectedPurities',
    stone: 'selectedStones', collection: 'selectedCollections',
    availability: 'selectedAvailability'
};

export default class GvNewArrivals extends LightningElement {
    products = [];
    errorMessage = '';
    loading = true;
    searchTerm = '';
    sortBy = 'newest';
    showFilters = true;
    openSection = 'metal';
    selectedMetals = [];
    selectedCategories = [];
    selectedGenders = [];
    selectedPurities = [];
    selectedStones = [];
    selectedCollections = [];
    selectedAvailability = [];
    budgetMaximum = 1000;
    maxBudget = 1000;

    currencyFormatter = new Intl.NumberFormat('en-IN', {
        style: 'currency', currency: 'INR', maximumFractionDigits: 0
    });

    @wire(getNewArrivals)
    wiredProducts({ data, error }) {
        if (data) {
            this.products = data.map(p => {
                const price = Number(p.price || 0);
                const discountPrice = Number(p.discountPrice || 0);
                const hasDiscount = discountPrice > 0 && discountPrice < price;
                const sellingPrice = hasDiscount ? discountPrice : price;
                const inStock = Number(p.availableQuantity || 0) > 0;
                return {
                    ...p,
                    image: p.imageUrl || FALLBACK_IMAGE,
                    detailsUrl: '/goldvuee/product-details?c__productId=' + encodeURIComponent(p.id),
                    categoryLabel: p.category || 'Fine Jewellery',
                    metal: p.metal || '', gender: p.gender || '',
                    purity: p.purity || '', stone: p.stone || '',
                    availability: inStock ? 'In Stock' : 'Out of Stock',
                    inStock, hasDiscount, sellingPrice,
                    formattedPrice: this.currencyFormatter.format(sellingPrice),
                    formattedOriginalPrice: this.currencyFormatter.format(price),
                    dateValue: p.createdDate ? new Date(p.createdDate).getTime() : 0
                };
            });
            this.budgetMaximum = Math.max(1000, Math.ceil(Math.max(0, ...this.products.map(p => p.sellingPrice)) / 1000) * 1000);
            this.maxBudget = this.budgetMaximum;
            this.errorMessage = '';
        } else if (error) {
            this.products = [];
            this.errorMessage = error.body?.message || 'Unable to load new arrivals.';
        }
        this.loading = false;
    }

    get filterToggleLabel() { return this.showFilters ? 'Hide Filters' : 'Show Filters'; }
    get catalogLayoutClass() { return this.showFilters ? 'catalog-layout' : 'catalog-layout filters-hidden'; }
    toggleFilters() { this.showFilters = !this.showFilters; }
    toggleSection(event) {
        const section = event.currentTarget.dataset.section;
        this.openSection = this.openSection === section ? '' : section;
    }
    get metalOpen() { return this.openSection === 'metal'; }
    get categoryOpen() { return this.openSection === 'category'; }
    get genderOpen() { return this.openSection === 'gender'; }
    get purityOpen() { return this.openSection === 'purity'; }
    get stoneOpen() { return this.openSection === 'stone'; }
    get collectionOpen() { return this.openSection === 'collection'; }
    get availabilityOpen() { return this.openSection === 'availability'; }
    get budgetOpen() { return this.openSection === 'budget'; }
    get metalArrow() { return this.metalOpen ? '−' : '+'; }
    get categoryArrow() { return this.categoryOpen ? '−' : '+'; }
    get genderArrow() { return this.genderOpen ? '−' : '+'; }
    get purityArrow() { return this.purityOpen ? '−' : '+'; }
    get stoneArrow() { return this.stoneOpen ? '−' : '+'; }
    get collectionArrow() { return this.collectionOpen ? '−' : '+'; }
    get availabilityArrow() { return this.availabilityOpen ? '−' : '+'; }
    get budgetArrow() { return this.budgetOpen ? '−' : '+'; }

    buildOptions(field, selected) {
        return [...new Set(this.products.map(p => p[field]).filter(Boolean))]
            .sort((a, b) => a.localeCompare(b))
            .map(value => ({
                value,
                label: field === 'gender' ? ({ women: 'Women', Men: 'Men', Kid: 'Kids' }[value] || value) : value,
                checked: selected.includes(value)
            }));
    }
    get metalOptions() { return this.buildOptions('metal', this.selectedMetals); }
    get categoryOptions() { return this.buildOptions('category', this.selectedCategories); }
    get genderOptions() { return this.buildOptions('gender', this.selectedGenders); }
    get purityOptions() { return this.buildOptions('purity', this.selectedPurities); }
    get stoneOptions() { return this.buildOptions('stone', this.selectedStones); }
    get availabilityOptions() { return this.buildOptions('availability', this.selectedAvailability); }
    get collectionOptions() {
        return [
            { value: 'new', label: 'New Arrivals' },
            { value: 'featured', label: 'GoldVuee Signature Picks' },
            { value: 'bestseller', label: 'Bestsellers' }
        ].map(o => ({ ...o, checked: this.selectedCollections.includes(o.value) }));
    }
    get sortOptions() {
        return [
            { label: 'Newest First', value: 'newest' },
            { label: 'Price: Low to High', value: 'low' },
            { label: 'Price: High to Low', value: 'high' },
            { label: 'Name: A to Z', value: 'name' }
        ];
    }
    get formattedMaxBudget() { return this.currencyFormatter.format(this.maxBudget); }
    handleBudgetChange(event) { this.maxBudget = Number(event.target.value); }
    handleSearch(event) { this.searchTerm = event.target.value; }
    handleSortChange(event) { this.sortBy = event.detail.value; }
    handleFilterChange(event) {
        const property = FILTER_GROUPS[event.target.dataset.group];
        if (!property) return;
        const value = event.target.value;
        this[property] = event.target.checked
            ? [...this[property], value]
            : this[property].filter(v => v !== value);
    }
    clearFilters() {
        this.selectedMetals = []; this.selectedCategories = [];
        this.selectedGenders = []; this.selectedPurities = [];
        this.selectedStones = []; this.selectedCollections = [];
        this.selectedAvailability = []; this.maxBudget = this.budgetMaximum;
        this.searchTerm = ''; this.sortBy = 'newest';
    }
    get filteredProducts() {
        const term = this.searchTerm.trim().toLowerCase();
        return this.products.filter(p =>
            (!term || p.name.toLowerCase().includes(term) || p.category.toLowerCase().includes(term)) &&
            (!this.selectedMetals.length || this.selectedMetals.includes(p.metal)) &&
            (!this.selectedCategories.length || this.selectedCategories.includes(p.category)) &&
            (!this.selectedGenders.length || this.selectedGenders.includes(p.gender)) &&
            (!this.selectedPurities.length || this.selectedPurities.includes(p.purity)) &&
            (!this.selectedStones.length || this.selectedStones.includes(p.stone)) &&
            (!this.selectedAvailability.length || this.selectedAvailability.includes(p.availability)) &&
            p.sellingPrice <= this.maxBudget &&
            (!this.selectedCollections.length || this.selectedCollections.some(c =>
                (c === 'new' && p.isNew) || (c === 'featured' && p.featured) || (c === 'bestseller' && p.bestseller)
            ))
        ).sort((a, b) => {
            if (this.sortBy === 'low') return a.sellingPrice - b.sellingPrice;
            if (this.sortBy === 'high') return b.sellingPrice - a.sellingPrice;
            if (this.sortBy === 'name') return a.name.localeCompare(b.name);
            return b.dateValue - a.dateValue;
        });
    }
    get hasProducts() { return this.filteredProducts.length > 0; }
    get productCount() { return this.filteredProducts.length; }
}
