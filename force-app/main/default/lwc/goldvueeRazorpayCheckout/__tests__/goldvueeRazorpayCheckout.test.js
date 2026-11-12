import { createElement } from "lwc";
import Component from "c/goldvueeRazorpayCheckout";
import prepare from "@salesforce/apex/GVOnlineCheckoutController.prepareOnlineOrder";
import resume from "@salesforce/apex/GVOnlineCheckoutController.resumeCheckout";
import initiate from "@salesforce/apex/GVPaymentController.initiatePayment";
import requestSignature from "@salesforce/apex/GVPaymentVerificationController.requestSignatureVerification";
import verify from "@salesforce/apex/GVPaymentVerificationController.verifyPayment";
jest.mock(
  "@salesforce/label/c.GoldVuee_Razorpay_Test_Key_ID",
  () => ({ default: "rzp_test_fixture" }),
  { virtual: true }
);
jest.mock(
  "@salesforce/label/c.GoldVuee_Razorpay_Host_URL",
  () => ({ default: "https://example.vf.force.com/apex/GVRazorpayHost" }),
  { virtual: true }
);
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
  "@salesforce/apex/GVPaymentController.paymentState",
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
  "@salesforce/apex/GVPaymentVerificationController.signatureVerificationState",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
const flush = async () => {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
};
const order = {
  orderId: "o1",
  paymentId: "p1",
  orderNumber: "GV-1",
  grandTotal: 900
};
let popup;
const mount = () => {
  const el = createElement("c-goldvuee-razorpay-checkout", { is: Component });
  Object.assign(el, {
    shippingAddress: "10 Gold Street",
    shippingCity: "Indore",
    shippingState: "MP",
    shippingPostalCode: "452001",
    shippingCountry: "India"
  });
  document.body.appendChild(el);
  return el;
};
const pay = (el) => el.shadowRoot.querySelector(".razorpay-pay-button");
beforeEach(() => {
  jest.useFakeTimers();
  resume.mockResolvedValue(null);
  prepare.mockResolvedValue(order);
  popup = {
    closed: false,
    postMessage: jest.fn(),
    close: jest.fn(function () {
      this.closed = true;
    })
  };
  jest.spyOn(window, "open").mockReturnValue(popup);
  initiate.mockResolvedValue({
    state: "Ready",
    razorpayOrderId: "order_test",
    amountPaise: 90000,
    currencyCode: "INR"
  });
});
afterEach(() => {
  while (document.body.firstChild)
    document.body.removeChild(document.body.firstChild);
  jest.clearAllTimers();
  jest.useRealTimers();
  jest.restoreAllMocks();
  jest.resetAllMocks();
});
it("prepares and displays authoritative total before opening payment", async () => {
  const el = mount();
  await flush();
  pay(el).click();
  await flush();
  expect(prepare).toHaveBeenCalledTimes(1);
  expect(pay(el).textContent).toContain("900");
  expect(window.open).not.toHaveBeenCalled();
});
it("rejects invalid shipping without creating an order", async () => {
  const el = mount();
  el.shippingPostalCode = "000000";
  await flush();
  pay(el).click();
  await flush();
  expect(prepare).not.toHaveBeenCalled();
  expect(el.shadowRoot.textContent).toContain("valid Indian");
});
it("prevents duplicate preparation while the request is pending", async () => {
  prepare.mockReturnValue(new Promise(() => {}));
  const el = mount();
  await flush();
  pay(el).click();
  await flush();
  pay(el).click();
  expect(prepare).toHaveBeenCalledTimes(1);
  expect(pay(el).disabled).toBe(true);
});
it("restores pending checkout after browser reload", async () => {
  resume.mockResolvedValue(order);
  const el = mount();
  await flush();
  expect(pay(el).textContent).toContain("900");
  expect(el.shadowRoot.querySelector(".razorpay-status-button")).not.toBeNull();
});
it("handles popup blocking without charging or creating another checkout", async () => {
  resume.mockResolvedValue(order);
  window.open.mockReturnValue(null);
  const el = mount();
  await flush();
  pay(el).click();
  await flush();
  expect(el.shadowRoot.textContent).toContain("Allow popups");
  expect(initiate).not.toHaveBeenCalled();
  expect(pay(el).disabled).toBe(false);
});
it("ignores messages from an untrusted origin and recovers a closed window", async () => {
  resume.mockResolvedValue(order);
  const el = mount();
  await flush();
  pay(el).click();
  await flush();
  window.dispatchEvent(
    new MessageEvent("message", {
      origin: "https://attacker.test",
      source: popup,
      data: { source: "GOLDVUEE_RAZORPAY_HOST", type: "PAYMENT_SUCCESS" }
    })
  );
  await flush();
  expect(requestSignature).not.toHaveBeenCalled();
  expect(verify).not.toHaveBeenCalled();
  popup.closed = true;
  jest.advanceTimersByTime(600);
  await flush();
  expect(pay(el).disabled).toBe(false);
  expect(el.shadowRoot.textContent).toContain("Check payment status");
});
it("confirms only after server signature and captured-payment verification", async () => {
  resume.mockResolvedValue(order);
  requestSignature.mockResolvedValue("VERIFIED");
  verify.mockResolvedValue({
    success: true,
    orderStatus: "Confirmed",
    paymentStatus: "Paid",
    orderNumber: "GV-1"
  });
  const el = mount();
  const success = jest.fn();
  el.addEventListener("paymentsuccess", success);
  await flush();
  pay(el).click();
  await flush();
  const nonce = new URL(window.open.mock.calls[0][0]).searchParams.get("nonce");
  const message = (type, data) =>
    window.dispatchEvent(
      new MessageEvent("message", {
        origin: "https://example.vf.force.com",
        source: popup,
        data: JSON.stringify({ source: "GOLDVUEE_RAZORPAY_HOST", nonce, type, data })
      })
    );
  message("READY");
  await flush();
  expect(popup.postMessage).toHaveBeenCalledTimes(1);
  const [payload, targetOrigin] = popup.postMessage.mock.calls[0];
  expect(typeof payload).toBe("string");
  expect(JSON.parse(payload)).toEqual({source:"GOLDVUEE_CHECKOUT",type:"START_PAYMENT",nonce,data:{key:"rzp_test_fixture",orderId:"order_test",amount:90000}});
  expect(targetOrigin).toBe("https://example.vf.force.com");
  message("PAYMENT_SUCCESS", {
    paymentId: "pay_test",
    orderId: "order_test",
    signature: "a".repeat(64)
  });
  await flush();
  expect(requestSignature).toHaveBeenCalledWith({
    paymentId: "p1",
    razorpayPaymentId: "pay_test",
    razorpaySignature: "a".repeat(64)
  });
  expect(verify).toHaveBeenCalledTimes(1);
  expect(success).toHaveBeenCalledTimes(1);
  expect(pay(el).disabled).toBe(true);
});
it("retains payment proof and offers confirmation retry after server failure", async () => {
  resume.mockResolvedValue(order);
  requestSignature.mockResolvedValue("VERIFIED");
  verify.mockRejectedValue({
    body: { message: "Gateway temporarily unavailable" }
  });
  const el = mount();
  await flush();
  pay(el).click();
  await flush();
  const nonce = new URL(window.open.mock.calls[0][0]).searchParams.get("nonce");
  window.dispatchEvent(
    new MessageEvent("message", {
      origin: "https://example.vf.force.com",
      source: popup,
      data: {
        source: "GOLDVUEE_RAZORPAY_HOST",
        nonce,
        type: "PAYMENT_SUCCESS",
        data: {
          paymentId: "pay_test",
          orderId: "order_test",
          signature: "a".repeat(64)
        }
      }
    })
  );
  await flush();
  expect(pay(el).textContent).toContain("Resume Payment Confirmation");
  expect(el.shadowRoot.textContent).toContain(
    "Gateway temporarily unavailable"
  );
  const opened = window.open.mock.calls.length;
  pay(el).click();
  await flush();
  expect(window.open).toHaveBeenCalledTimes(opened);
  expect(verify).toHaveBeenCalledTimes(2);
});

