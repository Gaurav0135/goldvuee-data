/* eslint-disable no-await-in-loop, @lwc/lwc/no-async-operation -- Bounded sequential gateway polling and popup watchdogs, cleaned up on disconnect. */
import { LightningElement, api } from "lwc";
import razorpayKey from "@salesforce/label/c.GoldVuee_Razorpay_Test_Key_ID";
import hostUrl from "@salesforce/label/c.GoldVuee_Razorpay_Host_URL";
import prepareOnlineOrder from "@salesforce/apex/GVOnlineCheckoutController.prepareOnlineOrder";
import resumeCheckout from "@salesforce/apex/GVOnlineCheckoutController.resumeCheckout";
import requestReconciliation from "@salesforce/apex/GVOnlineCheckoutController.requestReconciliation";
import cancelExpiredCheckout from "@salesforce/apex/GVOnlineCheckoutController.cancelExpiredCheckout";
import initiatePayment from "@salesforce/apex/GVPaymentController.initiatePayment";
import paymentState from "@salesforce/apex/GVPaymentController.paymentState";
import verifyPayment from "@salesforce/apex/GVPaymentVerificationController.verifyPayment";
import requestSignatureVerification from "@salesforce/apex/GVPaymentVerificationController.requestSignatureVerification";
import signatureVerificationState from "@salesforce/apex/GVPaymentVerificationController.signatureVerificationState";

