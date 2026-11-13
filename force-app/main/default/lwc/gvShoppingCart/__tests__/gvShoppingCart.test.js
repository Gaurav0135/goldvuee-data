import { createElement } from "lwc";
import Cart from "c/gvShoppingCart";
import getCart from "@salesforce/apex/GVCartController.getCart";
import updateCartItem from "@salesforce/apex/GVCartController.updateCartItem";
import removeCartItem from "@salesforce/apex/GVCartController.removeCartItem";
import checkoutRecovery from "@salesforce/apex/GVOnlineCheckoutController.checkoutRecovery";
import cancelUnpaidCheckout from "@salesforce/apex/GVOnlineCheckoutController.cancelUnpaidCheckout";
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
const cart = {
  cartId: "cart1",
  totalAmount: 900,
  itemCount: 1,
  items: [
    {
      Id: "item1",
      Jewellery_Product__c: "prod1",
      Quantity__c: 1,
      Unit_Price__c: 900,
      Line_Total__c: 900,
      Jewellery_Product__r: { Name: "Gold Ring", Available_Quantity__c: 5 }
    }
  ]
};
const pending = {
  state: "Interrupted",
  canCancel: true,
  order: { paymentId: "payment1" }
};
const flush = async () => {
  for (let i = 0; i < 12; i++) await Promise.resolve();
};
async function mount() {
  const el = createElement("c-gv-shopping-cart", { is: Cart });
  document.body.appendChild(el);
  await flush();
  return el;
}
describe("shopping bag recovery", () => {
  beforeEach(() => {
    getCart.mockResolvedValue(cart);
    checkoutRecovery.mockResolvedValue({ state: "Ready" });
  });
  afterEach(() => {
    document.body.replaceChildren();
    jest.resetAllMocks();
  });
  it("preserves quantity, removal and stock display", async () => {
    const el = await mount();
    expect(el.shadowRoot.textContent).toContain("Available for your bag");
    updateCartItem.mockResolvedValue(cart);
    el.shadowRoot.querySelector('[aria-label="Increase quantity"]').click();
    await flush();
    expect(updateCartItem).toHaveBeenCalledWith({
      cartItemId: "item1",
      quantity: 2
    });
    removeCartItem.mockResolvedValue({ ...cart, items: [], itemCount: 0 });
    el.shadowRoot.querySelector(".remove-button").click();
    await flush();
    expect(removeCartItem).toHaveBeenCalledWith({ cartItemId: "item1" });
  });
  it("shows recovery and disables editing for a pending checkout", async () => {
    checkoutRecovery.mockResolvedValue(pending);
    const el = await mount();
    expect(el.shadowRoot.textContent).toContain(
      "Your previous checkout is waiting."
    );
    expect(el.shadowRoot.querySelector(".remove-button").disabled).toBe(true);
    expect(
      el.shadowRoot.querySelector('[aria-label="Increase quantity"]').disabled
    ).toBe(true);
  });
  it("refreshes and unlocks after server cancellation", async () => {
    checkoutRecovery
      .mockResolvedValueOnce(pending)
      .mockResolvedValue({ state: "Ready" });
    cancelUnpaidCheckout.mockResolvedValue({ state: "Cancelled" });
    const el = await mount();
    el.shadowRoot.querySelector(".recovery-cancel").click();
    await flush();
    expect(cancelUnpaidCheckout).toHaveBeenCalledWith({
      paymentId: "payment1"
    });
    expect(getCart).toHaveBeenCalledTimes(2);
    expect(el.shadowRoot.querySelector(".remove-button").disabled).toBe(false);
  });
  it("keeps editing locked for captured payment review", async () => {
    checkoutRecovery.mockResolvedValue(pending);
    cancelUnpaidCheckout.mockResolvedValue({
      ...pending,
      state: "Review",
      message: "Please do not pay again."
    });
    const el = await mount();
    el.shadowRoot.querySelector(".recovery-cancel").click();
    await flush();
    expect(el.shadowRoot.querySelector(".remove-button").disabled).toBe(true);
    expect(getCart).toHaveBeenCalledTimes(1);
    expect(el.shadowRoot.textContent).toContain("Please do not pay again.");
  });
  it("never cancels on disconnect", async () => {
    checkoutRecovery.mockResolvedValue(pending);
    await mount();
    document.body.replaceChildren();
    expect(cancelUnpaidCheckout).not.toHaveBeenCalled();
  });
});

jest.mock("@salesforce/community/basePath", () => ({ default: "/goldvuee" }), {
  virtual: true
});
