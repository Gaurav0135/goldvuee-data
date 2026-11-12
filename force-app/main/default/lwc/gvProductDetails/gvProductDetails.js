import { LightningElement, api, wire } from "lwc";
import isGuest from "@salesforce/user/isGuest";
import communityBasePath from "@salesforce/community/basePath";
import { CurrentPageReference } from "lightning/navigation";

import getProductById from "@salesforce/apex/GVProductController.getProductById";

import addToCart from "@salesforce/apex/GVCartController.addToCart";

// ============================================================
// GOLDVUEE | PRODUCT DETAILS COMPONENT
// ============================================================
//
// Features:
// 1. Load jewellery using Salesforce Product ID.
// 2. Display product information and selling price.
// 3. Display current inventory availability.
// 4. Increase or decrease purchase quantity.
// 5. Add selected jewellery to the customer's cart.
// 6. Show cart success and error messages.
//
// Backend:
// - GVProductController.getProductById()
// - GVCartController.addToCart()
//
// Security:
// - Apex identifies the logged-in customer.
// - Apex calculates the selling price.
// - Apex validates inventory again before saving.
//
// ============================================================

const FALLBACK_IMAGE =
  "https://placehold.co/800x800/f8f3ee/6b1834?text=GoldVuee";

export default class GvProductDetails extends LightningElement {
  get isGuestUser() { return isGuest; }
  get loginUrl() { return `${communityBasePath}/login`; }
  // --------------------------------------------------------
  // 1. PRODUCT IDENTIFICATION
  // --------------------------------------------------------

  @api recordId;

  urlProductId = null;

  product = null;
  errorMessage = "";
  isLoading = false;

  // --------------------------------------------------------
  // 2. SHOPPING CART STATE
  // --------------------------------------------------------

  // Default purchase quantity.
  quantity = 1;

  // Prevent repeated clicks while Apex saves the cart.
  isAddingToCart = false;

  // Customer feedback messages.
  cartSuccessMessage = "";
  cartErrorMessage = "";

  // --------------------------------------------------------
  // 3. CURRENCY FORMATTER
  // --------------------------------------------------------

  currencyFormatter = new Intl.NumberFormat("en-IN", {
    style: "currency",
    currency: "INR",
    maximumFractionDigits: 0
  });

  // --------------------------------------------------------
  // 4. READ PRODUCT ID FROM PAGE URL
  // --------------------------------------------------------

  @wire(CurrentPageReference)
  readPageReference(pageReference) {
    const nextProductId = pageReference?.state?.c__productId || null;

    // Reset quantity and cart messages when navigating
    // to a different product.
    if (this.urlProductId !== nextProductId) {
      this.quantity = 1;
      this.cartSuccessMessage = "";
      this.cartErrorMessage = "";
    }

    this.urlProductId = nextProductId;
  }

  // Determine which product should be displayed.
  get productId() {
    return this.urlProductId || this.recordId || undefined;
  }

  // --------------------------------------------------------
  // 5. LOAD PRODUCT DATA FROM APEX
  // --------------------------------------------------------
  // Undefined productId prevents the Apex wire from running
  // until a product ID is available.

  @wire(getProductById, { productId: "$productId" })
  wiredProduct({ data, error }) {
    // No product has been selected.
    if (!this.productId) {
      this.product = null;
      this.errorMessage = "";
      this.isLoading = false;

      return;
    }

    // Salesforce returned the selected product.
    if (data) {
      this.errorMessage = "";

      const originalPrice = Number(data.Price__c || 0);

      const discountPrice = Number(data.Discount_Price__c || 0);

      const hasDiscount = discountPrice > 0 && discountPrice < originalPrice;

      const sellingPrice = hasDiscount ? discountPrice : originalPrice;

      // Convert Salesforce fields into UI-friendly data.
      this.product = {
        id: data.Id,
        name: data.Name,

        category: data.Category__r?.Name || "Jewellery",

        description:
          data.Description__c ||
          "An elegant piece from the GoldVuee collection.",

        image: data.Main_Image_URL__c || FALLBACK_IMAGE,

        metal: data.Metal_Type__c || "—",
        purity: data.Purity__c || "—",
        stone: data.Stone_Type__c || "—",
        gender: data.Gender__c || "—",

        sku: data.SKU__c || "—",
        productCode: data.Product_Code__c || "—",

        weight: data.Weight__c,

        stock: Number(data.Available_Quantity__c || 0),

        availability: data.Availability_Status__c,

        isNew: data.New_Arrival__c === true,

        isAvailable: data.Availability_Status__c === "In Stock",

        hasDiscount,

        formattedPrice: this.currencyFormatter.format(sellingPrice),

        formattedOriginalPrice: this.currencyFormatter.format(originalPrice)
      };

      // Keep selected quantity within available stock.
      if (this.quantity > this.product.stock || this.quantity < 1) {
        this.quantity = 1;
      }

      this.isLoading = false;
    } else if (error) {
      this.product = null;

      const apexMessage =
        error?.body?.message || error?.message || "Unknown Salesforce error";

      this.errorMessage =
        "Unable to load this jewellery product. " + apexMessage;

      this.isLoading = false;

      console.error("GoldVuee Product Details Apex Error:", error);
    } else {
      this.isLoading = true;
    }
  }

