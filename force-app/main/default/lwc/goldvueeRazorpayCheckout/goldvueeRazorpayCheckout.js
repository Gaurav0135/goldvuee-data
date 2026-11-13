/* eslint-disable no-await-in-loop, @lwc/lwc/no-async-operation -- Bounded sequential gateway polling and popup watchdogs, cleaned up on disconnect. */
import { LightningElement, api } from "lwc";
import razorpayKey from "@salesforce/label/c.GoldVuee_Razorpay_Test_Key_ID";
import hostUrl from "@salesforce/label/c.GoldVuee_Razorpay_Host_URL";
import prepareOnlineOrder from "@salesforce/apex/GVOnlineCheckoutController.prepareOnlineOrder";
import resumeCheckout from "@salesforce/apex/GVOnlineCheckoutController.resumeCheckout";
import checkoutRecovery from "@salesforce/apex/GVOnlineCheckoutController.checkoutRecovery";
import cancelUnpaidCheckout from "@salesforce/apex/GVOnlineCheckoutController.cancelUnpaidCheckout";
import communityBasePath from "@salesforce/community/basePath";
import { pollingScope, reconcile, rememberPayment } from "c/gvCheckoutRecovery";
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
  recovery = null;
  scope;
  phase = "Ready";
  get ordersUrl() {
    return `${communityBasePath}/my-orders`;
  }
  get hasPendingOrder() {
    return !!this.pendingOrder && !this.completed;
  }
  get showProgress() {
    return this.isWorking;
  }
  get cancelDisabled() {
    return this.isWorking || this.completed;
  }
  beginScope() {
    this.scope?.cancel();
    this.scope = pollingScope();
    return this.scope;
  }
  connectedCallback() {
    this.detached = false;
    this.confirming = false;
    window.addEventListener("message", this.handleHostMessage);
    this.restore();
  }
  disconnectedCallback() {
    this.detached = true;
    this.scope?.cancel();
    window.removeEventListener("message", this.handleHostMessage);
    this.clearTimers();
  }
  get isButtonDisabled() {
    return this.isWorking || this.completed;
  }
  get buttonLabel() {
    if (this.completed) return "Order Confirmed";
    if (this.isWorking) return this.phase;
    if (this.confirmationData) return "Resume Payment Confirmation";
    if (this.pendingOrder && !this.recovery?.canRetry)
      return "Resume Payment Verification";
    if (this.pendingOrder)
      return `Pay Securely · ${new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR" }).format(this.pendingOrder.grandTotal)}`;
    return "Continue to Secure Payment";
  }
  state(locked) {
    if (this.pendingOrder?.paymentId)
      rememberPayment(this.pendingOrder.paymentId);
    this.dispatchEvent(
      new CustomEvent("checkoutstate", {
        detail: { locked, order: this.pendingOrder }
      })
    );
  }
  async restore() {
    this.isWorking = true;
    this.phase = "Restoring Your Checkout…";
    const scope = this.beginScope();
    try {
      const order = await resumeCheckout();
      if (scope.cancelled) return;
      if (order && !this.pendingOrder) {
        this.pendingOrder = order;
        this.isExpired =
          order.reconciliationState === "Expired - stock released";
        this.needsReview = String(order.reconciliationState || "")
          .toLowerCase()
          .includes("captured");
        this.state(true);
        await this.reconcileCurrent(scope);
      }
    } catch (error) {
      if (!scope.cancelled) this.errorMessage = this.readError(error);
    } finally {
      if (!scope.cancelled) this.isWorking = false;
    }
  }
  applyRecovery(result) {
    if (!result) {
      this.statusMessage =
        "Payment verification is taking longer than expected. Your checkout is saved. Resume verification here, or visit My Orders for help. Please do not pay again yet.";
      return;
    }
    this.recovery = result;
    this.needsReview = result.state === "Review";
    this.isExpired = result.state === "Expired";
    this.statusMessage = result.message || "";
    if (result.state === "Confirmed")
      this.success({ ...result.order, success: true });
    if (result.state === "Cancelled") {
      rememberPayment(null);
      this.pendingOrder = null;
      this.gatewayOrder = null;
      this.confirmationData = null;
      this.state(false);
      this.dispatchEvent(new CustomEvent("checkoutcancelled"));
      this.statusMessage =
        "Unpaid checkout cancelled. You can update your shopping bag.";
    }
  }
  async reconcileCurrent(scope) {
    this.phase = "Verifying Your Payment…";
    this.statusMessage = "Verifying your payment. Please do not pay again yet.";
    const snapshot = await checkoutRecovery({
      paymentId: this.pendingOrder.paymentId
    });
    if (scope.cancelled) return;
    if (
      snapshot.canCancel ||
      ["Confirmed", "Cancelled", "Review"].includes(snapshot.state)
    ) {
      this.applyRecovery(snapshot);
      return;
    }
    this.recovery = { ...snapshot, canRetry: false };
    const result = await reconcile(this.pendingOrder.paymentId, scope);
    if (!scope.cancelled) this.applyRecovery(result);
  }
  @api async cancelForBack() {
    if (this.isWorking)
      return {
        state: "Uncertain",
        message:
          "Your payment is being verified. Please wait before returning to your bag."
      };
    this.isWorking = true;
    this.phase = "Cancelling Checkout…";
    const scope = this.beginScope();
    try {
      const snapshot = await checkoutRecovery({
        paymentId: this.pendingOrder?.paymentId || null
      });
      if (scope.cancelled) return { state: "Uncertain" };
      if (!snapshot.order) return { state: "Cancelled" };
      this.pendingOrder = { ...this.pendingOrder, ...snapshot.order };
      const result = await cancelUnpaidCheckout({
        paymentId: snapshot.order.paymentId
      });
      if (scope.cancelled) return { state: "Uncertain" };
      this.applyRecovery(result);
      if (result.state === "Uncertain") {
        const verified = await reconcile(snapshot.order.paymentId, scope);
        if (!scope.cancelled && verified?.state === "Confirmed") {
          this.applyRecovery(verified);
          return verified;
        }
        if (!scope.cancelled) this.statusMessage = result.message;
      }
      return result;
    } catch (error) {
      const result = { state: "Uncertain", message: this.readError(error) };
      if (!scope.cancelled) this.errorMessage = result.message;
      return result;
    } finally {
      if (!scope.cancelled) this.isWorking = false;
    }
  }
  async handleCancel() {
    await this.cancelForBack();
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
    const scope = this.beginScope();
    this.phase = "Preparing Secure Payment…";
    try {
      if (
        this.pendingOrder &&
        !this.recovery?.canRetry &&
        !this.confirmationData
      ) {
        await this.reconcileCurrent(scope);
        return;
      }
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
        if (scope.cancelled) return;
        this.recovery = await checkoutRecovery({
          paymentId: this.pendingOrder.paymentId
        });
        if (scope.cancelled) return;
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
      for (let i = 0; i < 12 && gateway.state === "Queued"; i += 1) {
        if (!(await scope.wait(Math.min(600 * (i + 1), 4000)))) return;
        gateway = await paymentState({
          paymentId: this.pendingOrder.paymentId
        });
      }
      if (scope.cancelled) return;
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
          "Payment initialization is pending verification. Resume verification here; do not start another payment."
        );
      this.gatewayOrder = gateway;
      this.phase = "Complete Payment in Razorpay";
      this.statusMessage = "Complete payment in the Razorpay window.";
      this.sendPaymentToHost();
      // Keep disabled while the popup is active.
    } catch (error) {
      if (scope.cancelled) return;
      this.errorMessage = this.readError(error);
      this.recovery = this.recovery
        ? { ...this.recovery, canRetry: false }
        : null;
      this.closeWindow();
      if (!this.pendingOrder) this.state(false);
    } finally {
      if (
        !scope.cancelled &&
        (!this.paymentWindow || this.paymentWindow.closed || !this.gatewayOrder)
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
      this.errorMessage =
        "Unable to connect to the payment window. " + this.readError(error);
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
      try {
        message = JSON.parse(message);
      } catch {
        return;
      }
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
        "Your payment wasn’t completed. Verifying your payment…";
      this.closeWindow();
      this.isWorking = false;
      await this.handleCheckStatus();
    }
  };
  async confirm(data) {
    this.confirming = true;
    const scope = this.beginScope();
    this.phase = "Verifying Your Payment…";
    this.isWorking = true;
    this.errorMessage = "";
    try {
      let state = await requestSignatureVerification({
        paymentId: this.pendingOrder.paymentId,
        razorpayPaymentId: data.paymentId,
        razorpaySignature: data.signature
      });
      for (let i = 0; i < 12 && state === "WAITING"; i += 1) {
        this.statusMessage = "Validating payment securely…";
        if (!(await scope.wait(Math.min(600 * (i + 1), 4000)))) return;
        state = await signatureVerificationState({
          paymentId: this.pendingOrder.paymentId,
          razorpayPaymentId: data.paymentId
        });
      }
      if (scope.cancelled) return;
      if (!["VERIFIED", "CONFIRMED"].includes(state))
        throw new Error(
          "Verification is pending. Resume confirmation or check payment status; do not pay again."
        );
      const result = await verifyPayment({
        paymentId: this.pendingOrder.paymentId,
        razorpayPaymentId: data.paymentId
      });
      if (scope.cancelled) return;
      if (!result?.success)
        throw new Error(
          result?.message ||
            "Payment requires reconciliation. Do not pay again."
        );
      this.success(result);
    } catch (error) {
      if (scope.cancelled) return;
      this.errorMessage = this.readError(error);
      this.statusMessage =
        "Confirmation is incomplete. Your payment reference is retained for retry.";
    } finally {
      if (!scope.cancelled) {
        this.confirming = false;
        this.isWorking = false;
        this.closeWindow();
      }
    }
  }
  async handleCheckStatus() {
    if (!this.pendingOrder || this.isWorking || this.detached) return;
    this.isWorking = true;
    this.errorMessage = "";
    const scope = this.beginScope();
    try {
      await this.reconcileCurrent(scope);
    } catch (error) {
      if (!scope.cancelled) this.errorMessage = this.readError(error);
    } finally {
      if (!scope.cancelled) this.isWorking = false;
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
          "Your payment wasn’t completed. Verifying your payment…";
        this.handleCheckStatus();
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
  readError(error) {
    return (
      error?.body?.message || error?.message || "Unable to complete checkout."
    );
  }
}
