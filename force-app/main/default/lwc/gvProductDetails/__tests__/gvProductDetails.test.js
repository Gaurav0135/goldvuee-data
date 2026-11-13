import { createElement } from "lwc";
import Product from "c/gvProductDetails";
import getProductById from "@salesforce/apex/GVProductController.getProductById";
import addToCart from "@salesforce/apex/GVCartController.addToCart";
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
  for (let i = 0; i < 12; i++) await Promise.resolve();
};
async function mount() {
  const el = createElement("c-gv-product-details", { is: Product });
  el.recordId = "product1";
  document.body.appendChild(el);
  await flush();
  getProductById.emit({
    Id: "product1",
    Name: "Gold Ring",
    Stock_Quantity__c: 10,
    Available_Quantity__c: 10,
    Price__c: 900,
    Active__c: true
  });
  await flush();
  return el;
}
describe("add to bag", () => {
  it("disables adding when physical stock is fully reserved", async () => {
    const el = await mount();
    getProductById.emit({
      Id: "product1",
      Name: "Gold Ring",
      Stock_Quantity__c: 10,
      Available_Quantity__c: 0,
      Price__c: 900,
      Active__c: true
    });
    await flush();
    expect(el.shadowRoot.querySelector(".add-to-cart-button").disabled).toBe(
      true
    );
    expect(addToCart).not.toHaveBeenCalled();
  });
  beforeEach(() => {
    jest.spyOn(console, "log").mockImplementation(() => {});
    jest.spyOn(console, "error").mockImplementation(() => {});
  });
  afterEach(() => {
    document.body.replaceChildren();
    jest.restoreAllMocks();
    jest.resetAllMocks();
  });
  it("sends only product and quantity once while the cart request is outstanding", async () => {
    let finish;
    addToCart.mockImplementation(
      () =>
        new Promise((resolve) => {
          finish = resolve;
        })
    );
    const el = await mount();
    const button = el.shadowRoot.querySelector(".add-to-cart-button");
    button.click();
    button.click();
    await flush();
    expect(addToCart).toHaveBeenCalledTimes(1);
    expect(addToCart).toHaveBeenCalledWith({
      productId: "product1",
      quantity: 1
    });
    finish({ cartId: "bag1" });
    await flush();
    expect(el.shadowRoot.querySelector(".cart-success").textContent).toContain(
      "added to your cart"
    );
  });
  it("shows stock feedback without exposing a raw server implementation error", async () => {
    addToCart.mockRejectedValue({
      body: {
        message:
          "Insufficient available stock in GVCartController.validateProduct"
      }
    });
    const el = await mount();
    el.shadowRoot.querySelector(".add-to-cart-button").click();
    await flush();
    expect(el.shadowRoot.querySelector(".cart-error").textContent).toContain(
      "requested quantity is unavailable"
    );
    expect(el.shadowRoot.textContent).not.toContain("GVCartController");
  });
});
