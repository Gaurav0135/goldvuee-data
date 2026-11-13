import { LightningElement } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import beginCheckout from "@salesforce/apex/GVOnlineCheckoutController.beginCheckout";
import getCart from "@salesforce/apex/GVCartController.getCart";
import updateCartItem from "@salesforce/apex/GVCartController.updateCartItem";
import removeCartItem from "@salesforce/apex/GVCartController.removeCartItem";
import communityBasePath from "@salesforce/community/basePath";
import checkoutRecovery from "@salesforce/apex/GVOnlineCheckoutController.checkoutRecovery";
import {
  pollingScope,
  cancelCheckout,
  rememberPayment,
  checkoutMessage,
  customerMessage
} from "c/gvCheckoutRecovery";

// ============================================================
// GOLDVUEE | SHOPPING CART
// ============================================================
// Displays and manages the authenticated customer's cart.
// All prices, inventory checks and ownership checks happen
// in GVCartController, not in the browser.
// ============================================================

const FALLBACK_IMAGE =
  "https://placehold.co/800x800/f8f3ee/6b1834?text=GoldVuee";

export default class GvShoppingCart extends NavigationMixin(LightningElement) {
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
    return checkoutMessage(this.recovery);
  }
  get resumeLabel() {
    return this.recovery?.state === "Confirmed"
      ? "View Order Confirmation"
      : this.recovery?.state === "StockUnavailable"
        ? "Check Availability"
        : "Continue Secure Payment";
  }
  get canCancelCheckout() {
    return !!this.recovery?.canCancel;
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
      const result = await cancelCheckout(paymentId, this.recoveryScope);
      if (!result || this.detached) return;
      this.recovery = result;
      this.successMessage = checkoutMessage(result);
      if (result.state === "Confirmed") {
        this.navigateTo("my-orders");
        return;
      }
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
      if (recovery?.state === "Confirmed") {
        this.navigateTo("my-orders");
        return;
      }
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

  async handleCheckout() {
    this.errorMessage = "";
    this.successMessage = "";

    // Prevent navigation while cart is being updated.
    if (this.isProcessing || this.isLoading) {
      return;
    }
    if (this.recovery?.state === "Confirmed") {
      this.navigateTo("my-orders");
      return;
    }

    // Do not allow checkout with an empty cart.
    if (!this.cartId || !this.hasItems) {
      this.errorMessage = "Your shopping bag is empty.";
      return;
    }

    // Navigate to the GoldVuee Experience Cloud
    // Checkout page.
    this.isProcessing = true;
    try {
      if (!this.hasPendingCheckout) {
        const order = await beginCheckout();
        if (this.detached) return;
        if (!order?.orderId || !order?.paymentId)
          throw new Error("Checkout could not be prepared.");
        rememberPayment(order.paymentId);
      }
      this.navigateTo("checkout");
    } catch (error) {
      if (!this.detached) this.errorMessage = this.getErrorMessage(error);
    } finally {
      if (!this.detached) this.isProcessing = false;
    }
  }

  // ========================================================
  // DISPLAY HELPERS
  // ========================================================

  navigateTo(page) {
    this[NavigationMixin.Navigate]({
      type: "standard__webPage",
      attributes: { url: communityBasePath + "/" + page }
    });
  }
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
    return customerMessage(
      error,
      "We could not update your shopping bag. Please try again."
    );
  }
}
