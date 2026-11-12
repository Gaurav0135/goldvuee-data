import { createElement } from "lwc";
import Component from "c/gvMyOrders";
import getOrders from "@salesforce/apex/GVOrderHistoryController.getMyOrders";
jest.mock(
  "@salesforce/apex/GVOrderHistoryController.getMyOrders",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/GVOrderHistoryController.getMyOrderDetail",
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
  const el = createElement("c-gv-my-orders", { is: Component });
  document.body.appendChild(el);
  return el;
};
it("renders server-confirmed order state", async () => {
  getOrders.mockResolvedValue([
    {
      orderId: "order1",
      orderNumber: "GV-ORD-1",
      grandTotal: 100,
      orderStatus: "Confirmed",
      paymentStatus: "Paid"
    }
  ]);
  const el = mount();
  await flush();
  expect(el.shadowRoot.textContent).toContain("GV-ORD-1");
  expect(el.shadowRoot.textContent).toContain("Confirmed");
});
it("shows order access errors", async () => {
  getOrders.mockRejectedValue({ body: { message: "Sign in to view orders" } });
  const el = mount();
  await flush();
  expect(el.shadowRoot.textContent).toContain("Sign in to view orders");
});
