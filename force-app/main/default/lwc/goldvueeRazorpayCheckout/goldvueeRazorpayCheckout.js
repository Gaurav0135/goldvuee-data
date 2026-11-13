
/* eslint-disable no-await-in-loop, @lwc/lwc/no-async-operation -- Bounded payment polling and popup monitoring. */

import { LightningElement, api } from "lwc";

import razorpayKey from "@salesforce/label/c.GoldVuee_Razorpay_Test_Key_ID";
import hostUrl from "@salesforce/label/c.GoldVuee_Razorpay_Host_URL";

import prepareOnlineOrder from "@salesforce/apex/GVOnlineCheckoutController.prepareOnlineOrder";
import checkoutRecovery from "@salesforce/apex/GVOnlineCheckoutController.checkoutRecovery";

import initiatePayment from "@salesforce/apex/GVPaymentController.initiatePayment";
import paymentState from "@salesforce/apex/GVPaymentController.paymentState";

import verifyPayment from "@salesforce/apex/GVPaymentVerificationController.verifyPayment";
import requestSignatureVerification from "@salesforce/apex/GVPaymentVerificationController.requestSignatureVerification";
import signatureVerificationState from "@salesforce/apex/GVPaymentVerificationController.signatureVerificationState";

import communityBasePath from "@salesforce/community/basePath";

import {
  pollingScope,
  reconcile,
  rememberPayment,
  checkoutMessage,
  customerMessage
} from "c/gvCheckoutRecovery";

export default class GoldvueeRazorpayCheckout extends LightningElement {
  // ==========================================
  // PUBLIC CHECKOUT PROPERTIES
  // ==========================================

  @api amount = 0;
  @api shippingAddress = "";
  @api shippingCity = "";
  @api shippingState = "";
  @api shippingPostalCode = "";
  @api shippingCountry = "India";

  // ==========================================
  // PAYMENT STATE
  // ==========================================

  isWorking = false;
  completed = false;
  confirming = false;
  detached = false;

  errorMessage = "";
  statusMessage = "";
  phase = "Ready";

  pendingOrder = null;
  gatewayOrder = null;
  recovery = null;
  confirmationData = null;

  paymentWindow = null;
  nonce = null;

  hostReady = false;
  paymentSent = false;

  closeTimer;
  handshakeTimer;
  scope;

  // ==========================================
  // GETTERS USED BY EXISTING HTML
  // ==========================================

  get ordersUrl() {
    return `${communityBasePath}/my-orders`;
  }

  get hasPendingOrder() {
    return !!this.pendingOrder && !this.completed;
  }

  get showProgress() {
    return this.isWorking;
  }

  get isButtonDisabled() {
    return this.isWorking || this.completed;
  }

  get cancelDisabled() {
    return this.isWorking || this.completed;
  }

  // Cancellation of initialized gateway orders
  // is not performed by a browser action.
  get canCancelCheckout() {
    return false;
  }

  get buttonLabel() {
    if (this.completed) {
      return "Order Confirmed";
    }

    if (this.isWorking) {
      return this.phase;
    }

    if (this.confirmationData) {
      return "Complete Payment Verification";
    }

    const total = Number(
      this.pendingOrder?.grandTotal || this.amount || 0
    );

    const formatted = new Intl.NumberFormat("en-IN", {
      style: "currency",
      currency: "INR"
    }).format(total);

    return `Pay Securely · ${formatted}`;
  }

  // ==========================================
  // COMPONENT LIFECYCLE
  // ==========================================

  connectedCallback() {
    this.detached = false;

    window.addEventListener(
      "message",
      this.handleHostMessage
    );

    // Do not automatically restore an old checkout.
    // The customer starts checkout intentionally.
  }

  disconnectedCallback() {
    this.detached = true;

    this.scope?.cancel();

    window.removeEventListener(
      "message",
      this.handleHostMessage
    );

    this.clearTimers();
  }

  // ==========================================
  // POLLING SCOPE
  // ==========================================

  beginScope() {
    this.scope?.cancel();

    this.scope = pollingScope();

    return this.scope;
  }

  // ==========================================
  // NOTIFY PARENT CHECKOUT
  // ==========================================

  state(locked) {
    if (this.pendingOrder?.paymentId) {
      rememberPayment(this.pendingOrder.paymentId);
    }

    this.dispatchEvent(
      new CustomEvent("checkoutstate", {
        detail: {
          locked: Boolean(locked),
          order: this.pendingOrder
        }
      })
    );
  }

