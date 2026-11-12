import { createElement } from "lwc";
import Component from "c/gvCheckout";
import getCart from "@salesforce/apex/GVCartController.getCart";
jest.mock(
  "@salesforce/apex/GVCartController.getCart",
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
};
afterEach(() => {
  while (document.body.firstChild)
    document.body.removeChild(document.body.firstChild);
  jest.clearAllMocks();
});
const mount = () => {
  const el = createElement("c-gv-checkout", { is: Component });
  document.body.appendChild(el);
  return el;
};
it("renders Razorpay-only checkout with server bag totals", async () => {
  getCart.mockResolvedValue({
    cartId: "c1",
    totalAmount: 100,
    itemCount: 1,
    items: [
      {
        Id: "i1",
        Quantity__c: 1,
        Line_Total__c: 100,
        Jewellery_Product__r: { Name: "Ruby Ring" }
      }
    ]
  });
  const el = mount();
  await flush();
  expect(el.shadowRoot.textContent).toContain("Ruby Ring");
  expect(el.shadowRoot.textContent).toContain("Razorpay");
  expect(el.shadowRoot.textContent).not.toContain("Cash on Delivery");
  const child = el.shadowRoot.querySelector("c-goldvuee-razorpay-checkout");
  expect(child).not.toBeNull();
  child.dispatchEvent(
    new CustomEvent("paymentsuccess", {
      detail: {
        success: true,
        orderStatus: "Confirmed",
        paymentStatus: "Paid",
        orderNumber: "GV-1",
        grandTotal: 100
      }
    })
  );
  await flush();
  expect(el.shadowRoot.textContent).toContain("GV-1");
  expect(el.shadowRoot.textContent).toContain("ORDER CONFIRMED");
});
it("does not show confirmation for an unverified callback", async () => {
  getCart.mockResolvedValue({
    items: [{ Id: "i1", Quantity__c: 1 }],
    totalAmount: 100,
    itemCount: 1
  });
  const el = mount();
  await flush();
  el.shadowRoot
    .querySelector("c-goldvuee-razorpay-checkout")
    .dispatchEvent(
      new CustomEvent("paymentsuccess", { detail: { success: false } })
    );
  await flush();
  expect(el.shadowRoot.textContent).not.toContain("ORDER CONFIRMED");
});
