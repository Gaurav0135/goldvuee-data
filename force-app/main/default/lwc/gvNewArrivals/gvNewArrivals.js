import { LightningElement, wire } from "lwc";
import getNewArrivals from "@salesforce/apex/GVNewArrivalsController.getNewArrivals";

export default class GvNewArrivals extends LightningElement {
  products = [];
  errorMessage = "";
  loading = true;
  selectedCategory = "All";
  sortBy = "newest";

  @wire(getNewArrivals)
  wiredProducts({ data, error }) {
    this.loading = false;

    if (data) {
      this.products = data.map((product) => {
        const hasDiscount =
          product.discountPrice != null &&
          product.discountPrice > 0 &&
          product.discountPrice < product.price;

        return {
          ...product,
          displayPrice: hasDiscount ? product.discountPrice : product.price,
          hasDiscount,
          inStock: Number(product.availableQuantity) > 0,
          categoryLabel: product.category || "Fine Jewellery",
          dateValue: product.createdDate
            ? new Date(product.createdDate).getTime()
            : 0
        };
      });

      this.errorMessage = "";
    } else if (error) {
      this.products = [];
      this.errorMessage = error.body?.message || "Unable to load new arrivals.";
    }
  }

  get categoryOptions() {
    const categories = [
      ...new Set(
        this.products.map((product) => product.category).filter(Boolean)
      )
    ].sort();

    return [
      { label: "All Jewellery", value: "All" },
      ...categories.map((category) => ({
        label: category,
        value: category
      }))
    ];
  }

  get sortOptions() {
    return [
      { label: "Newest First", value: "newest" },
      { label: "Price: Low to High", value: "low" },
      { label: "Price: High to Low", value: "high" }
    ];
  }

  get filteredProducts() {
    let result = this.products.filter(
      (product) =>
        this.selectedCategory === "All" ||
        product.category === this.selectedCategory
    );

    result = [...result];

    if (this.sortBy === "low") {
      result.sort((a, b) => a.displayPrice - b.displayPrice);
    } else if (this.sortBy === "high") {
      result.sort((a, b) => b.displayPrice - a.displayPrice);
    } else {
      result.sort((a, b) => b.dateValue - a.dateValue);
    }

    return result;
  }

  get hasProducts() {
    return this.filteredProducts.length > 0;
  }

  get productCount() {
    return this.filteredProducts.length;
  }

  handleCategoryChange(event) {
    this.selectedCategory = event.detail.value;
  }

  handleSortChange(event) {
    this.sortBy = event.detail.value;
  }
}
