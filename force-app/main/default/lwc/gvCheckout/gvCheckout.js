import { LightningElement } from "lwc";
import isGuest from "@salesforce/user/isGuest";

import getCart from "@salesforce/apex/GVCartController.getCart";
import checkoutRecovery from "@salesforce/apex/GVOnlineCheckoutController.checkoutRecovery";
import cancelUnpaidCheckout from "@salesforce/apex/GVOnlineCheckoutController.cancelUnpaidCheckout";
import { savedPaymentId, rememberPayment } from "c/gvCheckoutRecovery";

import communityBasePath from "@salesforce/community/basePath";

export default class GvCheckout extends LightningElement {
  get isGuestUser() {
    return isGuest;
  }
  get loginUrl() {
    return `${communityBasePath}/login`;
  }
  // ==========================================
  // CART
  // ==========================================

  cartId = null;
  cartItems = [];
  itemCount = 0;
  subtotal = 0;

  // ==========================================
  // CHECKOUT STATES
  // ==========================================

  isLoading = true;
  isPlacingOrder = false;
  orderPlaced = false;
  isReturning = false;
  pendingOrder = null;
  get deliveryDisabled() {
    return this.isPlacingOrder || this.isReturning;
  }
  get backButtonLabel() {
    return this.isReturning
      ? "Checking Your Checkout…"
      : "← Back to Shopping Bag";
  }
  get journeyLabel() {
    return this.orderPlaced
      ? "Order Confirmation"
      : this.pendingOrder
        ? "Secure Payment"
        : "Delivery Information";
  }

  // ==========================================
  // PAYMENT METHOD
  // ==========================================

  confirmedPaymentMethod = "Razorpay";
  // ==========================================
  // MESSAGES
  // ==========================================

  errorMessage = "";
  successMessage = "";

  // ==========================================
  // ORDER CONFIRMATION
  // ==========================================

  orderNumber = "";
  orderGrandTotal = 0;
  orderStatus = "";
  paymentStatus = "";

  // ==========================================
  // SHIPPING
  // ==========================================

  shippingAddress = "";
  shippingCity = "";
  shippingState = "";
  shippingPostalCode = "";
  shippingCountry = "India";

  // ==========================================
  // INITIALIZE
  // ==========================================

  connectedCallback() {
    this.loadCheckout();
  }
  renderedCallback() {
    const address = this.template.querySelector(
      'textarea[name="shippingAddress"]'
    );
    if (address && address.value !== this.shippingAddress)
      address.value = this.shippingAddress;
  }

  // ==========================================
  // LOAD CUSTOMER CART
  // ==========================================

  async loadCheckout() {
    if (isGuest) {
      this.isLoading = false;
      return;
    }
    this.isLoading = true;
    this.errorMessage = "";

    try {
      const response = await getCart();
      const reference = savedPaymentId();
      if (reference) {
        try {
          const snapshot = await checkoutRecovery({ paymentId: reference });
          if (
            snapshot?.state === "Confirmed" &&
            (!response?.cartId || response.cartId === snapshot.order.cartId)
          ) {
            this.handleRazorpaySuccess({
              detail: { ...snapshot.order, success: true }
            });
            return;
          }
          if (snapshot?.state === "Cancelled") rememberPayment(null);
          if (
            snapshot?.state === "Confirmed" &&
            response?.cartId &&
            response.cartId !== snapshot.order.cartId
          )
            rememberPayment(null);
        } catch {
          rememberPayment(null);
        }
      }

      this.cartId = response?.cartId || null;

      this.itemCount = Number(response?.itemCount || 0);

      this.subtotal = Number(response?.totalAmount || 0);

      this.cartItems = (response?.items || []).map((item) => ({
        id: item.Id,

        name: item.Jewellery_Product__r?.Name || "GoldVuee Jewellery",

        quantity: Number(item.Quantity__c || 0),

        formattedLineTotal: this.formatCurrency(item.Line_Total__c || 0)
      }));
    } catch (error) {
      this.errorMessage = this.getErrorMessage(error);

      console.error("[GoldVuee] Cart loading failed", error);
    } finally {
      this.isLoading = false;
    }
  }

  // ==========================================
  // HANDLE SHIPPING INPUT
  // ==========================================

  handleInputChange(event) {
    if (this.isPlacingOrder || this.orderPlaced) {
      return;
    }

    const field = event.target.name;

    const allowed = [
      "shippingAddress",
      "shippingCity",
      "shippingState",
      "shippingPostalCode",
      "shippingCountry"
    ];

    if (allowed.includes(field)) {
      this[field] = event.target.value;
    }

    this.errorMessage = "";
  }