  // --------------------------------------------------------
  // 6. PRODUCT DISPLAY HELPERS
  // --------------------------------------------------------

  get hasProduct() {
    return Boolean(this.product);
  }

  get formattedWeight() {
    if (
      !this.product ||
      this.product.weight === null ||
      this.product.weight === undefined
    ) {
      return "Not specified";
    }

    return `${this.product.weight} g`;
  }

  get stockLabel() {
    if (!this.product) {
      return "";
    }

    return this.product.isAvailable ? "In Stock" : "Out of Stock";
  }

  get availabilityClass() {
    return this.product?.isAvailable
      ? "stock-status in-stock"
      : "stock-status out-of-stock";
  }

  // --------------------------------------------------------
  // 7. INVENTORY HELPERS
  // --------------------------------------------------------

  get isInStock() {
    return Boolean(
      this.product && this.product.isAvailable && this.product.stock > 0
    );
  }

  get isDecreaseDisabled() {
    return this.isAddingToCart || !this.isInStock || this.quantity <= 1;
  }

  get isIncreaseDisabled() {
    return (
      this.isAddingToCart ||
      !this.isInStock ||
      this.quantity >= this.product.stock
    );
  }

  get isAddToCartDisabled() {
    return (
      this.isAddingToCart ||
      !this.isInStock ||
      this.quantity < 1 ||
      this.quantity > this.product.stock
    );
  }

  // --------------------------------------------------------
  // 8. DECREASE QUANTITY
  // --------------------------------------------------------

  handleDecreaseQuantity() {
    if (this.isDecreaseDisabled) {
      return;
    }

    this.quantity -= 1;

    // Clear messages when the customer changes quantity.
    this.cartSuccessMessage = "";
    this.cartErrorMessage = "";
  }

  // --------------------------------------------------------
  // 9. INCREASE QUANTITY
  // --------------------------------------------------------

  handleIncreaseQuantity() {
    if (this.isIncreaseDisabled) {
      return;
    }

    this.quantity += 1;

    this.cartSuccessMessage = "";
    this.cartErrorMessage = "";
  }

  // --------------------------------------------------------
  // 10. ADD JEWELLERY TO SALESFORCE CART
  // --------------------------------------------------------
  //
  // Calls:
  // GVCartController.addToCart(productId, quantity)
  //
  // Apex:
  // - Identifies the customer using User.ContactId.
  // - Finds or creates an active cart.
  // - Validates stock.
  // - Determines the current selling price.
  // - Inserts or updates the cart item.
  //
  // --------------------------------------------------------

  async handleAddToCart() {
    if (isGuest) {
      this.cartErrorMessage = "Please sign in to add jewellery to your bag.";
      return;
    }
    // Prevent invalid or repeated submissions.
    if (this.isAddToCartDisabled || !this.product?.id) {
      return;
    }

    const selectedProductId = this.product.id;
    const selectedProductName = this.product.name;
    const selectedQuantity = this.quantity;

    // Start loading state.
    this.isAddingToCart = true;

    // Clear previous messages.
    this.cartSuccessMessage = "";
    this.cartErrorMessage = "";

    try {
      // Call Salesforce Apex.
      const cartResponse = await addToCart({
        productId: selectedProductId,
        quantity: selectedQuantity
      });

      // Show confirmation only after Apex succeeds.
      this.cartSuccessMessage =
        `${selectedQuantity} × ${selectedProductName} ` +
        "added to your cart successfully!";

      // Useful for debugging during development.
      console.log("GoldVuee Cart Updated:", cartResponse);

      // Reset quantity after successful addition.
      if (this.product?.id === selectedProductId) {
        this.quantity = 1;
      }

      // Later we can notify the header cart badge
      // and navigate to the Shopping Cart page.
    } catch (error) {
      // Salesforce may return an AuraHandledException
      // for login, stock, access or validation problems.
      const apexMessage =
        error?.body?.message ||
        error?.message ||
        "Unable to add this product to your cart.";

      this.cartErrorMessage = apexMessage;

      console.error("GoldVuee Add to Cart Error:", error);
    } finally {
      // Re-enable controls after the Apex call finishes.
      this.isAddingToCart = false;
    }
  }
}
