import { createElement } from "lwc";
import Component from "c/gvNewArrivals";
import getArrivals from "@salesforce/apex/GVNewArrivalsController.getNewArrivals";
jest.mock(
  "@salesforce/apex/GVNewArrivalsController.getNewArrivals",
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
  const el = createElement("c-gv-new-arrivals", { is: Component });
  document.body.appendChild(el);
  return el;
};
it("renders products and reserved-aware availability", async () => {
  const el = mount();
  getArrivals.emit([
    {
      id: "p1",
      name: "Ruby Ring",
      price: 100,
      availableQuantity: 0,
      category: "Rings"
    }
  ]);
  await flush();
  expect(el.shadowRoot.textContent).toContain("Ruby Ring");
  expect(el.shadowRoot.textContent).not.toContain("Available");
});
it("surfaces catalogue errors", async () => {
  const el = mount();
  getArrivals.error({ message: "Catalogue offline" });
  await flush();
  expect(el.shadowRoot.textContent).toContain("Catalogue offline");
});
