import { createElement } from "lwc";
import Checkout from "c/gvCheckout";
import Header from "c/goldvueeHeader";

import loadDelivery from "@salesforce/apex/GVCheckoutController.loadDelivery";
import prepare from "@salesforce/apex/GVCheckoutController.prepareOrder";
import loadOrder from "@salesforce/apex/GVCheckoutController.loadOrder";
import getCart from "@salesforce/apex/GVCartController.getCart";

import start from "@salesforce/apex/GVRazorpayController.startPayment";
import retry from "@salesforce/apex/GVRazorpayController.retryPayment";
import status from "@salesforce/apex/GVRazorpayController.paymentStatus";
import refresh from "@salesforce/apex/GVRazorpayController.refreshPayment";
import cancel from "@salesforce/apex/GVRazorpayController.cancelPayment";

jest.mock(
  "@salesforce/apex/GVCheckoutController.loadDelivery",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/GVCheckoutController.prepareOrder",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/GVCheckoutController.loadOrder",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/GVCartController.getCart",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/GVRazorpayController.startPayment",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/GVRazorpayController.retryPayment",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/GVRazorpayController.paymentStatus",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/GVRazorpayController.refreshPayment",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/GVRazorpayController.cancelPayment",
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

const delivery = {
  fullName: "Test Customer",
  phone: "9691184503",
  street: "42 Gold Lane",
  city: "Indore",
  state: "Madhya Pradesh",
  postalCode: "452001",
  country: "India"
};

const summary = {
  orderId: "order1",
  paymentId: "payment1",
  orderNumber: "GV-1",
  total: 200,
  delivery,
  items: [
    {
      lineId: "item1",
      name: "Gold ring",
      quantity: 2,
      unitPrice: 100,
      lineTotal: 200
    }
  ]
};

const pending = {
  paymentId: "payment1",
  orderId: "order1",
  orderNumber: "GV-1",
  amount: 200,
  state: "Ready",
  paymentStatus: "Pending",
  paymentUrl: "https://rzp.io/rzp/test",
  message: "Awaiting verified payment",
  matchesCurrentCart: true
};

const flush = () =>
  Array.from({ length: 12 }).reduce(
    (p) => p.then(() => Promise.resolve()),
    Promise.resolve()
  );

let tab;

beforeEach(() => {
  jest.useFakeTimers();

  jest.setSystemTime(new Date("2026-11-14T00:00:00Z"));

  loadDelivery.mockResolvedValue(delivery);
  prepare.mockResolvedValue(summary);
  loadOrder.mockResolvedValue(summary);

  getCart.mockResolvedValue({
    itemCount: 2
  });

  start.mockResolvedValue({
    ...pending,
    state: "Queued",
    paymentUrl: null
  });

  retry.mockResolvedValue({
    ...pending,
    state: "Queued",
    paymentUrl: null
  });

  status.mockResolvedValue(pending);
  refresh.mockResolvedValue(pending);

  cancel.mockResolvedValue({
    ...pending,
    state: "Cancelled",
    paymentStatus: "Failed"
  });

  tab = {
    closed: false,
    location: {
      replace: jest.fn()
    },
    close: jest.fn()
  };

  jest.spyOn(window, "open").mockReturnValue(tab);
});

afterEach(() => {
  document.body.replaceChildren();
  sessionStorage.clear();

  jest.clearAllTimers();
  jest.useRealTimers();
  jest.restoreAllMocks();
  jest.resetAllMocks();
});

async function mount() {
  const element = createElement("c-gv-checkout", {
    is: Checkout
  });

  document.body.appendChild(element);

  await flush();

  return element;
}

function button(element, label) {
  return [...element.shadowRoot.querySelectorAll("button")].find((node) =>
    node.textContent.toLowerCase().includes(label)
  );
}

async function paymentPage() {
  const element = await mount();

  button(element, "continue to order summary").click();

  await flush();

  button(element, "continue to payment").click();

  await flush();

  return element;
}

// --------------------------------------------------
// ADDRESS TESTS
// --------------------------------------------------

it.each(["9691184503", "+919691184503", "+91 9691184503"])(
  "normalizes %s and navigates from address to review",
  async (phone) => {
    const element = await mount();

    const field = element.shadowRoot.querySelector('input[name="phone"]');

    expect(field.hasAttribute("pattern")).toBe(true);

    field.value = phone;

    field.dispatchEvent(new CustomEvent("input"));

    await flush();

    button(element, "continue to order summary").click();

    await flush();

    expect(prepare).toHaveBeenCalledWith({
      delivery
    });

    expect(element.shadowRoot.textContent).toContain(
      "Your jewellery selection"
    );

    expect(element.shadowRoot.querySelector(".address").textContent).toContain(
      "42 Gold Lane"
    );
  }
);

it.each(["12345", "+449691184503", "96911abc4503"])(
  "allows free-form mobile %s to continue",
  async (phone) => {
    const element = await mount();

    const field = element.shadowRoot.querySelector('input[name="phone"]');

    field.value = phone;

    field.dispatchEvent(new CustomEvent("input"));

    await flush();

    button(element, "continue to order summary").click();

    await flush();

    expect(prepare).toHaveBeenCalledWith({
      delivery: {
        ...delivery,
        phone
      }
    });

    expect(element.shadowRoot.textContent).toContain(
      "Your jewellery selection"
    );
  }
);

it("uses empty fields for missing Contact data and keeps State editable", async () => {
  loadDelivery.mockResolvedValue({
    fullName: "Test Customer",
    phone: "+91 9691184503",
    street: "9691184503",
    state: null
  });

  const element = await mount();

  expect(element.shadowRoot.querySelector("textarea").value).toBe("");

  const state = element.shadowRoot.querySelector('[name="state"]');

  expect(state.value).toBe("");
  expect(state.type).toBe("text");
  expect(state.readOnly).toBe(false);

  expect(element.shadowRoot.textContent).not.toMatch(/undefined|null/);
});

it("reads browser autofill even without input events and supports back navigation", async () => {
  const element = await mount();

  element.shadowRoot.querySelector('[name="phone"]').value = "+91 9691184503";

  button(element, "continue to order summary").click();

  await flush();

  expect(prepare).toHaveBeenCalledWith({
    delivery
  });

  button(element, "continue to payment").click();

  await flush();

  button(element, "back to order summary").click();

  await flush();

  button(element, "change address").click();

  await flush();

  expect(element.shadowRoot.querySelector("textarea").value).toBe(
    delivery.street
  );
});

// --------------------------------------------------
// PREVIOUS PAYMENT RESTORATION
// --------------------------------------------------

it("ignores an unrelated previous payment while the current bag remains editable", async () => {
  sessionStorage.setItem("gvHostedPayment", "old");

  status.mockResolvedValue({
    ...pending,
    matchesCurrentCart: false
  });

  const element = await mount();

  expect(element.shadowRoot.querySelector('[name="street"]')).not.toBeNull();

  expect(element.shadowRoot.textContent).toContain("previous payment");

  expect(sessionStorage.getItem("gvHostedPayment")).toBeNull();
});

// --------------------------------------------------
// RAZORPAY PAYMENT TESTS
// --------------------------------------------------

it("opens Razorpay separately and polls authenticated status", async () => {
  const element = await paymentPage();

  button(element, "pay now").click();

  await flush();

  expect(window.open).toHaveBeenCalledWith("about:blank", "_blank");

  await jest.advanceTimersByTimeAsync(1600);

  expect(tab.location.replace).toHaveBeenCalledWith(pending.paymentUrl);

  await jest.advanceTimersByTimeAsync(6000);

  expect(refresh).toHaveBeenCalledWith({
    paymentId: "payment1"
  });

  expect(start).toHaveBeenCalledTimes(1);
});

it("ends waiting after 120 seconds and reuses the existing attempt on retry", async () => {
  const element = await paymentPage();

  button(element, "pay now").click();

  await flush();

  await jest.advanceTimersByTimeAsync(120000);

  expect(element.shadowRoot.textContent).toContain("Payment not confirmed yet");

  expect(button(element, "pay now").disabled).toBe(false);

  expect(cancel).not.toHaveBeenCalled();

  button(element, "retry payment").click();

  await flush();

  expect(retry).toHaveBeenCalledWith({
    paymentId: "payment1"
  });

  expect(prepare).toHaveBeenCalledTimes(1);
});

it("releases a stalled RPC and allows a new monitoring generation", async () => {
  const element = await paymentPage();

  button(element, "pay now").click();

  await flush();

  await jest.advanceTimersByTimeAsync(1600);

  refresh.mockImplementation(() => new Promise(() => {}));

  await jest.advanceTimersByTimeAsync(118400);

  expect(element.shadowRoot.textContent).toContain("Payment not confirmed yet");

  const before = refresh.mock.calls.length;

  refresh.mockResolvedValue(pending);

  button(element, "retry payment").click();

  await flush();

  await jest.advanceTimersByTimeAsync(6500);

  expect(refresh.mock.calls.length).toBeGreaterThan(before);
});

it("renders late verified success inline without a separate result component", async () => {
  const element = await paymentPage();

  button(element, "pay now").click();

  await flush();

  await jest.advanceTimersByTimeAsync(120000);

  refresh.mockResolvedValue({
    ...pending,
    state: "Paid",
    paymentStatus: "Success",
    fulfillment: "Confirmed",
    message: "Payment verified"
  });

  button(element, "refresh status").click();

  await flush();

  expect(element.shadowRoot.textContent).toContain("Your order is confirmed");

  expect(element.shadowRoot.querySelector("c-gv-payment-result")).toBeNull();

  expect(element.shadowRoot.textContent).not.toContain(
    "Payment not confirmed yet"
  );
});

it("preserves a captured stock exception as paid", async () => {
  const element = await paymentPage();

  start.mockResolvedValue({
    ...pending,
    state: "Paid",
    paymentStatus: "Success",
    fulfillment: "Stock review required",
    message: "Payment received; do not pay again"
  });

  button(element, "pay now").click();

  await flush();

  expect(element.shadowRoot.textContent).toContain("fulfillment needs review");

  expect(button(element, "pay now")).toBeUndefined();
});

it("retries a terminal link through the server without creating another business order", async () => {
  const element = await paymentPage();

  button(element, "cancel unpaid payment").click();

  await flush();

  retry.mockResolvedValue({
    ...pending,
    paymentId: "payment2",
    state: "Queued",
    paymentUrl: null
  });

  button(element, "retry payment").click();

  await flush();

  expect(retry).toHaveBeenCalledWith({
    paymentId: "payment1"
  });

  expect(prepare).toHaveBeenCalledTimes(1);

  expect(sessionStorage.getItem("gvHostedPayment")).toBe("payment2");
});

it("reports setup errors without fabricating payment failure", async () => {
  start.mockRejectedValue({
    body: {
      message: "Secure test payments need administrator setup."
    }
  });

  const element = await paymentPage();

  button(element, "pay now").click();

  await flush();

  expect(
    element.shadowRoot.querySelector('[role="alert"]').textContent
  ).toContain("administrator setup");

  expect(tab.close).toHaveBeenCalled();

  expect(cancel).not.toHaveBeenCalled();
});

// --------------------------------------------------
// CART BADGE SYNCHRONIZATION REGRESSION TESTS
// --------------------------------------------------

it("syncs actual cart count after confirmed payment", async () => {
  const element = await paymentPage();
  const listener = jest.fn();

  window.addEventListener("goldvueecartchange", listener);

  try {
    getCart.mockResolvedValue({
      itemCount: 0,
      items: [],
      totalAmount: 0
    });

    refresh.mockResolvedValue({
      ...pending,
      state: "Paid",
      paymentStatus: "Success",
      fulfillment: "Confirmed"
    });

    button(element, "refresh status").click();

    await flush();

    expect(getCart).toHaveBeenCalled();

    expect(listener).toHaveBeenCalledTimes(1);

    expect(listener.mock.calls[0][0].detail.count).toBe(0);

    expect(element.shadowRoot.textContent).toContain("Your order is confirmed");
  } finally {
    window.removeEventListener("goldvueecartchange", listener);
  }
});

it.each([
  ["Pending", "Ready", null],
  ["Failed", "Cancelled", null],
  ["Success", "Paid", "Stock review required"]
])(
  "does not clear cart for %s payment in %s state",
  async (paymentStatus, state, fulfillment) => {
    const element = await paymentPage();
    const listener = jest.fn();

    window.addEventListener("goldvueecartchange", listener);

    try {
      refresh.mockResolvedValue({
        ...pending,
        paymentStatus,
        state,
        fulfillment
      });

      button(element, "refresh status").click();

      await flush();

      expect(listener).not.toHaveBeenCalled();
    } finally {
      window.removeEventListener("goldvueecartchange", listener);
    }
  }
);

const confirmed = {
  ...pending,
  state: "Paid",
  paymentStatus: "Success",
  fulfillment: "Confirmed"
};
it("preserves verified attempt failure while refresh checks the same retryable link", async () => {
  const element = await paymentPage();
  refresh.mockResolvedValue({
    ...pending,
    state: "Checking",
    lastFailureState: "failed"
  });
  button(element, "refresh status").click();
  await flush();
  expect(element.shadowRoot.textContent).toContain("Payment unsuccessful");
  expect(getCart).not.toHaveBeenCalled();
  status.mockResolvedValue({ ...pending, lastFailureState: "failed" });
  await jest.advanceTimersByTimeAsync(1600);
  expect(element.shadowRoot.textContent).toContain("retry available");
  expect(button(element, "retry payment").disabled).toBe(false);
  expect(start).not.toHaveBeenCalled();
  expect(retry).not.toHaveBeenCalled();
});
it("keeps uncertain verification pending despite previous failure evidence", async () => {
  const element = await paymentPage();
  refresh.mockResolvedValue({
    ...pending,
    state: "Unknown",
    lastFailureState: "failed"
  });
  button(element, "refresh status").click();
  await flush();
  expect(element.shadowRoot.textContent).not.toContain("Payment unsuccessful");
  expect(getCart).not.toHaveBeenCalled();
});
it.each([
  [
    "same tab",
    () => new CustomEvent("goldvueecartchange", { detail: { count: 3 } }),
    [3]
  ],
  [
    "other tab",
    () => new StorageEvent("storage", { key: "goldvueecartrefresh" }),
    []
  ]
])(
  "does not publish an older cart read after a concurrent update in %s",
  async (source, concurrentEvent, expectedCounts) => {
    const element = await paymentPage();
    let resolve;
    getCart.mockReturnValueOnce(
      new Promise((done) => {
        resolve = done;
      })
    );
    refresh.mockResolvedValue(confirmed);
    const listener = jest.fn();
    window.addEventListener("goldvueecartchange", listener);
    try {
      button(element, "refresh status").click();
      await flush();
      window.dispatchEvent(concurrentEvent());
      resolve({ itemCount: 0 });
      await flush();
      expect(listener).toHaveBeenCalledTimes(expectedCounts.length);
      expect(listener.mock.calls.map(([event]) => event.detail.count)).toEqual(
        expectedCounts
      );
    } finally {
      window.removeEventListener("goldvueecartchange", listener);
    }
  }
);
it("retries a failed cart synchronization and deduplicates repeated confirmation", async () => {
  const element = await paymentPage();
  refresh.mockResolvedValue(confirmed);
  getCart.mockRejectedValueOnce(new Error("offline"));
  button(element, "refresh status").click();
  await flush();
  getCart.mockResolvedValue({ itemCount: 2 });
  window.dispatchEvent(new CustomEvent("focus"));
  await flush();
  window.dispatchEvent(new CustomEvent("focus"));
  await flush();
  expect(getCart).toHaveBeenCalledTimes(2);
  expect(element.shadowRoot.textContent).toContain("Your order is confirmed");
});
it("restores confirmed payment and actual count after reload and reconnect", async () => {
  sessionStorage.setItem("gvHostedPayment", "payment1");
  status.mockResolvedValue(confirmed);
  getCart.mockResolvedValue({ itemCount: 0 });
  const listener = jest.fn();
  window.addEventListener("goldvueecartchange", listener);
  try {
    const element = await mount();
    expect(element.shadowRoot.textContent).toContain("Your order is confirmed");
    expect(listener.mock.calls[0][0].detail.count).toBe(0);
    element.remove();
    document.body.appendChild(element);
    await flush();
    expect(listener).toHaveBeenCalledTimes(2);
  } finally {
    window.removeEventListener("goldvueecartchange", listener);
  }
});

// These tests mount the production header and checkout together. No synthetic
// goldvueecartchange is dispatched by the confirmation test: checkout must do it.
async function mountedPendingCheckoutWithHeader() {
  getCart.mockResolvedValue({ itemCount: 1 });
  sessionStorage.setItem("gvHostedPayment", "payment1");
  sessionStorage.setItem("gvDeadline:payment1", String(Date.now() + 120000));
  const header = createElement("c-goldvuee-header", { is: Header });
  document.body.appendChild(header);
  await flush();
  const element = await mount();
  expect(header.shadowRoot.textContent).toContain("Cart (1)");
  return { header, element };
}

function expectNoPaymentActionsOrNavigation(originalUrl, header, element) {
  expect(window.location.href).toBe(originalUrl);
  expect(Array.from(document.body.children)).toEqual([header, element]);
  expect(header.isConnected).toBe(true);
  expect(element.isConnected).toBe(true);
  expect(prepare).not.toHaveBeenCalled();
  expect(start).not.toHaveBeenCalled();
  expect(retry).not.toHaveBeenCalled();
  expect(cancel).not.toHaveBeenCalled();
  expect(window.open).not.toHaveBeenCalled();
  expect(tab.location.replace).not.toHaveBeenCalled();
}

it("automatically changes the mounted navbar from Cart (1) to Cart (0) on confirmed polling, without reload or navigation", async () => {
  const originalUrl = window.location.href;
  const originalDocument = document;
  const replaceState = jest.spyOn(window.history, "replaceState");
  const pushState = jest.spyOn(window.history, "pushState");
  const pageExit = jest.fn();
  const consoleError = jest
    .spyOn(console, "error")
    .mockImplementation(() => {});
  window.addEventListener("beforeunload", pageExit);
  window.addEventListener("pagehide", pageExit);
  try {
    const { header, element } = await mountedPendingCheckoutWithHeader();
    expect(getCart).toHaveBeenCalledTimes(2); // Header initialization and pending restoration.
    let resolveCart;
    getCart.mockImplementationOnce(
      () =>
        new Promise((resolve) => {
          resolveCart = resolve;
        })
    );
    refresh.mockResolvedValue(confirmed);

    // Advance the production polling timer; do not click Refresh status or dispatch a cart event.
    await jest.advanceTimersByTimeAsync(1500);
    await flush();
    expect(refresh).toHaveBeenCalledWith({ paymentId: "payment1" });
    expect(element.shadowRoot.textContent).toContain("Your order is confirmed");
    expect(getCart).toHaveBeenCalledTimes(3);
    expect(header.shadowRoot.textContent).toContain("Cart (1)"); // Must await actual backend count.

    resolveCart({ itemCount: 0 });
    await flush(); // Only resolve microtasks; no focus, navigation or page reload.
    expect(header.shadowRoot.textContent).toContain("Cart (0)");
    expect(document).toBe(originalDocument);
    expect(pageExit).not.toHaveBeenCalled();
    expect(pushState).not.toHaveBeenCalled();
    expect(replaceState).not.toHaveBeenCalled();
    expect(consoleError).not.toHaveBeenCalled(); // jsdom reports attempted reload/navigation here.
    expectNoPaymentActionsOrNavigation(originalUrl, header, element);

    // Confirmed state stops polling rather than repeatedly fetching cart or creating payment work.
    await jest.advanceTimersByTimeAsync(10000);
    expect(refresh).toHaveBeenCalledTimes(1);
    expect(getCart).toHaveBeenCalledTimes(3);
    expect(header.shadowRoot.textContent).toContain("Cart (0)");
    expectNoPaymentActionsOrNavigation(originalUrl, header, element);
  } finally {
    window.removeEventListener("beforeunload", pageExit);
    window.removeEventListener("pagehide", pageExit);
  }
});

it.each([
  ["pending", { ...pending }],
  ["failed retryable attempt", { ...pending, lastFailureState: "failed" }],
  [
    "terminal failed link",
    { ...pending, state: "Cancelled", paymentStatus: "Failed" }
  ],
  ["fulfillment review", { ...confirmed, fulfillment: "Stock review required" }]
])(
  "keeps the integrated Cart (1) badge for %s without confirmation cart cleanup",
  async (label, response) => {
    const originalUrl = window.location.href;
    const { header, element } = await mountedPendingCheckoutWithHeader();
    const initialCartCalls = getCart.mock.calls.length;
    // Even if an erroneous extra fetch would return zero, these states must not request cleanup/sync.
    getCart.mockResolvedValue({ itemCount: 0 });
    refresh.mockResolvedValue(response);
    await jest.advanceTimersByTimeAsync(1500);
    await flush();
    expect(getCart).toHaveBeenCalledTimes(initialCartCalls);
    expect(header.shadowRoot.textContent).toContain("Cart (1)");
    expectNoPaymentActionsOrNavigation(originalUrl, header, element);
  }
);

it("keeps retry available for a failed retryable attempt with the integrated header", async () => {
  const { element } = await mountedPendingCheckoutWithHeader();
  refresh.mockResolvedValue({ ...pending, lastFailureState: "failed" });
  await jest.advanceTimersByTimeAsync(1500);
  await flush();
  expect(element.shadowRoot.textContent).toContain("retry available");
  expect(button(element, "retry payment").disabled).toBe(false);
});

it("shows fulfillment review without a pay action with the integrated header", async () => {
  const { element } = await mountedPendingCheckoutWithHeader();
  refresh.mockResolvedValue({
    ...confirmed,
    fulfillment: "Stock review required"
  });
  await jest.advanceTimersByTimeAsync(1500);
  await flush();
  expect(element.shadowRoot.textContent).toContain("fulfillment needs review");
  expect(button(element, "pay now")).toBeUndefined();
});

it("safely reapplies repeated confirmed responses on reconnect with the same mounted header", async () => {
  const originalUrl = window.location.href;
  const { header, element } = await mountedPendingCheckoutWithHeader();
  getCart.mockResolvedValue({ itemCount: 0 });
  refresh.mockResolvedValue(confirmed);
  await jest.advanceTimersByTimeAsync(1500);
  await flush();
  expect(header.shadowRoot.textContent).toContain("Cart (0)");
  status.mockResolvedValue(confirmed);
  const reconnectAndAssert = async () => {
    element.remove();
    document.body.appendChild(element);
    await flush();
    expect(element.shadowRoot.textContent).toContain("Your order is confirmed");
    expect(header.shadowRoot.textContent).toContain("Cart (0)");
    expectNoPaymentActionsOrNavigation(originalUrl, header, element);
  };
  await reconnectAndAssert();
  await reconnectAndAssert();
  expect(refresh).toHaveBeenCalledTimes(1);
});

it("refreshes the integrated navbar from Salesforce on another-tab storage notification while checkout stays pending", async () => {
  const originalUrl = window.location.href;
  const { header, element } = await mountedPendingCheckoutWithHeader();
  const initialCartCalls = getCart.mock.calls.length;
  getCart.mockResolvedValue({ itemCount: 0 });
  // A StorageEvent is the browser delivery mechanism for a different same-origin tab.
  window.dispatchEvent(
    new StorageEvent("storage", {
      key: "goldvueecartrefresh",
      newValue: "other-tab-update"
    })
  );
  await flush();
  expect(getCart).toHaveBeenCalledTimes(initialCartCalls + 1);
  expect(header.shadowRoot.textContent).toContain("Cart (0)");
  expect(element.shadowRoot.textContent).not.toContain(
    "Your order is confirmed"
  );
  expect(refresh).not.toHaveBeenCalled();
  expectNoPaymentActionsOrNavigation(originalUrl, header, element);
});

function expiringPayment(remainingMs = 10000, serverOffsetMs = 0) {
  const serverNow = Date.now() + serverOffsetMs;
  return { ...pending, paymentExpiresAt: serverNow + remainingMs, serverNow };
}
const expiredUnpaid = {
  ...pending,
  state: "Cancelled",
  paymentStatus: "Failed",
  expiredByTimer: true,
  paymentUrl: null,
  message:
    "Payment time expired. The unpaid link is closed; you may retry safely."
};

it("uses remaining gateway time instead of restarting a 120-second page timer and shows safe terminal expiry", async () => {
  const response = expiringPayment();
  status.mockResolvedValue(response);
  refresh.mockResolvedValue(response);
  const { header, element } = await mountedPendingCheckoutWithHeader();
  await jest.advanceTimersByTimeAsync(9000);
  expect(element.shadowRoot.textContent).not.toContain("Payment time expired");
  refresh.mockResolvedValue(expiredUnpaid);
  await jest.advanceTimersByTimeAsync(1000);
  await flush();
  expect(element.shadowRoot.textContent).toContain("Payment time expired");
  expect(button(element, "retry payment").disabled).toBe(false);
  expect(header.shadowRoot.textContent).toContain("Cart (1)");
  expect(start).not.toHaveBeenCalled();
  expect(retry).not.toHaveBeenCalled();
  expect(cancel).not.toHaveBeenCalled();
});
it("adjusts the gateway deadline for client clock skew", async () => {
  const response = expiringPayment(10000, 3600000);
  status.mockResolvedValue(response);
  refresh.mockResolvedValue(response);
  const { element } = await mountedPendingCheckoutWithHeader();
  await jest.advanceTimersByTimeAsync(9000);
  expect(element.shadowRoot.textContent).not.toContain("Payment time expired");
  refresh.mockResolvedValue(expiredUnpaid);
  await jest.advanceTimersByTimeAsync(1000);
  expect(element.shadowRoot.textContent).toContain("Payment time expired");
});
it("restores an already elapsed gateway deadline without reopening its payment window", async () => {
  status.mockResolvedValue(expiringPayment(-1000));
  refresh.mockResolvedValue(expiredUnpaid);
  const { element } = await mountedPendingCheckoutWithHeader();
  await jest.advanceTimersByTimeAsync(1);
  await flush();
  expect(element.shadowRoot.textContent).toContain("Payment time expired");
  expect(refresh).toHaveBeenCalledTimes(1);
  expect(start).not.toHaveBeenCalled();
});
it("keeps an uncertain expiry pending and blocks replacement payment until terminal verification", async () => {
  const response = expiringPayment(1000);
  status.mockResolvedValue(response);
  refresh.mockResolvedValue({
    ...response,
    state: "Unknown",
    paymentUrl: null
  });
  const { header, element } = await mountedPendingCheckoutWithHeader();
  await jest.advanceTimersByTimeAsync(1000);
  await flush();
  expect(element.shadowRoot.textContent).toContain(
    "Verifying that the unpaid link is closed"
  );
  expect(element.shadowRoot.textContent).not.toContain("Payment time expired");
  expect(button(element, "retry payment").disabled).toBe(true);
  expect(button(element, "pay now").disabled).toBe(true);
  expect(button(element, "open razorpay payment")).toBeUndefined();
  expect(header.shadowRoot.textContent).toContain("Cart (1)");
  expect(start).not.toHaveBeenCalled();
  expect(retry).not.toHaveBeenCalled();
});
it("preserves a capture racing with gateway expiry and synchronizes the actual cart", async () => {
  const response = expiringPayment(1000);
  status.mockResolvedValue(response);
  refresh.mockResolvedValue({
    ...confirmed,
    paymentExpiresAt: response.paymentExpiresAt,
    serverNow: response.serverNow
  });
  const { header, element } = await mountedPendingCheckoutWithHeader();
  getCart.mockResolvedValue({ itemCount: 0 });
  await jest.advanceTimersByTimeAsync(1000);
  await flush();
  expect(element.shadowRoot.textContent).toContain("Your order is confirmed");
  expect(header.shadowRoot.textContent).toContain("Cart (0)");
  const checks = refresh.mock.calls.length;
  await jest.advanceTimersByTimeAsync(120000);
  expect(refresh).toHaveBeenCalledTimes(checks);
  expect(element.shadowRoot.textContent).not.toContain("Payment time expired");
  expect(cancel).not.toHaveBeenCalled();
});
it("does not restart gateway time when retry reuses a still-pending attempt", async () => {
  const element = await paymentPage();
  const response = expiringPayment(10000);
  start.mockResolvedValue(response);
  status.mockResolvedValue(response);
  refresh.mockResolvedValue(response);
  button(element, "pay now").click();
  await flush();
  await jest.advanceTimersByTimeAsync(9000);
  refresh.mockResolvedValue(expiredUnpaid);
  await jest.advanceTimersByTimeAsync(1000);
  expect(element.shadowRoot.textContent).toContain("Payment time expired");
  retry.mockResolvedValue({
    ...pending,
    paymentId: "payment2",
    state: "Queued",
    paymentUrl: null
  });
  button(element, "retry payment").click();
  await flush();
  expect(retry).toHaveBeenCalledTimes(1);
  expect(prepare).toHaveBeenCalledTimes(1);
});

it("keeps the original gateway deadline armed after a failed attempt and retry of the same pending link", async () => {
  const response = { ...expiringPayment(10000), lastFailureState: "failed" };
  status.mockResolvedValue(response);
  refresh.mockResolvedValue(response);
  retry.mockResolvedValue({ ...response, state: "Checking", paymentUrl: null });
  const { element } = await mountedPendingCheckoutWithHeader();
  expect(button(element, "retry payment").disabled).toBe(false);
  await jest.advanceTimersByTimeAsync(9000);
  button(element, "retry payment").click();
  await flush();
  refresh.mockResolvedValue(expiredUnpaid);
  await jest.advanceTimersByTimeAsync(1000);
  await flush();
  expect(element.shadowRoot.textContent).toContain("Payment time expired");
  expect(retry).toHaveBeenCalledWith({ paymentId: "payment1" });
  expect(start).not.toHaveBeenCalled();
  expect(prepare).not.toHaveBeenCalled();
});
