import { LightningElement } from "lwc";
import getCart from "@salesforce/apex/GVCartController.getCart";
import updateCartItem from "@salesforce/apex/GVCartController.updateCartItem";
import removeCartItem from "@salesforce/apex/GVCartController.removeCartItem";
import communityBasePath from "@salesforce/community/basePath";
import checkoutRecovery from "@salesforce/apex/GVOnlineCheckoutController.checkoutRecovery";
import cancelUnpaidCheckout from "@salesforce/apex/GVOnlineCheckoutController.cancelUnpaidCheckout";
import { pollingScope, reconcile } from "c/gvCheckoutRecovery";

// ============================================================
// GOLDVUEE | SHOPPING CART
// ============================================================
// Displays and manages the authenticated customer's cart.
// All prices, inventory checks and ownership checks happen
// in GVCartController, not in the browser.
// ============================================================

const FALLBACK_IMAGE =
  "https://placehold.co/800x800/f8f3ee/6b1834?text=GoldVuee";

export default class GvShoppingCart extends LightningElement {
  cartId = null;
  cartItems = [];
  totalAmount = 0;
  itemCount = 0;

  isLoading = true;
  isProcessing = false;
  errorMessage = "";
  successMessage = "";
  recovery = null;
  recoveryScope;
  detached = false;
  get hasPendingCheckout() {
    return !!this.recovery?.order && this.recovery.state !== "Cancelled";
  }
  get recoveryMessage() {
    const message = this.recovery?.message;
    return message && message !== "Your previous checkout is waiting."
      ? message
      : "Your jewellery is reserved while you decide.";
  }
  get resumeLabel() {
    return this.recovery?.state === "Confirmed"
      ? "View Order Confirmation"
      : "Resume Secure Payment";
  }
  get ordersUrl() {
    return `${communityBasePath}/my-orders`;
  }
  get displayItems() {
    return this.cartItems.map((item) => ({
      ...item,
      decreaseDisabled: this.controlsDisabled || item.quantity <= 1
    }));
  }
  disconnectedCallback() {
    this.detached = true;
    this.recoveryScope?.cancel();
  }

  async handleCancelCheckout() {
    if (this.isProcessing || !this.recovery?.order) return;
    this.isProcessing = true;
    this.errorMessage = "";
    const paymentId = this.recovery.order.paymentId;
    this.recoveryScope?.cancel();
    this.recoveryScope = pollingScope();
    try {
      let result = await cancelUnpaidCheckout({ paymentId });
      if (this.detached) return;
      if (result.state === "Uncertain") {
        this.recovery = result;
        this.successMessage =
          "Verifying your payment. Your shopping bag remains reserved.";
        const verified = await reconcile(paymentId, this.recoveryScope);
        if (this.detached) return;
        if (verified?.state === "Confirmed") result = verified;
      }
      this.recovery = result;
      this.successMessage =
        result.state === "Cancelled"
          ? "Unpaid checkout cancelled. You can update your shopping bag."
          : result.message;
      if (result.state === "Cancelled") await this.loadCart();
    } catch (error) {
      if (!this.detached) this.errorMessage = this.getErrorMessage(error);
    } finally {
      if (!this.detached) this.isProcessing = false;
    }
  }

  currencyFormatter = new Intl.NumberFormat("en-IN", {
    style: "currency",
    currency: "INR",
    maximumFractionDigits: 2
  });

  // ========================================================
  // INITIAL LOAD
  // ========================================================

  connectedCallback() {
    this.detached = false;
    this.loadCart();
  }

  // ========================================================
  // LOAD CUSTOMER CART
  // ========================================================

  async loadCart() {
    this.isLoading = true;
    this.errorMessage = "";

    try {
      const response = await getCart();
      const recovery = await checkoutRecovery({ paymentId: null });
      if (this.detached) return;
      this.recovery = recovery;
      this.applyCartResponse(response);
    } catch (error) {
      this.errorMessage = this.getErrorMessage(error);
      console.error("GoldVuee cart loading error:", error);
    } finally {
      this.isLoading = false;
    }
  }

  // ========================================================
  // CONVERT APEX RESPONSE INTO DISPLAY DATA
  // ========================================================

