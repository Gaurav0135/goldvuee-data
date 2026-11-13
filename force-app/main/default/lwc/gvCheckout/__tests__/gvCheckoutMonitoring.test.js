import { createElement } from "lwc";
import Checkout from "c/gvCheckout";
import getCart from "@salesforce/apex/GVCartController.getCart";
import loadDelivery from "@salesforce/apex/GVCheckoutController.loadDelivery";
import prepare from "@salesforce/apex/GVCheckoutController.prepareOrder";
import loadOrder from "@salesforce/apex/GVCheckoutController.loadOrder";
import start from "@salesforce/apex/GVRazorpayController.startPayment";
import status from "@salesforce/apex/GVRazorpayController.paymentStatus";
import refresh from "@salesforce/apex/GVRazorpayController.refreshPayment";
import cancel from "@salesforce/apex/GVRazorpayController.cancelPayment";
jest.mock(
  "@salesforce/apex/GVCartController.getCart",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/GVCheckoutController.loadDelivery",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/GVCheckoutController.prepareOrder",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/GVCheckoutController.loadOrder",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/GVRazorpayController.startPayment",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/GVRazorpayController.paymentStatus",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/GVRazorpayController.refreshPayment",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/GVRazorpayController.cancelPayment",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/user/isGuest",
  () => ({ __esModule: true, default: false }),
  { virtual: true }
);
jest.mock(
  "@salesforce/community/basePath",
  () => ({ __esModule: true, default: "/shop/s" }),
  { virtual: true }
);
const delivery = {
  fullName: "A Customer",
  phone: "9876543210",
  street: "1 Gold Road",
  city: "Indore",
  state: "MP",
  postalCode: "452001",
  country: "India"
};
const summary = {
  orderId: "o1",
  paymentId: "p1",
  total: 200,
  delivery: { ...delivery, street: "A Customer\n9876543210\n1 Gold Road" },
  items: []
};
const pending = {
  state: "Ready",
  paymentStatus: "Pending",
  orderId: "o1",
  cartId: "cart1",
  paymentUrl: "https://rzp.io/rzp/test",
  message: "Awaiting verified payment"
};
const flush = async () => {
  for (let i = 0; i < 12; i++) await Promise.resolve();
};
let popup;
beforeEach(() => {
  jest.useFakeTimers();
  jest.setSystemTime(new Date("2026-11-13T18:00:00Z"));
  loadDelivery.mockResolvedValue(delivery);
  prepare.mockResolvedValue(summary);
  loadOrder.mockResolvedValue(summary);
  start.mockResolvedValue({ ...pending, state: "Queued", paymentUrl: null });
  status.mockResolvedValue(pending);
  refresh.mockResolvedValue(pending);
  cancel.mockResolvedValue({
    ...pending,
    state: "Cancelled",
    paymentStatus: "Failed"
  });
  getCart.mockResolvedValue({ cartId: "cart1", itemCount: 2 });
  popup = { closed: false, location: { replace: jest.fn() }, close: jest.fn() };
  jest.spyOn(window, "open").mockReturnValue(popup);
});
afterEach(() => {
  document.body.innerHTML = "";
  sessionStorage.clear();
  jest.clearAllTimers();
  jest.useRealTimers();
  jest.restoreAllMocks();
  jest.resetAllMocks();
});
async function mount() {
  const el = createElement("c-gv-checkout", { is: Checkout });
  document.body.appendChild(el);
  await flush();
  return el;
}
const button = (el, label) =>
  [...el.shadowRoot.querySelectorAll("button")].find((b) =>
    b.textContent.toLowerCase().includes(label)
  );
