import { createElement } from "lwc";
import Orders from "c/gvMyOrders";
import getMyOrders from "@salesforce/apex/GVOrderHistoryController.getMyOrders";
import getMyOrderDetail from "@salesforce/apex/GVOrderHistoryController.getMyOrderDetail";
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
  for (let i = 0; i < 12; i++) await Promise.resolve();
};
describe("accurate order history", () => {
  afterEach(() => {
    document.body.replaceChildren();
    jest.resetAllMocks();
  });
  it("keeps unverified payments Processing and displays confirmed/failed server states", async () => {
    getMyOrders.mockResolvedValue([
      {
        orderId: "pending",
        orderNumber: "Pending order",
        orderStatus: "pending",
        paymentStatus: "Pending"
      },
      {
        orderId: "paid",
        orderNumber: "Paid order",
        orderStatus: "Confirmed",
        paymentStatus: "Paid"
      },
      {
        orderId: "failed",
        orderNumber: "Cancelled order",
        orderStatus: "Cancelled",
        paymentStatus: "Failed"
      }
    ]);
    const el = createElement("c-gv-my-orders", { is: Orders });
    document.body.appendChild(el);
    await flush();
    const cards = el.shadowRoot.querySelectorAll(".order-card");
    expect(cards[0].querySelector(".status-pill").textContent).toContain(
      "Processing"
    );
    expect(cards[0].textContent).not.toContain("Failed");
    expect(cards[1].textContent).toContain("Confirmed");
    expect(cards[2].textContent).toContain("Failed");
    getMyOrders.mockResolvedValue([
      { orderId: "pending", orderStatus: "Confirmed", paymentStatus: "Paid" }
    ]);
    el.shadowRoot.querySelector(".refresh-button").click();
    await flush();
    expect(getMyOrders).toHaveBeenCalledTimes(2);
    expect(el.shadowRoot.querySelector(".status-pill").textContent).toContain(
      "Confirmed"
    );
  });
  it("uses the same verified status mapping for order details", async () => {
    getMyOrders.mockResolvedValue([
      { orderId: "one", orderStatus: "pending", paymentStatus: "Pending" }
    ]);
    getMyOrderDetail.mockResolvedValue({
      order: {
        orderId: "one",
        orderStatus: "pending",
        paymentStatus: "Pending"
      },
      items: []
    });
    const el = createElement("c-gv-my-orders", { is: Orders });
    document.body.appendChild(el);
    await flush();
    el.shadowRoot.querySelector(".gold-button").click();
    await flush();
    expect(
      el.shadowRoot.querySelector(".detail-summary").textContent
    ).toContain("Processing");
    expect(
      el.shadowRoot.querySelector(".detail-summary").textContent
    ).not.toContain("Failed");
  });
});