  // ==========================================
  // VALIDATE SHIPPING INFORMATION
  // ==========================================

  validateShipping() {
    const values = [
      this.shippingAddress,
      this.shippingCity,
      this.shippingState,
      this.shippingPostalCode,
      this.shippingCountry
    ];

    if (
      values.some(
        (value) => !String(value || "").trim()
      )
    ) {
      throw new Error(
        "Please complete all delivery information."
      );
    }

    if (
      String(this.shippingCountry)
        .trim()
        .toLowerCase() !== "india" ||
      !/^[1-9][0-9]{5}$/.test(
        String(this.shippingPostalCode).trim()
      )
    ) {
      throw new Error(
        "Enter a valid Indian address and six-digit PIN code."
      );
    }
  }

  // ==========================================
  // PREPARE ORDER
  // ==========================================

  async prepareOrder(scope) {
    if (this.pendingOrder?.paymentId) {
      return this.pendingOrder;
    }

    this.phase = "Preparing Secure Checkout…";

    const order = await prepareOnlineOrder({
      shippingAddress: this.shippingAddress.trim(),
      shippingCity: this.shippingCity.trim(),
      shippingState: this.shippingState.trim(),
      shippingPostalCode: this.shippingPostalCode.trim(),
      shippingCountry: this.shippingCountry.trim()
    });

    if (scope.cancelled || this.detached) {
      return null;
    }

    if (
      !order?.paymentId ||
      !order?.orderId ||
      Number(order.grandTotal) <= 0
    ) {
      throw new Error(
        "Unable to prepare your order."
      );
    }

    this.pendingOrder = order;

    this.state(true);

    return order;
  }

  // ==========================================
  // PAYMENT RECOVERY SNAPSHOT
  // ==========================================

  applyRecovery(result) {
    if (!result) {
      this.statusMessage =
        "We could not confirm the previous payment status. " +
        "You may return to your shopping bag while verification continues.";

      return;
    }

    this.recovery = result;

    if (result.state === "Confirmed") {
      this.success({
        ...result.order,
        success: true
      });

      return;
    }

    if (result.state === "Cancelled") {
      rememberPayment(null);

      this.pendingOrder = null;
      this.gatewayOrder = null;
      this.confirmationData = null;
      this.recovery = null;

      this.state(false);

      this.statusMessage =
        "The previous checkout was cancelled. " +
        "You can start another payment.";

      return;
    }

    this.statusMessage = checkoutMessage(result);
  }

  async reconcileCurrent(scope) {
    if (!this.pendingOrder?.paymentId) {
      return null;
    }

    this.phase = "Verifying Payment…";

    const paymentId = this.pendingOrder.paymentId;

    let result = await checkoutRecovery({
      paymentId
    });

    if (scope.cancelled || this.detached) {
      return null;
    }

    if (
      result.state === "Confirmed" ||
      result.state === "Cancelled" ||
      result.state === "Review"
    ) {
      this.applyRecovery(result);
      return result;
    }

    // A new, uninitialized payment is immediately
    // eligible. No gateway status request is needed.
    if (
      result.canCancel &&
      result.canRetry
    ) {
      this.applyRecovery(result);
      return result;
    }

    // For initialized payments, ask the existing
    // server reconciliation service to determine
    // whether the gateway order can be reused.
    result = await reconcile(paymentId, scope);

    if (!scope.cancelled && !this.detached) {
      this.applyRecovery(result);
    }

    return result;
  }

  // ==========================================
  // START RAZORPAY
  // ==========================================

