import { createElement } from "lwc";
import Cart from "c/gvCart";
import getCart from "@salesforce/apex/GVCartController.getCart";
import update from "@salesforce/apex/GVCartController.updateCartItem";
import remove from "@salesforce/apex/GVCartController.removeCartItem";
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
  "@salesforce/user/isGuest",
  () => ({ __esModule: true, default: false }),
  { virtual: true }
);
jest.mock(
  "@salesforce/community/basePath",
  () => ({ __esModule: true, default: "/shop/s" }),
  { virtual: true }
);
const flush = () =>
  Array.from({ length: 8 }).reduce(
    (p) => p.then(() => Promise.resolve()),
    Promise.resolve()
  );
const cart = {
  cartId: "bag",
  itemCount: 2,
  totalAmount: 200,
  items: [
    {
      lineId: "line1",
      productId: "product1",
      name: "Gold ring",
      imageUrl: "https://example.com/ring.jpg",
      quantity: 2,
      unitPrice: 100,
      lineTotal: 200,
      available: true
    }
  ]
};
afterEach(() => {
  document.body.replaceChildren();
  jest.clearAllMocks();
});
async function mount() {
  getCart.mockResolvedValue(cart);
  const element = createElement("c-gv-cart", { is: Cart });
  document.body.appendChild(element);
  await flush();
  return element;
}
it("renders server products and totals with community navigation", async () => {
  const element = await mount();
  expect(element.shadowRoot.textContent).toContain("Gold ring");
  expect(
    element.shadowRoot.querySelector("a.button").getAttribute("href")
  ).toBe("/shop/s/checkout");
  expect(
    element.shadowRoot.querySelector("lightning-formatted-number").value
  ).toBe(100);
});
it("updates the selected line and publishes the server badge count", async () => {
  update.mockResolvedValue({ ...cart, itemCount: 3 });
  const listener = jest.fn();
  window.addEventListener("goldvueecartchange", listener);
  const element = await mount();
  element.shadowRoot.querySelector('[data-action="plus"]').click();
  await flush();
  expect(update).toHaveBeenCalledWith({ cartItemId: "line1", quantity: 3 });
  expect(listener.mock.calls.at(-1)[0].detail.count).toBe(3);
  window.removeEventListener("goldvueecartchange", listener);
});
it("removes jewellery and shows the empty state", async () => {
  remove.mockResolvedValue({ items: [], itemCount: 0, totalAmount: 0 });
  const element = await mount();
  element.shadowRoot.querySelector('[data-action="remove"]').click();
  await flush();
  expect(element.shadowRoot.textContent).toContain("Your bag awaits");
  expect(remove).toHaveBeenCalledWith({ cartItemId: "line1" });
});
it("leaves navigation available when a cart mutation is rejected", async () => {
  update.mockRejectedValue({
    body: { message: "The requested quantity is unavailable." }
  });
  const element = await mount();
  element.shadowRoot.querySelector('[data-action="plus"]').click();
  await flush();
  expect(
    element.shadowRoot.querySelector('[role="alert"]').textContent
  ).toContain("unavailable");
  expect(element.shadowRoot.querySelector("a.button")).not.toBeNull();
});
