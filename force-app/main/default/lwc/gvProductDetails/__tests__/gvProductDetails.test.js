import { createElement } from "lwc";
import Component from "c/gvProductDetails";
import getProduct from "@salesforce/apex/GVProductController.getProductById";
jest.mock(
  "@salesforce/apex/GVProductController.getProductById",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/GVCartController.addToCart",
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
  const el = createElement("c-gv-product-details", { is: Component });
  el.recordId = "p1";
  document.body.appendChild(el);
  return el;
};
it("renders a product from the server", async () => {
  const el = mount();
  getProduct.emit({
    Id: "p1",
    Name: "Ruby Ring",
    Price__c: 100,
    Available_Quantity__c: 2,
    Stock_Quantity__c: 2
  });
  await flush();
  expect(el.shadowRoot.textContent).toContain("Ruby Ring");
});
it("shows product lookup errors", async () => {
  const el = mount();
  getProduct.error({ message: "Product unavailable" });
  await flush();
  expect(el.shadowRoot.textContent).toContain("Product unavailable");
});
