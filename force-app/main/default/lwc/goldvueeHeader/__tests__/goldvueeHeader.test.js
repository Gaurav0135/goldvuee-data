import { createElement } from "lwc";
import Header from "c/goldvueeHeader";
import getCart from "@salesforce/apex/GVCartController.getCart";
jest.mock(
  "@salesforce/apex/GVCartController.getCart",
  () => ({ default: jest.fn().mockResolvedValue({ itemCount: 2 }) }),
  { virtual: true }
);
jest.mock(
  "@salesforce/user/isGuest",
  () => ({ __esModule: true, default: false }),
  { virtual: true }
);
afterEach(() => {
  document.body.replaceChildren();
  jest.clearAllMocks();
});
const flush = () => Promise.resolve().then(() => Promise.resolve());
it("preserves collections, arrivals, cart and account navigation", async () => {
  const el = createElement("c-goldvuee-header", { is: Header });
  document.body.appendChild(el);
  await flush();
  const links = [...el.shadowRoot.querySelectorAll("a")].map((a) =>
    a.getAttribute("href")
  );
  expect(links.some((x) => x.endsWith("/collections"))).toBe(true);
  expect(links.some((x) => x.endsWith("/new-arrivals"))).toBe(true);
  expect(links.some((x) => x.endsWith("/shopping-cart"))).toBe(true);
  expect(links.some((x) => x.endsWith("/my-account"))).toBe(true);
  expect(getCart).toHaveBeenCalledTimes(1);
});
it("shows the server cart badge and follows cart updates", async () => {
  const el = createElement("c-goldvuee-header", { is: Header });
  document.body.appendChild(el);
  await flush();
  expect(el.shadowRoot.textContent).toContain("Cart (2)");
  window.dispatchEvent(
    new CustomEvent("goldvueecartchange", { detail: { count: 4 } })
  );
  await flush();
  expect(el.shadowRoot.textContent).toContain("Cart (4)");
});

it("does not overwrite a cart event with a late initialization response", async () => {
  let resolve;
  getCart.mockReturnValueOnce(
    new Promise((done) => {
      resolve = done;
    })
  );
  const el = createElement("c-goldvuee-header", { is: Header });
  document.body.appendChild(el);
  window.dispatchEvent(
    new CustomEvent("goldvueecartchange", { detail: { count: 0 } })
  );
  resolve({ itemCount: 1 });
  await flush();
  expect(el.shadowRoot.textContent).toContain("Cart (0)");
});
it.each(["focus", "storage"])(
  "refreshes backend cart on %s after another tab changes it",
  async (type) => {
    const el = createElement("c-goldvuee-header", { is: Header });
    document.body.appendChild(el);
    await flush();
    getCart.mockResolvedValueOnce({ itemCount: 0 });
    window.dispatchEvent(
      type === "storage"
        ? new StorageEvent("storage", { key: "goldvueecartrefresh" })
        : new CustomEvent("focus")
    );
    await flush();
    expect(el.shadowRoot.textContent).toContain("Cart (0)");
  }
);
it("ignores older overlapping reads and refreshes on reconnect", async () => {
  const el = createElement("c-goldvuee-header", { is: Header });
  document.body.appendChild(el);
  await flush();
  let resolve;
  getCart.mockReturnValueOnce(
    new Promise((done) => {
      resolve = done;
    })
  );
  window.dispatchEvent(new CustomEvent("focus"));
  getCart.mockResolvedValueOnce({ itemCount: 3 });
  window.dispatchEvent(new CustomEvent("focus"));
  await flush();
  resolve({ itemCount: 0 });
  await flush();
  expect(el.shadowRoot.textContent).toContain("Cart (3)");
  el.remove();
  getCart.mockResolvedValueOnce({ itemCount: 4 });
  document.body.appendChild(el);
  await flush();
  expect(el.shadowRoot.textContent).toContain("Cart (4)");
});
it("preserves count when refresh fails and removes listeners on disconnect", async () => {
  const el = createElement("c-goldvuee-header", { is: Header });
  document.body.appendChild(el);
  await flush();
  getCart.mockRejectedValueOnce(new Error("offline"));
  window.dispatchEvent(new CustomEvent("focus"));
  await flush();
  expect(el.shadowRoot.textContent).toContain("Cart (2)");
  el.remove();
  const calls = getCart.mock.calls.length;
  window.dispatchEvent(new CustomEvent("focus"));
  expect(getCart).toHaveBeenCalledTimes(calls);
});