  applyCartResponse(response) {
    this.cartId = response?.cartId || null;
    this.totalAmount = Number(response?.totalAmount || 0);
    this.itemCount = Number(response?.itemCount || 0);

    this.cartItems = (response?.items || []).map((item) => {
      const product = item.Jewellery_Product__r || {};
      const quantity = Number(item.Quantity__c || 0);
      const unitPrice = Number(item.Unit_Price__c || 0);
      const lineTotal = Number(item.Line_Total__c || 0);

      return {
        id: item.Id,
        productId: item.Jewellery_Product__c,
        name: product.Name || "Jewellery Product",
        image: product.Main_Image_URL__c || FALLBACK_IMAGE,
        quantity,
        unitPrice,
        lineTotal,
        formattedUnitPrice: this.formatCurrency(unitPrice),
        formattedLineTotal: this.formatCurrency(lineTotal),
        detailsUrl:
          `${communityBasePath}/product-details?c__productId=` +
          encodeURIComponent(item.Jewellery_Product__c),
        decreaseDisabled: quantity <= 1,
        availability: this.hasPendingCheckout
          ? "Reserved for your checkout"
          : Number(product.Available_Quantity__c || 0) >= quantity
            ? "Available for your bag"
            : "Availability checked at checkout"
      };
    });
  }

  // ========================================================
  // UPDATE QUANTITY
  // ========================================================

  async handleIncrease(event) {
    const itemId = event.currentTarget.dataset.id;
    const item = this.cartItems.find((row) => row.id === itemId);

    if (!item || this.controlsDisabled) {
      return;
    }

    await this.changeQuantity(itemId, item.quantity + 1);
  }

  async handleDecrease(event) {
    const itemId = event.currentTarget.dataset.id;
    const item = this.cartItems.find((row) => row.id === itemId);

    if (!item || this.controlsDisabled || item.quantity <= 1) {
      return;
    }

    await this.changeQuantity(itemId, item.quantity - 1);
  }

  async changeQuantity(itemId, quantity) {
    this.isProcessing = true;
    this.errorMessage = "";
    this.successMessage = "";

    try {
      const response = await updateCartItem({
        cartItemId: itemId,
        quantity
      });

      this.applyCartResponse(response);
      this.successMessage = "Shopping bag updated successfully.";
    } catch (error) {
      this.errorMessage = this.getErrorMessage(error);
      console.error("GoldVuee quantity update error:", error);
    } finally {
      this.isProcessing = false;
    }
  }

  // ========================================================
  // REMOVE CART ITEM
  // ========================================================

  async handleRemove(event) {
    const itemId = event.currentTarget.dataset.id;

    if (!itemId || this.controlsDisabled) {
      return;
    }

    this.isProcessing = true;
    this.errorMessage = "";
    this.successMessage = "";

    try {
      const response = await removeCartItem({
        cartItemId: itemId
      });

      this.applyCartResponse(response);
      this.successMessage = "Jewellery removed from your bag.";
    } catch (error) {
      this.errorMessage = this.getErrorMessage(error);
      console.error("GoldVuee remove item error:", error);
    } finally {
      this.isProcessing = false;
    }
  }

  // ========================================================
  // NAVIGATION
  // ========================================================

  handleContinueShopping() {
    window.location.assign(`${communityBasePath}/collections`);
  }

  // ========================================================
  // CHECKOUT NAVIGATION — CONNECTED
  // ========================================================

  handleCheckout() {
    this.errorMessage = "";
    this.successMessage = "";

    // Prevent navigation while cart is being updated.
    if (this.isProcessing || this.isLoading) {
      return;
    }
    if (this.recovery?.state === "Confirmed") {
      window.location.assign(this.ordersUrl);
      return;
    }

    // Do not allow checkout with an empty cart.
    if (!this.cartId || !this.hasItems) {
      this.errorMessage = "Your shopping bag is empty.";
      return;
    }

    // Navigate to the GoldVuee Experience Cloud
    // Checkout page.
    window.location.assign(`${communityBasePath}/checkout`);
  }

  // ========================================================
  // DISPLAY HELPERS
  // ========================================================

  get hasItems() {
    return this.cartItems.length > 0;
  }

  get isEmpty() {
    return !this.isLoading && !this.hasItems;
  }

  get formattedTotal() {
    return this.formatCurrency(this.totalAmount);
  }

  get itemCountLabel() {
    return this.itemCount === 1
      ? "1 exquisite piece"
      : `${this.itemCount} exquisite pieces`;
  }

  get controlsDisabled() {
    return this.isProcessing || this.isLoading || this.hasPendingCheckout;
  }

  // ========================================================
  // CURRENCY FORMATTING
  // ========================================================

  formatCurrency(value) {
    return this.currencyFormatter.format(Number(value || 0));
  }

  // ========================================================
  // ERROR HANDLING
  // ========================================================

  getErrorMessage(error) {
    return (
      error?.body?.message ||
      error?.message ||
      "Something went wrong. Please try again."
    );
  }
}