  handlePay = async () => {
    if (this.isButtonDisabled) {
      return;
    }

    if (
      this.paymentWindow &&
      !this.paymentWindow.closed
    ) {
      this.statusMessage =
        "Complete payment in the open Razorpay window.";

      return;
    }

    this.errorMessage = "";
    this.statusMessage = "";

    try {
      this.validateShipping();

      if (
        !/^rzp_test_[A-Za-z0-9]+$/.test(
          razorpayKey || ""
        )
      ) {
        throw new Error(
          "Razorpay Test Key ID is not configured."
        );
      }

      const url = new URL(hostUrl);

      if (
        url.protocol !== "https:"
      ) {
        throw new Error(
          "Secure Razorpay host URL is invalid."
        );
      }

      // Open popup directly from the click event
      // to avoid browser popup blocking.
      this.openPaymentWindow(url);

    } catch (error) {
      this.errorMessage = this.readError(error);
      this.isWorking = false;
      return;
    }

    this.isWorking = true;
    this.phase = "Preparing Secure Payment…";

    const scope = this.beginScope();

    try {
      if (this.confirmationData) {
        await this.confirm(this.confirmationData);
        return;
      }

      const order = await this.prepareOrder(scope);

      if (!order || scope.cancelled) {
        return;
      }

      // The server decides whether an existing
      // payment is eligible. Do not blindly retry
      // an unresolved gateway payment.
      const recovery = await this.reconcileCurrent(scope);

      if (scope.cancelled || this.completed) {
        return;
      }

      if (!recovery?.canRetry) {
        this.closeWindow();

        this.statusMessage =
          recovery?.message ||
          "The previous payment is being verified. " +
            "You can return to your shopping bag.";

        return;
      }

      this.phase = "Starting Razorpay…";

      let gateway = await initiatePayment({
        paymentId: order.paymentId
      });

      // Wait for the authorized Apex worker
      // to create the gateway order.
      for (
        let i = 0;
        i < 12 &&
        ["Queued", "New"].includes(gateway.state);
        i += 1
      ) {
        if (
          !(await scope.wait(
            Math.min(600 * (i + 1), 4000)
          ))
        ) {
          return;
        }

        gateway = await paymentState({
          paymentId: order.paymentId
        });
      }

      if (scope.cancelled || this.detached) {
        return;
      }

      if (gateway.state === "Confirmed") {
        const snapshot = await checkoutRecovery({
          paymentId: order.paymentId
        });

        this.applyRecovery(snapshot);
        return;
      }

      if (gateway.state === "Review") {
        throw new Error(
          "Payment is being reviewed. Do not start " +
          "another charge for this order."
        );
      }

      if (
        gateway.state !== "Ready" ||
        !/^order_[A-Za-z0-9]+$/.test(
          gateway.razorpayOrderId || ""
        ) ||
        gateway.currencyCode !== "INR" ||
        !Number.isSafeInteger(
          Number(gateway.amountPaise)
        ) ||
        Number(gateway.amountPaise) < 100
      ) {
        throw new Error(
          "Razorpay initialization is not ready. " +
          "Please try again after its status is resolved."
        );
      }

      this.gatewayOrder = gateway;

      this.phase = "Complete Payment in Razorpay";

      this.statusMessage =
        "Complete your payment in the secure Razorpay window.";

      this.sendPaymentToHost();

      // isWorking stays true while the popup is active.

    } catch (error) {
      if (!scope.cancelled) {
        this.errorMessage = this.readError(error);

        this.statusMessage =
          "Payment could not be started or confirmed. " +
          "Your shopping bag remains accessible.";
      }

      this.closeWindow();

    } finally {
      if (
        !scope.cancelled &&
        (
          !this.paymentWindow ||
          this.paymentWindow.closed
        )
      ) {
        this.isWorking = false;
      }

      this.state(false);
    }
  };

  // ==========================================
  // OPEN PAYMENT WINDOW
  // ==========================================

  openPaymentWindow(url) {
    this.closeWindow();

    const bytes = new Uint8Array(16);

    window.crypto.getRandomValues(bytes);

    this.nonce = Array.from(bytes)
      .map((value) =>
        value.toString(16).padStart(2, "0")
      )
      .join("");

    url.searchParams.set(
      "origin",
      window.location.origin
    );

    url.searchParams.set(
      "nonce",
      this.nonce
    );

    this.hostReady = false;
    this.paymentSent = false;
    this.gatewayOrder = null;

    this.paymentWindow = window.open(
      url.toString(),
      "_blank",
      "width=520,height=760"
    );

    if (!this.paymentWindow) {
      throw new Error(
        "Please allow popups to open Razorpay."
      );
    }

    this.watchWindow();
  }

  // ==========================================
  // SEND PAYMENT DATA TO RAZORPAY HOST
  // ==========================================