  handleCheckoutState(event) {
    this.isPlacingOrder = event.detail.locked;
    const order = event.detail.order;
    this.pendingOrder = order || null;
    if (order) {
      this.subtotal = Number(order.grandTotal);
      if (order.items)
        this.cartItems = order.items.map((item) => ({
          id: item.Id,
          name: item.Jewellery_Product__r?.Name || "GoldVuee Jewellery",
          quantity: Number(item.Quantity__c),
          formattedLineTotal: this.formatCurrency(item.Line_Total__c)
        }));
    }
    if (order?.shippingAddress) {
      this.shippingAddress = order.shippingAddress;
      this.shippingCity = order.shippingCity;
      this.shippingState = order.shippingState;
      this.shippingPostalCode = order.shippingPostalCode;
      this.shippingCountry = order.shippingCountry;
    }
  }

  // ==========================================
  // ==========================================
  // VALIDATE SHIPPING
  // ==========================================

  validateShipping() {
    const values = [
      this.shippingAddress,
      this.shippingCity,
      this.shippingState,
      this.shippingPostalCode,
      this.shippingCountry
    ];

    if (values.some((value) => !String(value || "").trim())) {
      this.errorMessage = "Please complete all delivery fields.";

      return false;
    }

    if (
      this.shippingCountry.trim().toLowerCase() !== "india" ||
      !/^[1-9][0-9]{5}$/.test(this.shippingPostalCode.trim())
    ) {
      this.errorMessage =
        "Please enter a valid Indian address and six-digit PIN code.";

      return false;
    }

    return true;
  }

  // ==========================================
  // ==========================================
  // BACK TO CART
  // ==========================================

  async handleBackToCart() {
    if (this.isReturning || this.orderPlaced) return;
    this.isReturning = true;
    this.errorMessage = "";
    try {
      const payment = this.template.querySelector(
        "c-goldvuee-razorpay-checkout"
      );
      let result;
      if (payment) result = await payment.cancelForBack();
      else {
        const snapshot = await checkoutRecovery({ paymentId: null });
        result = snapshot.order
          ? await cancelUnpaidCheckout({ paymentId: snapshot.order.paymentId })
          : { state: "Cancelled" };
      }
      if (result.state === "Cancelled")
        window.location.assign(`${communityBasePath}/shopping-cart`);
      else if (result.state === "Confirmed")
        this.handleRazorpaySuccess({
          detail: { ...result.order, success: true }
        });
      else
        this.errorMessage =
          result.message ||
          "Verifying your payment. Your bag remains reserved. Please visit My Orders for help.";
    } catch (error) {
      this.errorMessage = this.getErrorMessage(error);
    } finally {
      this.isReturning = false;
    }
  }

  handleCheckoutCancelled() {
    this.pendingOrder = null;
    this.loadCheckout();
  }

  handleRazorpaySuccess(event) {
    const result = event.detail;

    if (
      !result?.success ||
      result.orderStatus !== "Confirmed" ||
      result.paymentStatus !== "Paid"
    ) {
      this.errorMessage = "Salesforce did not confirm the online payment.";
      return;
    }

    this.orderPlaced = true;
    this.confirmedPaymentMethod = "Razorpay";

    this.orderNumber = result.orderNumber || "";
    this.orderGrandTotal = Number(result.grandTotal || this.subtotal);

    this.orderStatus = result.orderStatus;
    this.paymentStatus = result.paymentStatus;

    this.successMessage =
      "Your Razorpay Test Mode payment was verified. " +
      "Your GoldVuee jewellery order is confirmed.";

    this.errorMessage = "";

    this.cartId = null;
    this.cartItems = [];
    this.itemCount = 0;
    this.subtotal = 0;
  }

  // ==========================================
  // GETTERS
  // ==========================================

  get hasItems() {
    return this.cartItems.length > 0;
  }

  get formattedSubtotal() {
    return this.formatCurrency(this.subtotal);
  }

  get formattedOrderGrandTotal() {
    return this.formatCurrency(this.orderGrandTotal);
  }

  get isCheckoutDisabled() {
    return (
      this.isLoading ||
      this.isPlacingOrder ||
      this.orderPlaced ||
      !this.hasItems
    );
  }

  // ==========================================
  // CURRENCY HELPER
  // ==========================================

  formatCurrency(value) {
    return new Intl.NumberFormat("en-IN", {
      style: "currency",
      currency: "INR",
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    }).format(Number(value || 0));
  }

  // ==========================================
  // ERROR HELPER
  // ==========================================

  getErrorMessage(error) {
    if (Array.isArray(error?.body)) {
      return (
        error.body
          .map((item) => item?.message)
          .filter(Boolean)
          .join(", ") || "Checkout failed."
      );
    }

    return (
      error?.body?.message || error?.message || "Unable to complete checkout."
    );
  }
}
