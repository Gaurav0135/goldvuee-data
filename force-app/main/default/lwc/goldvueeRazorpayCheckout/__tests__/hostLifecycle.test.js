const fs = require("fs");
const path = require("path");
const vm = require("vm");

function host() {
  const origin = "https://example.my.site.com";
  const listeners = {};
  const elements = Object.fromEntries(
    ["status", "error", "retryButton"].map((id) => [
      id,
      { style: {}, addEventListener: jest.fn() }
    ])
  );
  const opener = { postMessage: jest.fn() };
  let options, failed;
  const open = jest.fn();
  const window = {
    location: {
      search: `?origin=${encodeURIComponent(origin)}&nonce=0123456789abcdef0123456789abcdef`
    },
    opener,
    addEventListener: (type, handler) => {
      listeners[type] = handler;
    },
    Razorpay: function (config) {
      options = config;
      this.open = open;
      this.on = (type, handler) => {
        if (type === "payment.failed") failed = handler;
      };
    }
  };
  const markup = fs.readFileSync(
    path.resolve(
      process.cwd(),
      "force-app/main/default/pages/GVRazorpayHost.page"
    ),
    "utf8"
  );
  const script = markup
    .split("//<![CDATA[")[1]
    .split("//]]>")[0]
    .replace("{!JSENCODE($Label.GoldVuee_Experience_Origin)}", origin);
  vm.runInNewContext(script, {
    window,
    document: { getElementById: (id) => elements[id] },
    URL,
    URLSearchParams
  });
  listeners.load();
  const envelope = {
    source: "GOLDVUEE_CHECKOUT",
    type: "START_PAYMENT",
    nonce: "0123456789abcdef0123456789abcdef",
    data: { key: "rzp_test_UnitTest", orderId: "order_Gateway", amount: 90000 }
  };
  const start = (overrides = {}) =>
    listeners.message({
      source: opener,
      origin,
      data: JSON.stringify({ ...envelope, ...overrides })
    });
  return {
    start,
    opener,
    open,
    elements,
    get options() {
      return options;
    },
    fail: () => failed({ error: { description: "Test payment failure" } })
  };
}
describe("Visualforce Razorpay host lifecycle", () => {
  it("passes the trusted envelope to Razorpay and ignores a wrong nonce", () => {
    const h = host();
    h.start({ nonce: "wrong" });
    expect(h.open).not.toHaveBeenCalled();
    h.start();
    expect(h.open).toHaveBeenCalledTimes(1);
    expect(h.options).toEqual(
      expect.objectContaining({
        key: "rzp_test_UnitTest",
        order_id: "order_Gateway",
        amount: 90000,
        currency: "INR"
      })
    );
  });
  it("does not send dismissal after returning a successful payment response", () => {
    const h = host();
    h.start();
    h.options.handler({
      razorpay_payment_id: "pay_Test",
      razorpay_order_id: "order_Gateway",
      razorpay_signature: "a".repeat(64)
    });
    h.options.modal.ondismiss();
    const types = h.opener.postMessage.mock.calls.map(
      ([message]) => JSON.parse(message).type
    );
    expect(types).toEqual(["READY", "PAYMENT_SUCCESS"]);
  });
  it("preserves SDK retry and still reports dismissal after a failed attempt", () => {
    const h = host();
    h.start();
    h.fail();
    expect(h.elements.retryButton.style.display).toBe("none");
    h.options.modal.ondismiss();
    const types = h.opener.postMessage.mock.calls.map(
      ([message]) => JSON.parse(message).type
    );
    expect(types).toEqual(["READY", "PAYMENT_FAILED", "PAYMENT_DISMISSED"]);
  });
});