it("uses clone-safe messages when the browser rejects object payloads", async () => {
  resume.mockResolvedValue(order);
  popup.postMessage.mockImplementation(payload => {
    if (typeof payload !== "string") throw new DOMException("Object could not be cloned", "DataCloneError");
  });
  const el=mount();await flush();pay(el).click();await flush();
  const nonce=new URL(window.open.mock.calls[0][0]).searchParams.get("nonce");
  window.dispatchEvent(new MessageEvent("message",{origin:"https://example.vf.force.com",source:popup,data:JSON.stringify({source:"GOLDVUEE_RAZORPAY_HOST",nonce,type:"READY"})}));
  await flush();expect(popup.postMessage).toHaveBeenCalledTimes(1);expect(popup.close).not.toHaveBeenCalled();expect(pay(el).disabled).toBe(true);
});

it("recovers a send failure delivered by the asynchronous READY event", async () => {
  resume.mockResolvedValue(order);popup.postMessage.mockImplementation(()=>{throw new Error("Message delivery failed");});
  const el=mount();await flush();pay(el).click();await flush();
  const nonce=new URL(window.open.mock.calls[0][0]).searchParams.get("nonce");
  window.dispatchEvent(new MessageEvent("message",{origin:"https://example.vf.force.com",source:popup,data:JSON.stringify({source:"GOLDVUEE_RAZORPAY_HOST",nonce,type:"READY"})}));
  await flush();expect(el.shadowRoot.textContent).toContain("Unable to connect to the payment window");expect(pay(el).disabled).toBe(false);expect(popup.close).toHaveBeenCalledTimes(1);
});

it("ignores malformed serialized host messages", async () => {
  resume.mockResolvedValue(order);const el=mount();await flush();pay(el).click();await flush();
  window.dispatchEvent(new MessageEvent("message",{origin:"https://example.vf.force.com",source:popup,data:"{invalid JSON"}));await flush();
  expect(popup.postMessage).not.toHaveBeenCalled();expect(requestSignature).not.toHaveBeenCalled();
});
