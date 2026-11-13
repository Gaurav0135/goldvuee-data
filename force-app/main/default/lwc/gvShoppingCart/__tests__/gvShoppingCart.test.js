import { createElement } from "lwc";
import Cart from "c/gvShoppingCart";
import getCart from "@salesforce/apex/GVCartController.getCart";
import updateCartItem from "@salesforce/apex/GVCartController.updateCartItem";
import removeCartItem from "@salesforce/apex/GVCartController.removeCartItem";
import checkoutRecovery from "@salesforce/apex/GVOnlineCheckoutController.checkoutRecovery";
import cancelUnpaidCheckout from "@salesforce/apex/GVOnlineCheckoutController.cancelUnpaidCheckout";
import beginCheckout from "@salesforce/apex/GVOnlineCheckoutController.beginCheckout";
import { __navigate as navigate } from "lightning/navigation";
jest.mock(
  "@salesforce/apex/GVOnlineCheckoutController.beginCheckout",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock("lightning/navigation", () => {
  const mockNavigate = jest.fn();
  const key = Symbol("Navigate");
  const NavigationMixin = (Base) =>
    class extends Base {
      [key](reference) {
        mockNavigate(reference);
      }
    };
  NavigationMixin.Navigate = key;
  return { NavigationMixin, __navigate: mockNavigate };
});
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
  // eslint-disable-next-line no-await-in-loop -- Settle the sequential LWC render microtasks.
  for (let i = 0; i < 12; i++) await Promise.resolve();
};
async function mount() {
  const el = createElement("c-gv-shopping-cart", { is: Cart });
  document.body.appendChild(el);
  await flush();
  return el;
}
describe("shopping bag recovery", () => {
  it("offers recovery without cancellation or background polling for an expired initialized checkout", async () => {
    checkoutRecovery.mockResolvedValue({
      state: "RecoveryRequired",
      canCancel: false,
      canRecover: true,
      order: { paymentId: "payment1" }
    });
    const el = await mount();
    expect(el.shadowRoot.querySelector(".recovery-cancel")).toBeNull();
    expect(
      el.shadowRoot.querySelector(".recovery-actions .checkout-button")
        .textContent
    ).toContain("Continue Secure Payment");
    expect(checkoutRecovery).toHaveBeenCalledTimes(1);
    expect(el.shadowRoot.textContent).toContain("reservation expired");
    el.shadowRoot.querySelector(".recovery-actions .checkout-button").click();
    await flush();
    expect(beginCheckout).not.toHaveBeenCalled();
    expect(navigate).toHaveBeenCalledTimes(1);
  });
  it("navigates a confirmed checkout to My Orders", async () => {
    checkoutRecovery.mockResolvedValue({
      state: "Confirmed",
      order: { paymentId: "payment1" }
    });
    await mount();
    expect(navigate).toHaveBeenCalledWith({
      type: "standard__webPage",
      attributes: { url: "/goldvuee/my-orders" }
    });
  });
  it("prepares exactly one checkout before navigation despite repeated clicks", async () => {
    let finish;
    beginCheckout.mockImplementation(
      () =>
        new Promise((resolve) => {
          finish = resolve;
        })
    );
    const el = await mount();
    const button = el.shadowRoot.querySelector(".checkout-button");
    button.click();
    button.click();
    await flush();
    expect(beginCheckout).toHaveBeenCalledTimes(1);
    expect(navigate).not.toHaveBeenCalled();
    finish({ orderId: "order1", paymentId: "payment1" });
    await flush();
    expect(navigate).toHaveBeenCalledWith({
      type: "standard__webPage",
      attributes: { url: "/goldvuee/checkout" }
    });
  });
  it("resumes an existing checkout without preparing another order", async () => {
    checkoutRecovery.mockResolvedValue(pending);
    const el = await mount();
    el.shadowRoot.querySelector(".recovery-actions .checkout-button").click();
    await flush();
    expect(beginCheckout).not.toHaveBeenCalled();
    expect(navigate).toHaveBeenCalledWith({
      type: "standard__webPage",
      attributes: { url: "/goldvuee/checkout" }
    });
  });
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
    expect(el.shadowRoot.textContent).toContain("payment needs review");
  });
  it("never cancels on disconnect", async () => {
    checkoutRecovery.mockResolvedValue(pending);
    await mount();
    document.body.replaceChildren();
    expect(cancelUnpaidCheckout).not.toHaveBeenCalled();
  });
});

jest.mock(
  "@salesforce/community/basePath",
  () => ({ __esModule: true, default: "/goldvuee" }),
  {
    virtual: true
  }
);
