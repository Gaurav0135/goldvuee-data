import { createElement } from "lwc";
import Component from "c/gvShoppingCart";
import getCart from "@salesforce/apex/GVCartController.getCart";
jest.mock(
  "@salesforce/apex/GVCartController.getCart",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/GVCartController.updateCartItem",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/GVCartController.removeCartItem",
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
  const el = createElement("c-gv-shopping-cart", { is: Component });
  document.body.appendChild(el);
  return el;
};
it("displays authoritative cart quantities and totals", async () => {
  getCart.mockResolvedValue({
    cartId: "c1",
    totalAmount: 200,
    itemCount: 2,
    items: [
      {
        Id: "i1",
        Jewellery_Product__c: "p1",
        Jewellery_Product__r: { Name: "Ruby Ring" },
        Quantity__c: 2,
        Unit_Price__c: 100,
        Line_Total__c: 200
      }
    ]
  });
  const el = mount();
  await flush();
  expect(el.shadowRoot.textContent).toContain("Ruby Ring");
  expect(el.shadowRoot.textContent).toContain("200");
});
it("surfaces ownership errors", async () => {
  getCart.mockRejectedValue({ body: { message: "Sign in required" } });
  const el = mount();
  await flush();
  expect(el.shadowRoot.textContent).toContain("Sign in required");
});