async function paymentPage() {
  const el = await mount();
  button(el, "continue to order summary").click();
  await flush();
  button(el, "continue to payment").click();
  await flush();
  return el;
}
it("normalizes absent Contact fields and permits editing country", async () => {
  loadDelivery.mockResolvedValue({
    fullName: "A Customer",
    state: undefined,
    city: null
  });
  const el = await mount();
  expect(el.shadowRoot.querySelector('input[name="state"]').value).toBe("");
  expect(el.shadowRoot.querySelector('input[name="city"]').value).toBe("");
  expect(el.shadowRoot.textContent).not.toMatch(/undefined|\u00c2|\ufffd/);
  expect(el.shadowRoot.querySelector('input[name="country"]').readOnly).toBe(
    false
  );
  button(el, "continue to order summary").click();
  await flush();
  expect(prepare).not.toHaveBeenCalled();
  expect(el.shadowRoot.textContent).toContain("Enter a valid Indian mobile number");
});
it("validates mobile length and navigates backwards without losing the address", async () => {
  const el = await mount();
  const phone = el.shadowRoot.querySelector('input[name="phone"]');
  phone.value = "123";
  phone.dispatchEvent(new Event("change"));
  button(el, "continue to order summary").click();
  await flush();
  expect(prepare).not.toHaveBeenCalled();
  phone.value = "9876543210";
  phone.dispatchEvent(new Event("change"));
  await flush();
  button(el, "continue to order summary").click();
  await flush();
  button(el, "continue to payment").click();
  await flush();
  button(el, "back to order summary").click();
  await flush();
  button(el, "change address").click();
  await flush();
  expect(el.shadowRoot.querySelector("textarea").value).toBe(delivery.street);
});
it("does not restore an old pending payment over an independent current bag", async () => {
  sessionStorage.setItem("gvHostedPayment", "old-payment");
  status.mockResolvedValue({ ...pending, cartId: "old-cart" });
  const el = await mount();
  expect(el.shadowRoot.querySelector('input[name="state"]')).not.toBeNull();
  expect(sessionStorage.getItem("gvHostedPayment")).toBeNull();
  expect(el.shadowRoot.textContent).toContain("current bag");
});
it("retries a failed transaction using the existing logical payment attempt", async () => {
  start.mockResolvedValue({
    ...pending,
    lastFailureState: "failed",
    message: "Your last payment attempt failed"
  });
  const el = await paymentPage();
  button(el, "pay now").click();
  await flush();
  expect(el.shadowRoot.textContent).toContain("last payment attempt failed");
  expect(button(el, "pay now").disabled).toBe(false);
  button(el, "retry payment").click();
  await flush();
  expect(start).toHaveBeenCalledTimes(2);
  expect(prepare).toHaveBeenCalledTimes(1);
});
it("prepares a replacement only after server-confirmed cancellation", async () => {
  const el = await paymentPage();
  button(el, "cancel unpaid payment").click();
  await flush();
  prepare.mockResolvedValue({ ...summary, paymentId: "p2" });
  button(el, "retry payment").click();
  await flush();
  expect(prepare).toHaveBeenCalledTimes(2);
  expect(start).not.toHaveBeenCalled();
  expect(sessionStorage.getItem("gvHostedPayment")).toBe("p2");
});
it("opens hosted payment separately and checks verified gateway state", async () => {
  const el = await paymentPage();
  button(el, "pay now").click();
  await flush();
  expect(window.open).toHaveBeenCalledWith("about:blank", "_blank");
  await jest.advanceTimersByTimeAsync(1600);
  expect(popup.location.replace).toHaveBeenCalledWith(pending.paymentUrl);
  await jest.advanceTimersByTimeAsync(6000);
  expect(refresh).toHaveBeenCalledWith({ paymentId: "p1" });
  expect(start).toHaveBeenCalledTimes(1);
});
it("stops waiting at 120 seconds without failing or cancelling the payment", async () => {
  const el = await paymentPage();
  button(el, "pay now").click();
  await flush();
  await jest.advanceTimersByTimeAsync(120000);
  expect(el.shadowRoot.textContent).toContain("Payment not confirmed yet");
  expect(button(el, "pay now").disabled).toBe(false);
  expect(sessionStorage.getItem("gvHostedPayment")).toBe("p1");
  expect(cancel).not.toHaveBeenCalled();
  button(el, "retry payment").click();
  await flush();
  expect(start).toHaveBeenCalledTimes(2);
  expect(start.mock.calls[1][0]).toEqual({ paymentId: "p1" });
  expect(prepare).toHaveBeenCalledTimes(1);
});
it("ends waiting even if a verification request stalls", async () => {
  const el = await paymentPage();
  button(el, "pay now").click();
  await flush();
  await jest.advanceTimersByTimeAsync(1600);
  refresh.mockImplementation(() => new Promise(() => {}));
  await jest.advanceTimersByTimeAsync(118400);
  expect(el.shadowRoot.textContent).toContain("Payment not confirmed yet");
  expect(button(el, "pay now").disabled).toBe(false);
  const checksBeforeRetry = refresh.mock.calls.length;
  refresh.mockResolvedValue(pending);
  button(el, "retry payment").click();
  await flush();
  await jest.advanceTimersByTimeAsync(6500);
  expect(refresh.mock.calls.length).toBeGreaterThan(checksBeforeRetry);
  expect(start.mock.calls[1][0]).toEqual({ paymentId: "p1" });
});
it("shows late server-confirmed success after timeout", async () => {
  const el = await paymentPage();
  button(el, "pay now").click();
  await flush();
  await jest.advanceTimersByTimeAsync(120000);
  refresh.mockResolvedValue({
    ...pending,
    state: "Paid",
    paymentStatus: "Success",
    message: "Payment confirmed"
  });
  button(el, "refresh payment status").click();
  await flush();
  expect(el.shadowRoot.textContent).toContain("Payment confirmed");
  expect(el.shadowRoot.querySelector("c-gv-payment-result")).not.toBeNull();
  expect(el.shadowRoot.textContent).not.toContain("Payment not confirmed yet");
});
