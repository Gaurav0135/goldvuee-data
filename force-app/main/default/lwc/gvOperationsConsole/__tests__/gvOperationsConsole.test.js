import { createElement } from "lwc";
import Component from "c/gvOperationsConsole";
import inventory from "@salesforce/apex/GVCheckoutOperations.inventory";
import reviews from "@salesforce/apex/GVCheckoutOperations.reviewQueue";
import orders from "@salesforce/apex/GVCheckoutOperations.fulfillmentQueue";
jest.mock(
  "@salesforce/apex/GVCheckoutOperations.inventory",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/GVCheckoutOperations.reviewQueue",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/GVCheckoutOperations.fulfillmentQueue",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
const flush = async () => {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
};
afterEach(() => {
  while (document.body.firstChild)
    document.body.removeChild(document.body.firstChild);
  jest.resetAllMocks();
});
it("shows inventory counters, pending review and paid fulfillment transitions", async () => {
  inventory.mockResolvedValue([
    {
      Id: "p1",
      Name: "Ring",
      Stock_Quantity__c: 3,
      Reserved_Quantity__c: 1,
      Available_Quantity__c: 2
    }
  ]);
  reviews.mockResolvedValue([
    {
      Id: "pay1",
      Jewellery_Order__r: { Name: "GV-1" },
      Payment_Amount__c: 900,
      Reconciliation_State__c: "Captured - stock review required"
    }
  ]);
  orders.mockResolvedValue([
    {
      Id: "o1",
      Name: "GV-2",
      Order_Status__c: "Confirmed",
      Grand_Total__c: 900
    }
  ]);
  const el = createElement("c-gv-operations-console", { is: Component });
  document.body.appendChild(el);
  await flush();
  expect(el.shadowRoot.textContent).toContain("Ring");
  expect(el.shadowRoot.textContent).toContain("stock review required");
  expect(
    el.shadowRoot.querySelector('lightning-button[data-next="Processing"]')
  ).not.toBeNull();
});
it("shows access denial without inventory data", async () => {
  inventory.mockRejectedValue({ body: { message: "Administrator required" } });
  reviews.mockResolvedValue([]);
  orders.mockResolvedValue([]);
  const el = createElement("c-gv-operations-console", { is: Component });
  document.body.appendChild(el);
  await flush();
  expect(el.shadowRoot.querySelector('[role="alert"]').textContent).toContain(
    "Administrator required"
  );
  expect(el.shadowRoot.querySelector("tbody").children).toHaveLength(0);
});
