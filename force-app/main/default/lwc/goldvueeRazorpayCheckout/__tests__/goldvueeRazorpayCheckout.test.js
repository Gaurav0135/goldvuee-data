import { createElement } from "lwc";
import Payment from "c/goldvueeRazorpayCheckout";
import prepare from "@salesforce/apex/GVOnlineCheckoutController.prepareOnlineOrder";
import resume from "@salesforce/apex/GVOnlineCheckoutController.resumeCheckout";
import recovery from "@salesforce/apex/GVOnlineCheckoutController.checkoutRecovery";
import cancel from "@salesforce/apex/GVOnlineCheckoutController.cancelUnpaidCheckout";
import request from "@salesforce/apex/GVOnlineCheckoutController.requestReconciliation";
import initiate from "@salesforce/apex/GVPaymentController.initiatePayment";
import verify from "@salesforce/apex/GVPaymentVerificationController.verifyPayment";
import signature from "@salesforce/apex/GVPaymentVerificationController.requestSignatureVerification";
jest.mock(
  "@salesforce/apex/GVOnlineCheckoutController.prepareOnlineOrder",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/GVOnlineCheckoutController.resumeCheckout",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/GVOnlineCheckoutController.checkoutRecovery",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/GVOnlineCheckoutController.cancelUnpaidCheckout",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/GVOnlineCheckoutController.requestReconciliation",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/GVPaymentController.initiatePayment",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/GVPaymentVerificationController.verifyPayment",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/GVPaymentVerificationController.requestSignatureVerification",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/label/c.GoldVuee_Razorpay_Test_Key_ID",
  () => ({ default: "rzp_test_UnitTest" }),
  { virtual: true }
);
jest.mock(
  "@salesforce/label/c.GoldVuee_Razorpay_Host_URL",
  () => ({ default: "https://example.vf.force.com/apex/GVRazorpayHost" }),
  { virtual: true }
);
const order = {
  paymentId: "payment1",
  orderId: "order1",
  orderNumber: "GV001",
  shippingAddress: "Gold Street",
  shippingCity: "Indore",
  shippingState: "MP",
  shippingPostalCode: "452001",
  shippingCountry: "India",
  grandTotal: 900
};
const unpaid = { state: "Interrupted", canCancel: true, canRetry: true, order };
const flush = async () => {
  // eslint-disable-next-line no-await-in-loop -- Settle the sequential LWC render microtasks.
  for (let i = 0; i < 20; i++) await Promise.resolve();
};
let popup;
async function mount() {
  const el = createElement("c-goldvuee-razorpay-checkout", { is: Payment });
  Object.assign(el, {
    amount: 999,
    shippingAddress: "Gold Street",
    shippingCity: "Indore",
    shippingState: "MP",
    shippingPostalCode: "452001",
    shippingCountry: "India"
  });
  document.body.appendChild(el);
  await flush();
  return el;
}
async function send(type, data = {}) {
  const nonce = new URL(window.open.mock.calls[0][0]).searchParams.get("nonce");
  // eslint-disable-next-line @lwc/lwc/prefer-custom-event -- Simulate the browser's native message event.
  const event = new Event("message");
  Object.assign(event, {
    source: popup,
    origin: "https://example.vf.force.com",
    data: { source: "GOLDVUEE_RAZORPAY_HOST", nonce, type, data }
  });
  window.dispatchEvent(event);
  await flush();
}
describe("secure payment recovery", () => {
  it("recovers on explicit payment click only and reuses one gateway window despite double click", async () => {
    resume.mockResolvedValue(order);
    const expired = {
      state: "RecoveryRequired",
      canCancel: false,
      canRetry: false,
      canRecover: true,
      order
    };
    recovery.mockResolvedValue(expired);
    const el = await mount();
    expect(request).not.toHaveBeenCalled();
    expect(el.shadowRoot.querySelector(".razorpay-status-button")).toBeNull();
    const button = el.shadowRoot.querySelector(".razorpay-pay-button");
    expect(button.textContent).toContain("Continue Secure Payment");
    button.click();
    button.click();
    await flush();
    expect(request).toHaveBeenCalledTimes(1);
    recovery.mockResolvedValue({ ...unpaid, canCancel: false });
    await jest.advanceTimersByTimeAsync(600);
    await flush();
    expect(window.open).toHaveBeenCalledTimes(1);
    expect(initiate).toHaveBeenCalledTimes(1);
    expect(initiate).toHaveBeenCalledWith({ paymentId: order.paymentId });
    expect(prepare).not.toHaveBeenCalled();
    await send("READY");
    expect(JSON.parse(popup.postMessage.mock.calls[0][0])).toEqual(
      expect.objectContaining({
        type: "START_PAYMENT",
        data: expect.objectContaining({
          orderId: "order_Gateway",
          amount: 90000
        })
      })
    );
  });
  it("stops recovery when stock is unavailable without initializing Razorpay", async () => {
    resume.mockResolvedValue(order);
    recovery.mockResolvedValue({
      state: "StockUnavailable",
      canCancel: false,
      canRetry: false,
      canRecover: true,
      order
    });
    const el = await mount();
    expect(request).not.toHaveBeenCalled();
    el.shadowRoot.querySelector(".razorpay-pay-button").click();
    await flush();
    await jest.advanceTimersByTimeAsync(600);
    await flush();
    const reads = recovery.mock.calls.length;
    await jest.advanceTimersByTimeAsync(30000);
    expect(recovery).toHaveBeenCalledTimes(reads);
    expect(initiate).not.toHaveBeenCalled();
    expect(el.shadowRoot.textContent).toContain("currently unavailable");
  });
  it("unlocks delivery after a failed draft save without initiating payment", async () => {
    resume.mockResolvedValue({ ...order, shippingAddress: null });
    prepare.mockRejectedValue({
      body: {
        message: "Please complete all delivery information. GVCheckoutEngine"
      }
    });
    const el = await mount();
    const state = jest.fn();
    el.addEventListener("checkoutstate", state);
    el.shadowRoot.querySelector(".razorpay-pay-button").click();
    await flush();
    expect(state.mock.calls[state.mock.calls.length - 1][0].detail.locked).toBe(
      false
    );
    expect(initiate).not.toHaveBeenCalled();
    expect(el.shadowRoot.textContent).not.toContain("GVCheckoutEngine");
  });
  it("saves delivery on a restored draft before enabling payment without another checkout", async () => {
    resume.mockResolvedValue({ ...order, shippingAddress: null });
    const el = await mount();
    expect(
      el.shadowRoot.querySelector(".razorpay-pay-button").textContent
    ).toContain("Continue to Secure Payment");
    el.shadowRoot.querySelector(".razorpay-pay-button").click();
    await flush();
    expect(prepare).toHaveBeenCalledTimes(1);
    expect(initiate).not.toHaveBeenCalled();
    expect(
      el.shadowRoot.querySelector(".razorpay-pay-button").textContent
    ).toContain("900.00");
    expect(el.shadowRoot.textContent).not.toContain(
      "Resume Payment Verification"
    );
  });
  it("rechecks expired UI eligibility and never initializes another payment while verification is uncertain", async () => {
    resume.mockResolvedValue(order);
    const el = await mount();
    recovery.mockResolvedValue({
      ...unpaid,
      state: "Uncertain",
      canCancel: false,
      canRetry: false
    });
    el.shadowRoot.querySelector(".razorpay-pay-button").click();
    await flush();
    await send("READY");
    await jest.advanceTimersByTimeAsync(21000);
    await flush();
    expect(initiate).not.toHaveBeenCalled();
    expect(prepare).not.toHaveBeenCalled();
    expect(cancel).not.toHaveBeenCalled();
    expect(popup.close).not.toHaveBeenCalled();
    expect(el.shadowRoot.textContent).toContain("Please do not pay again yet.");
  });
  it("keeps the host open when initialization is rejected and preserves recovery", async () => {
    resume.mockResolvedValue(order);
    const el = await mount();
    initiate.mockRejectedValue({
      body: {
        message: "Verify your existing payment before resuming secure payment."
      }
    });
    el.shadowRoot.querySelector(".razorpay-pay-button").click();
    await flush();
    expect(popup.close).not.toHaveBeenCalled();
    expect(el.shadowRoot.textContent).toContain("Checking payment securely");
    expect(prepare).not.toHaveBeenCalled();
    expect(cancel).not.toHaveBeenCalled();
  });
  it("keeps an initialized payment modal open on failure and prevents a second window", async () => {
    resume.mockResolvedValue(order);
    const el = await mount();
    el.shadowRoot.querySelector(".razorpay-pay-button").click();
    await flush();
    await send("READY");
    await send("PAYMENT_FAILED");
    expect(popup.close).not.toHaveBeenCalled();
    expect(el.shadowRoot.textContent).toContain(
      "retry in the secure payment window"
    );
    el.shadowRoot.querySelector(".razorpay-pay-button").click();
    await flush();
    expect(window.open).toHaveBeenCalledTimes(1);
    expect(verify).not.toHaveBeenCalled();
  });
  it("does not time out a ready host while gateway initialization is still pending", async () => {
    resume.mockResolvedValue(order);
    const el = await mount();
    let complete;
    initiate.mockImplementation(
      () =>
        new Promise((resolve) => {
          complete = resolve;
        })
    );
    el.shadowRoot.querySelector(".razorpay-pay-button").click();
    await flush();
    await send("READY");
    await jest.advanceTimersByTimeAsync(20000);
    expect(popup.close).not.toHaveBeenCalled();
    complete({
      state: "Ready",
      razorpayOrderId: "order_Gateway",
      currencyCode: "INR",
      amountPaise: 90000
    });
    await flush();
    expect(popup.postMessage).toHaveBeenCalledTimes(1);
    expect(JSON.parse(popup.postMessage.mock.calls[0][0]).data).toEqual({
      key: "rzp_test_UnitTest",
      orderId: "order_Gateway",
      amount: 90000
    });
  });
  it("retains the host error instead of closing the diagnostic window", async () => {
    resume.mockResolvedValue(order);
    const el = await mount();
    el.shadowRoot.querySelector(".razorpay-pay-button").click();
    await flush();
    await send("READY");
    await send("ERROR", { message: "Razorpay library unavailable." });
    expect(popup.close).not.toHaveBeenCalled();
    expect(el.shadowRoot.textContent).toContain("Checking payment securely");
    expect(cancel).not.toHaveBeenCalled();
  });
  it("dispatches confirmation once after verified server success, even with duplicate callbacks", async () => {
    resume.mockResolvedValue(order);
    const el = await mount();
    const success = jest.fn();
    el.addEventListener("paymentsuccess", success);
    el.shadowRoot.querySelector(".razorpay-pay-button").click();
    await flush();
    await send("READY");
    signature.mockResolvedValue("VERIFIED");
    verify.mockResolvedValue({
      success: true,
      orderStatus: "Confirmed",
      paymentStatus: "Paid"
    });
    const data = {
      paymentId: "pay_Test",
      orderId: "order_Gateway",
      signature: "a".repeat(64)
    };
    await send("PAYMENT_SUCCESS", data);
    await send("PAYMENT_SUCCESS", data);
    expect(success).toHaveBeenCalledTimes(1);
    expect(verify).toHaveBeenCalledTimes(1);
  });
  beforeEach(() => {
    jest.useFakeTimers();
    resume.mockResolvedValue(null);
    recovery.mockResolvedValue(unpaid);
    request.mockResolvedValue();
    prepare.mockResolvedValue(order);
    popup = {
      closed: false,
      close: jest.fn(() => {
        popup.closed = true;
      }),
      postMessage: jest.fn()
    };
    window.open = jest.fn(() => popup);
    initiate.mockResolvedValue({
      state: "Ready",
      razorpayOrderId: "order_Gateway",
      currencyCode: "INR",
      amountPaise: 90000
    });
  });
  afterEach(() => {
    document.body.replaceChildren();
    window.sessionStorage.clear();
    jest.clearAllTimers();
    jest.useRealTimers();
    jest.resetAllMocks();
  });
  it("prepares once, prevents duplicate clicks and displays the server total", async () => {
    const el = await mount();
    const button = el.shadowRoot.querySelector(".razorpay-pay-button");
    button.click();
    button.click();
    await flush();
    expect(prepare).toHaveBeenCalledTimes(1);
    expect(button.textContent).toContain("900.00");
    expect(button.textContent).not.toContain("999");
    expect(el.shadowRoot.textContent).not.toContain("Check Payment Status");
    expect(initiate).not.toHaveBeenCalled();
  });
  it("restores without preparing another order or reserving stock", async () => {
    resume.mockResolvedValue(order);
    await mount();
    expect(prepare).not.toHaveBeenCalled();
    expect(initiate).not.toHaveBeenCalled();
    expect(recovery).toHaveBeenCalledWith({ paymentId: "payment1" });
  });
  it("automatically reconciles an initialized checkout and confirms only server success", async () => {
    resume.mockResolvedValue(order);
    recovery.mockResolvedValueOnce({
      ...unpaid,
      canCancel: false,
      canRetry: false,
      state: "Uncertain"
    });
    const el = await mount();
    const success = jest.fn();
    el.addEventListener("paymentsuccess", success);
    expect(request).toHaveBeenCalledTimes(1);
    recovery.mockResolvedValue({
      state: "Confirmed",
      order: { ...order, orderStatus: "Confirmed", paymentStatus: "Paid" }
    });
    await jest.advanceTimersByTimeAsync(600);
    await flush();
    expect(success).toHaveBeenCalledTimes(1);
    expect(prepare).not.toHaveBeenCalled();
  });
  it("stops polling on disconnect and never cancels on unmount", async () => {
    resume.mockResolvedValue(order);
    recovery.mockResolvedValue({
      ...unpaid,
      canCancel: false,
      state: "Uncertain"
    });
    const el = await mount();
    const before = recovery.mock.calls.length;
    el.remove();
    await jest.advanceTimersByTimeAsync(30000);
    await flush();
    expect(recovery).toHaveBeenCalledTimes(before);
    expect(cancel).not.toHaveBeenCalled();
  });
  it("reconciles dismissal without reporting payment success or making another order", async () => {
    resume.mockResolvedValue(order);
    const el = await mount();
    const success = jest.fn();
    el.addEventListener("paymentsuccess", success);
    el.shadowRoot.querySelector(".razorpay-pay-button").click();
    await flush();
    await send("READY");
    recovery.mockResolvedValue({
      ...unpaid,
      state: "Uncertain",
      canCancel: false,
      canRetry: false
    });
    await send("PAYMENT_DISMISSED");
    expect(request).toHaveBeenCalledTimes(1);
    expect(success).not.toHaveBeenCalled();
    expect(verify).not.toHaveBeenCalled();
    expect(prepare).not.toHaveBeenCalled();
  });
  it("never trusts popup success when server verification fails", async () => {
    resume.mockResolvedValue(order);
    const el = await mount();
    const success = jest.fn();
    el.addEventListener("paymentsuccess", success);
    el.shadowRoot.querySelector(".razorpay-pay-button").click();
    await flush();
    await send("READY");
    signature.mockResolvedValue("VERIFIED");
    verify.mockResolvedValue({
      success: false,
      message: "Payment requires review."
    });
    await send("PAYMENT_SUCCESS", {
      paymentId: "pay_Test",
      orderId: "order_Gateway",
      signature: "a".repeat(64)
    });
    expect(verify).toHaveBeenCalledTimes(1);
    expect(success).not.toHaveBeenCalled();
    expect(el.shadowRoot.textContent).toContain("Checking payment securely");
  });
  it("leaves an uncertain cancellation locked with a recovery path", async () => {
    resume.mockResolvedValue(order);
    const el = await mount();
    cancel.mockResolvedValue({
      ...unpaid,
      state: "Review",
      canCancel: false,
      canRetry: false,
      message: "Please do not pay again."
    });
    const result = await el.cancelForBack();
    await flush();
    expect(result.state).toBe("Review");
    expect(el.shadowRoot.textContent).toContain("payment needs review");
    expect(el.shadowRoot.querySelector(".orders-link")).not.toBeNull();
  });
});

jest.mock("@salesforce/community/basePath", () => ({ default: "/goldvuee" }), {
  virtual: true
});