  sendPaymentToHost() {
    if (
      !this.hostReady ||
      !this.gatewayOrder ||
      !this.paymentWindow ||
      this.paymentWindow.closed ||
      this.paymentSent
    ) {
      return;
    }

    const payload = JSON.stringify({
      source: "GOLDVUEE_CHECKOUT",
      type: "START_PAYMENT",
      nonce: this.nonce,

      data: {
        key: razorpayKey,
        orderId: this.gatewayOrder.razorpayOrderId,
        amount: Number(
          this.gatewayOrder.amountPaise
        )
      }
    });

    try {
      this.paymentWindow.postMessage(
        payload,
        new URL(hostUrl).origin
      );

      this.paymentSent = true;

      clearTimeout(this.handshakeTimer);

    } catch (error) {
      this.errorMessage = this.readError(error);

      this.closeWindow();

      this.isWorking = false;
    }
  }

  // ==========================================
  // RECEIVE RAZORPAY HOST MESSAGES
  // ==========================================

  handleHostMessage = async (event) => {
    if (
      !this.paymentWindow ||
      event.source !== this.paymentWindow ||
      event.origin !== new URL(hostUrl).origin
    ) {
      return;
    }

    let message = event.data;

    if (typeof message === "string") {
      if (message.length > 16384) {
        return;
      }

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
    ) {
      return;
    }

    // ========================================
    // HOST READY
    // ========================================

    if (message.type === "READY") {
      this.hostReady = true;

      clearTimeout(this.handshakeTimer);

      this.sendPaymentToHost();

      return;
    }

    // ========================================
    // PAYMENT SUCCESS MESSAGE
    // ========================================

    if (message.type === "PAYMENT_SUCCESS") {
      if (this.confirming || this.completed) {
        return;
      }

      const data = message.data;

      if (
        !/^pay_[A-Za-z0-9]+$/.test(
          data?.paymentId || ""
        ) ||
        !/^[a-fA-F0-9]{64}$/.test(
          data?.signature || ""
        ) ||
        data?.orderId !==
          this.gatewayOrder?.razorpayOrderId
      ) {
        this.errorMessage =
          "Invalid Razorpay response.";

        return;
      }

      this.confirmationData = data;

      await this.confirm(data);

      return;
    }

    // ========================================
    // PAYMENT FAILED
    // ========================================

    if (
      message.type === "PAYMENT_FAILED" &&
      !this.confirming &&
      !this.completed
    ) {
      // Razorpay can allow another attempt inside
      // its existing checkout popup.
      this.errorMessage =
        "Payment was unsuccessful. " +
        "You can retry inside Razorpay or close the window.";

      this.statusMessage =
        "No inventory has been deducted.";

      return;
    }

    // ========================================
    // PAYMENT HOST ERROR
    // ========================================

    if (
      message.type === "ERROR" &&
      !this.confirming &&
      !this.completed
    ) {
      this.errorMessage = customerMessage(
        { message: message.data?.message },
        "Unable to open secure payment."
      );

      this.closeWindow();

      this.isWorking = false;

      return;
    }

    // ========================================
    // PAYMENT WINDOW DISMISSED
    // ========================================

    if (
      message.type === "PAYMENT_DISMISSED" &&
      !this.confirming &&
      !this.completed
    ) {
      this.closeWindow();

      this.isWorking = false;

      this.statusMessage =
        "Payment window closed. Checking the payment outcome.";

      await this.handleCheckStatus();
    }
  };

  // ==========================================
  // VERIFY SUCCESSFUL PAYMENT
  // ==========================================

  async confirm(data) {
    if (this.confirming || this.completed) {
      return;
    }

    this.confirming = true;
    this.isWorking = true;

    this.phase = "Verifying Secure Payment…";
    this.errorMessage = "";

    const scope = this.beginScope();

    try {
      let verificationState =
        await requestSignatureVerification({
          paymentId: this.pendingOrder.paymentId,
          razorpayPaymentId: data.paymentId,
          razorpaySignature: data.signature
        });

      for (
        let i = 0;
        i < 12 && verificationState === "WAITING";
        i += 1
      ) {
        if (
          !(await scope.wait(
            Math.min(600 * (i + 1), 4000)
          ))
        ) {
          return;
        }

        verificationState =
          await signatureVerificationState({
            paymentId: this.pendingOrder.paymentId,
            razorpayPaymentId: data.paymentId
          });
      }

      if (scope.cancelled) {
        return;
      }

      if (
        !["VERIFIED", "CONFIRMED"].includes(
          verificationState
        )
      ) {
        throw new Error(
          "Payment verification has not completed."
        );
      }

      const result = await verifyPayment({
        paymentId: this.pendingOrder.paymentId,
        razorpayPaymentId: data.paymentId
      });

      if (scope.cancelled) {
        return;
      }

      if (!result?.success) {
        throw new Error(
          result?.message ||
          "Payment confirmation requires review."
        );
      }

      this.success(result);

    } catch (error) {
      if (!scope.cancelled) {
        this.errorMessage = this.readError(error);

        this.statusMessage =
          "Payment confirmation is pending. " +
          "Check My Orders before starting a new charge.";
      }

    } finally {
      if (!scope.cancelled) {
        this.confirming = false;
        this.isWorking = false;
        this.closeWindow();
      }
    }
  }

