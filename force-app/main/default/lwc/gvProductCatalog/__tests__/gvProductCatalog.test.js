import { createElement } from "lwc";
import Component from "c/gvProductCatalog";
import getProducts from "@salesforce/apex/GVProductController.getProducts";
jest.mock(
  "@salesforce/apex/GVProductController.getProducts",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
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
  const el = createElement("c-gv-product-catalog", { is: Component });
  document.body.appendChild(el);
  return el;
};
it("renders wired catalogue data and a product route", async () => {
  const el = mount();
  getProducts.emit([
    {
      Id: "p1",
      Name: "Ruby Ring",
      Price__c: 100,
      Availability_Status__c: "In Stock"
    }
  ]);
  await flush();
  expect(el.shadowRoot.textContent).toContain("Ruby Ring");
  expect(
    el.shadowRoot.querySelector('a[href*="c__productId=p1"]')
  ).not.toBeNull();
});
it("renders a catalogue load failure", async () => {
  const el = mount();
  getProducts.error({ message: "Products unavailable" });
  await flush();
  expect(el.shadowRoot.textContent).toContain("Unable to load jewellery");
});