export default class GoldvueeRazorpayCheckout extends LightningElement {
  @api amount = 0;
  @api shippingAddress = "";
  @api shippingCity = "";
  @api shippingState = "";
  @api shippingPostalCode = "";
  @api shippingCountry = "India";
  isWorking = false;
  completed = false;
  errorMessage = "";
  statusMessage = "";
  pendingOrder = null;
  gatewayOrder = null;
  paymentWindow = null;
  nonce = null;
  isExpired = false;
  needsReview = false;
  hostReady = false;
  paymentSent = false;
  confirming = false;
  confirmationData = null;
  closeTimer;
  handshakeTimer;
  detached = false;
  connectedCallback() {
    window.addEventListener("message", this.handleHostMessage);
    this.restore();
  }
  disconnectedCallback() {
    this.detached = true;
    window.removeEventListener("message", this.handleHostMessage);
    this.clearTimers();
  }
  get isButtonDisabled() {
    return this.isWorking || this.completed;
  }
  get buttonLabel() {
    if (this.completed) return "Order Confirmed";
    if (this.isWorking) return "Processing Secure Checkout…";
    if (this.confirmationData) return "Resume Payment Confirmation";
    if (this.isExpired) return "Restart Unpaid Checkout";
    if (this.needsReview) return "Payment Under Review — Do Not Pay Again";
    if (this.pendingOrder)
      return `Pay ${new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR" }).format(this.pendingOrder.grandTotal)} with Razorpay`;
    return "Review Secure Checkout";
  }
  state(locked) {
    this.dispatchEvent(
      new CustomEvent("checkoutstate", {
        detail: { locked, order: this.pendingOrder }
      })
    );
  }
  async restore() {
    try {
      const order = await resumeCheckout();
      if (order && !this.pendingOrder) {
        this.pendingOrder = order;
        this.isExpired = order.reconciliationState === "Expired - stock released";
        this.needsReview = String(order.reconciliationState || "").toLowerCase().includes("captured");
        this.state(true);
        this.statusMessage =
          order.reconciliationState ||
          "Existing checkout restored. Check payment status before paying again.";
      }
    } catch (error) {
      this.errorMessage = this.readError(error);
    }
  }
  validateShipping() {
    if (
      [
        this.shippingAddress,
        this.shippingCity,
        this.shippingState,
        this.shippingPostalCode,
        this.shippingCountry
      ].some((v) => !String(v || "").trim())
    )
      throw new Error("Complete all delivery information.");
    if (
      this.shippingCountry.trim().toLowerCase() !== "india" ||
      !/^[1-9][0-9]{5}$/.test(this.shippingPostalCode.trim())
    )
      throw new Error("Enter a valid Indian address and PIN code.");
  }
  handlePay = async () => {
    if (this.isButtonDisabled) return;
    this.isWorking = true;
    this.errorMessage = "";
    try {
      if (this.isExpired) {
        await cancelExpiredCheckout({ paymentId: this.pendingOrder.paymentId });
        this.pendingOrder = null;
        this.gatewayOrder = null;
        this.isExpired = false;
        this.state(false);
        this.statusMessage =
          "Unpaid checkout closed. Review delivery information to start again.";
        return;
      }
      if (this.needsReview)
        throw new Error(
          "Your payment requires review. Check payment status; do not pay again."
        );
      if (this.confirmationData) {
        await this.confirm(this.confirmationData);
        return;
      }
      if (!this.pendingOrder) {
        this.validateShipping();
        this.state(true);
        this.pendingOrder = await prepareOnlineOrder({
          shippingAddress: this.shippingAddress.trim(),
          shippingCity: this.shippingCity.trim(),
          shippingState: this.shippingState.trim(),
          shippingPostalCode: this.shippingPostalCode.trim(),
          shippingCountry: this.shippingCountry.trim()
        });
        this.state(true);
        this.statusMessage =
          "Review the final server-calculated total on the Pay button. Delivery information is now reserved for this order.";
        return;
      }
      if (!/^rzp_test_[A-Za-z0-9]+$/.test(razorpayKey || ""))
        throw new Error("Razorpay Test Key ID is not configured.");
      const url = new URL(hostUrl);
      const bytes = new Uint8Array(16);
      window.crypto.getRandomValues(bytes);
      this.nonce = Array.from(bytes)
        .map((v) => v.toString(16).padStart(2, "0"))
        .join("");
      url.searchParams.set("origin", window.location.origin);
      url.searchParams.set("nonce", this.nonce);
      this.hostReady = false;
      this.paymentSent = false;
      this.gatewayOrder = null;
      this.paymentWindow = window.open(
        url.toString(),
        "_blank",
        "width=520,height=760"
      );
      if (!this.paymentWindow)
        throw new Error("Allow popups to open secure Razorpay checkout.");
      this.watchWindow();
      let gateway = await initiatePayment({
        paymentId: this.pendingOrder.paymentId
      });
      for (let i = 0; i < 40 && gateway.state === "Queued"; i += 1) {
        await this.delay(1000);
        gateway = await paymentState({
          paymentId: this.pendingOrder.paymentId
        });
      }
      if (gateway.state === "Review") {
        this.needsReview = true;
        throw new Error("Payment requires review. Do not pay again.");
      }
      if (
        !/^order_[A-Za-z0-9]+$/.test(gateway.razorpayOrderId || "") ||
        gateway.currencyCode !== "INR" ||
        !Number.isSafeInteger(Number(gateway.amountPaise)) ||
        Number(gateway.amountPaise) < 100
      )
        throw new Error(
          "Payment initialization is pending reconciliation. Use Check Payment Status; do not start another payment."
        );
      this.gatewayOrder = gateway;
      this.statusMessage = "Complete payment in the Razorpay window.";
      this.sendPaymentToHost();
      // Keep disabled while the popup is active.
    } catch (error) {
      this.errorMessage = this.readError(error);
      this.closeWindow();
      if (!this.pendingOrder) this.state(false);
    } finally {
      if (
        !this.paymentWindow ||
        this.paymentWindow.closed ||
        !this.gatewayOrder
      )
        this.isWorking = false;
    }
  };
  sendPaymentToHost() {
    if (
      !this.hostReady ||
      !this.gatewayOrder ||
      !this.paymentWindow ||
      this.paymentWindow.closed ||
      this.paymentSent
    )
      return;
    // A primitive string crosses the LWS boundary without structured-cloning
    // reactive proxies. Both endpoints decode and validate the envelope.
    const payload = JSON.stringify({
        source: "GOLDVUEE_CHECKOUT",
        type: "START_PAYMENT",
        nonce: this.nonce,
        data: {
          key: razorpayKey,
          orderId: this.gatewayOrder.razorpayOrderId,
          amount: Number(this.gatewayOrder.amountPaise)
        }
      });
    try {
      this.paymentWindow.postMessage(payload, new URL(hostUrl).origin);
      this.paymentSent = true;
      clearTimeout(this.handshakeTimer);
    } catch (error) {
      this.errorMessage = "Unable to connect to the payment window. " + this.readError(error);
      this.statusMessage = "";
      this.closeWindow();
      this.isWorking = false;
    }
  }
  handleHostMessage = async (event) => {
    if (
      !this.paymentWindow ||
      event.source !== this.paymentWindow ||
      event.origin !== new URL(hostUrl).origin
    )
      return;
    let message = event.data;
    if (typeof message === "string") {
      if (message.length > 16384) return;
      try { message = JSON.parse(message); } catch { return; }
    }
    if (
      !message ||
      message.source !== "GOLDVUEE_RAZORPAY_HOST" ||
      message.nonce !== this.nonce
    )
      return;
    if (message.type === "READY") {
      this.hostReady = true;
      this.sendPaymentToHost();
      return;
    }
    if (message.type === "PAYMENT_SUCCESS") {
      if (this.confirming || this.completed) return;
      const data = message.data;
      if (
        !/^pay_[A-Za-z0-9]+$/.test(data?.paymentId || "") ||
        !/^[a-fA-F0-9]{64}$/.test(data?.signature || "") ||
        data?.orderId !== this.gatewayOrder?.razorpayOrderId
      ) {
        this.errorMessage = "Invalid checkout response.";
        return;
      }
      this.confirmationData = data;
      await this.confirm(data);
      return;
    }
    if (
      ["PAYMENT_FAILED", "PAYMENT_DISMISSED", "ERROR"].includes(message.type) &&
      !this.confirming
    ) {
      this.statusMessage =
        "Payment was not confirmed. Check payment status before retrying.";
      this.closeWindow();
      this.isWorking = false;
    }
  };
  async confirm(data) {
    this.confirming = true;
    this.isWorking = true;
    this.errorMessage = "";
    try {
      let state = await requestSignatureVerification({
        paymentId: this.pendingOrder.paymentId,
        razorpayPaymentId: data.paymentId,
        razorpaySignature: data.signature
      });
      for (let i = 0; i < 40 && state === "WAITING"; i += 1) {
        this.statusMessage = "Validating payment securely…";
        await this.delay(1000);
        state = await signatureVerificationState({
          paymentId: this.pendingOrder.paymentId,
          razorpayPaymentId: data.paymentId
        });
      }
      if (!["VERIFIED", "CONFIRMED"].includes(state))
        throw new Error(
          "Verification is pending. Resume confirmation or check payment status; do not pay again."
        );
      const result = await verifyPayment({
        paymentId: this.pendingOrder.paymentId,
        razorpayPaymentId: data.paymentId
      });
      if (!result?.success)
        throw new Error(
          result?.message ||
            "Payment requires reconciliation. Do not pay again."
        );
      this.success(result);
    } catch (error) {
      this.errorMessage = this.readError(error);
      this.statusMessage =
        "Confirmation is incomplete. Your payment reference is retained for retry.";
    } finally {
      this.confirming = false;
      this.isWorking = false;
      this.closeWindow();
    }
  }
  async handleCheckStatus() {
    if (!this.pendingOrder || this.isWorking) return;
    this.isWorking = true;
    this.errorMessage = "";
    try {
      await requestReconciliation({ paymentId: this.pendingOrder.paymentId });
      this.statusMessage = "Checking Razorpay and Salesforce…";
      for (let i = 0; i < 20; i += 1) {
        await this.delay(1200);
        const state = await paymentState({
          paymentId: this.pendingOrder.paymentId
        });
        if (state.state === "Confirmed") {
          this.success({
            success: true,
            orderId: this.pendingOrder.orderId,
            orderNumber: this.pendingOrder.orderNumber,
            orderStatus: "Confirmed",
            paymentStatus: "Paid"
          });
          return;
        }
        if (state.state === "Expired") {
          this.isExpired = true;
          this.statusMessage =
            "Unpaid reservation expired. You may restart checkout.";
          return;
        }
        if (state.state === "Cancelled") {
          this.pendingOrder = null;
          this.gatewayOrder = null;
          this.state(false);
          this.statusMessage =
            "Unpaid checkout expired. Review checkout again.";
          return;
        }
        if (state.state === "Review") {
          this.needsReview = true;
          this.statusMessage =
            "Payment received; inventory review is required. Do not pay again.";
          return;
        }
        if (state.message) this.statusMessage = state.message;
      }
      this.statusMessage =
        "Reconciliation requested. Check My Orders before attempting another payment.";
    } catch (error) {
      this.errorMessage = this.readError(error);
    } finally {
      this.isWorking = false;
    }
  }
  success(result) {
    this.completed = true;
    this.statusMessage = "Payment verified and order confirmed.";
    this.dispatchEvent(
      new CustomEvent("paymentsuccess", {
        detail: { ...result, grandTotal: this.pendingOrder.grandTotal }
      })
    );
  }
  watchWindow() {
    this.clearTimers();
    this.closeTimer = setInterval(() => {
      if (this.paymentWindow?.closed && !this.confirming) {
        this.clearTimers();
        this.isWorking = false;
        this.statusMessage =
          "Payment window closed. Check payment status before retrying.";
      }
    }, 500);
    this.handshakeTimer = setTimeout(() => {
      if (!this.hostReady && !this.confirming) {
        this.errorMessage =
          "Payment window did not connect. Check popup access and try again.";
        this.closeWindow();
        this.isWorking = false;
      }
    }, 15000);
  }
  clearTimers() {
    clearInterval(this.closeTimer);
    clearTimeout(this.handshakeTimer);
  }
  closeWindow() {
    this.clearTimers();
    if (this.paymentWindow && !this.paymentWindow.closed)
      this.paymentWindow.close();
    this.paymentWindow = null;
  }
  delay(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }
  readError(error) {
    return (
      error?.body?.message || error?.message || "Unable to complete checkout."
    );
  }
}