  // ==========================================
  // AUTOMATIC PAYMENT STATUS CHECK
  // ==========================================

  async handleCheckStatus() {
    if (
      !this.pendingOrder?.paymentId ||
      this.isWorking ||
      this.detached
    ) {
      return;
    }

    this.isWorking = true;
    this.phase = "Checking Payment…";

    const scope = this.beginScope();

    try {
      const result =
        await this.reconcileCurrent(scope);

      if (
        !scope.cancelled &&
        result?.canRetry
      ) {
        this.statusMessage =
          "Your existing payment is eligible to resume. " +
          "Choose Pay Securely to continue.";
      }

    } catch (error) {
      if (!scope.cancelled) {
        this.errorMessage = this.readError(error);
      }

    } finally {
      if (!scope.cancelled) {
        this.isWorking = false;
      }
    }
  }

  // ==========================================
  // VERIFIED PAYMENT SUCCESS
  // ==========================================

  success(result) {
    if (this.completed) {
      return;
    }

    this.completed = true;

    this.closeWindow();

    this.statusMessage =
      "Payment verified. Your order is confirmed.";

    rememberPayment(null);

    this.dispatchEvent(
      new CustomEvent("paymentsuccess", {
        detail: {
          ...result,
          grandTotal: this.pendingOrder?.grandTotal
        }
      })
    );
  }

  // ==========================================
  // BACK BUTTON COMPATIBILITY
  // ==========================================

  @api
  async cancelForBack() {
    this.scope?.cancel();

    // Never cancel a captured or uncertain gateway
    // payment simply because the customer navigates.
    this.closeWindow();

    return {
      state: "Ready",
      message: "You can return to your shopping bag."
    };
  }

  // Existing HTML compatibility.
  async handleCancel() {
    await this.cancelForBack();
  }

  // ==========================================
  // WATCH RAZORPAY POPUP
  // ==========================================

  watchWindow() {
    this.clearTimers();

    this.closeTimer = setInterval(() => {
      if (
        this.paymentWindow?.closed &&
        !this.confirming
      ) {
        this.clearTimers();

        this.paymentWindow = null;
        this.paymentSent = false;
        this.isWorking = false;

        this.statusMessage =
          "Checking the previous payment outcome.";

        this.handleCheckStatus();
      }
    }, 500);

    this.handshakeTimer = setTimeout(() => {
      if (
        !this.hostReady &&
        !this.confirming
      ) {
        this.errorMessage =
          "Razorpay window did not connect. " +
          "Please check popup permissions.";

        this.closeWindow();

        this.isWorking = false;
      }
    }, 15000);
  }

  // ==========================================
  // CLEAR POPUP TIMERS
  // ==========================================

  clearTimers() {
    clearInterval(this.closeTimer);
    clearTimeout(this.handshakeTimer);
  }

  // ==========================================
  // CLOSE POPUP
  // ==========================================

  closeWindow() {
    this.clearTimers();

    if (
      this.paymentWindow &&
      !this.paymentWindow.closed
    ) {
      this.paymentWindow.close();
    }

    this.paymentWindow = null;
    this.paymentSent = false;
  }

  // ==========================================
  // ERROR HELPER
  // ==========================================

  readError(error) {
    const message = String(
      error?.body?.message ||
      error?.message ||
      ""
    );

    if (
      /payment|Razorpay|verification|reconcil/i.test(
        message
      )
    ) {
      return message ||
        "Payment status requires verification.";
    }

    return customerMessage(
      error,
      "Unable to complete checkout. Please try again."
    );
  }
}
