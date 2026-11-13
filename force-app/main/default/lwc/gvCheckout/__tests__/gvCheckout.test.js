import { createElement } from "lwc";
import Checkout from "c/gvCheckout";
import getCart from "@salesforce/apex/GVCartController.getCart";
import recovery from "@salesforce/apex/GVOnlineCheckoutController.checkoutRecovery";
jest.mock(
  "@salesforce/apex/GVOnlineCheckoutController.checkoutRecovery",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/GVCartController.getCart",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock("@salesforce/user/isGuest", () => ({ default: false }), {
  virtual: true
});
const flush = async () => {
  for (let i = 0; i < 12; i++) await Promise.resolve();
};
async function mount() {
  getCart.mockResolvedValue({
    cartId: "cart1",
    totalAmount: 950,
    itemCount: 1,
    items: [{ Id: "item1", Quantity__c: 1, Line_Total__c: 950 }]
  });
  const el = createElement("c-gv-checkout", { is: Checkout });
  document.body.appendChild(el);
  await flush();
  return el;
}
describe("checkout journey", () => {
  it("restores confirmation after refresh using only a saved reference and server status", async () => {
    window.sessionStorage.setItem("goldvuee.checkout.payment", "payment1");
    getCart.mockResolvedValueOnce({ cartId: null, items: [], itemCount: 0 });
    recovery.mockResolvedValue({
      state: "Confirmed",
      order: {
        orderNumber: "GV-RESTORED",
        grandTotal: 900,
        orderStatus: "Confirmed",
        paymentStatus: "Paid"
      }
    });
    const el = await mount();
    expect(recovery).toHaveBeenCalledWith({ paymentId: "payment1" });
    expect(el.shadowRoot.textContent).toContain("GV-RESTORED");
  });
  it("does not show an old confirmation over a newly created active bag", async () => {
    window.sessionStorage.setItem("goldvuee.checkout.payment", "payment1");
    recovery.mockResolvedValue({
      state: "Confirmed",
      order: {
        cartId: "oldCart",
        orderNumber: "GV-OLD",
        grandTotal: 900,
        orderStatus: "Confirmed",
        paymentStatus: "Paid"
      }
    });
    const el = await mount();
    expect(el.shadowRoot.textContent).not.toContain("GV-OLD");
    expect(el.shadowRoot.querySelector(".back-to-bag")).not.toBeNull();
    expect(
      window.sessionStorage.getItem("goldvuee.checkout.payment")
    ).toBeNull();
  });
  afterEach(() => {
    document.body.replaceChildren();
    window.sessionStorage.clear();
    jest.resetAllMocks();
  });
  it("offers a visible back action and delivery fields", async () => {
    const el = await mount();
    expect(el.shadowRoot.querySelector(".back-to-bag").textContent).toContain(
      "Back to Shopping Bag"
    );
    expect(el.shadowRoot.querySelectorAll('[name^="shipping"]')).toHaveLength(
      5
    );
  });
  it("restores the server total and freezes delivery details", async () => {
    const el = await mount();
    el.shadowRoot.querySelector("c-goldvuee-razorpay-checkout").dispatchEvent(
      new CustomEvent("checkoutstate", {
        detail: {
          locked: true,
          order: {
            grandTotal: 900,
            items: [
              {
                Id: "originalLine",
                Jewellery_Product__r: { Name: "Original order jewellery" },
                Quantity__c: 2,
                Unit_Price__c: 500,
                Line_Total__c: 900
              }
            ],
            shippingAddress: "Saved address",
            shippingCity: "Indore",
            shippingState: "MP",
            shippingPostalCode: "452001",
            shippingCountry: "India"
          }
        }
      })
    );
    await flush();
    expect(el.shadowRoot.querySelector(".summary-item").textContent).toContain(
      "Original order jewellery"
    );
    expect(el.shadowRoot.querySelector(".item-price").textContent).toContain(
      "900.00"
    );
    expect(el.shadowRoot.querySelector('[name="shippingAddress"]').value).toBe(
      "Saved address"
    );
    expect(
      el.shadowRoot.querySelector('[name="shippingAddress"]').disabled
    ).toBe(true);
    expect(el.shadowRoot.querySelector(".summary-total").textContent).toContain(
      "900.00"
    );
  });
  it("stays in checkout when cancellation is uncertain", async () => {
    const el = await mount();
    const child = el.shadowRoot.querySelector("c-goldvuee-razorpay-checkout");
    child.cancelForBack = jest.fn().mockResolvedValue({
      state: "Uncertain",
      message: "Verifying your payment."
    });
    el.shadowRoot.querySelector(".back-to-bag").click();
    await flush();
    expect(child.cancelForBack).toHaveBeenCalledTimes(1);
    expect(el.shadowRoot.querySelector('[role="alert"]').textContent).toContain(
      "Verifying your payment."
    );
  });
  it("shows confirmation for a server-confirmed payment during Back to Bag", async () => {
    const el = await mount();
    el.shadowRoot.querySelector("c-goldvuee-razorpay-checkout").cancelForBack =
      jest.fn().mockResolvedValue({
        state: "Confirmed",
        order: {
          orderNumber: "GV-001",
          grandTotal: 900,
          orderStatus: "Confirmed",
          paymentStatus: "Paid"
        }
      });
    el.shadowRoot.querySelector(".back-to-bag").click();
    await flush();
    expect(el.shadowRoot.textContent).toContain("GV-001");
    expect(el.shadowRoot.querySelector(".back-to-bag")).toBeNull();
  });
});

jest.mock("@salesforce/community/basePath", () => ({ default: "/goldvuee" }), {
  virtual: true
});
