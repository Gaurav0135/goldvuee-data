import { createElement } from "lwc";
import Component from "c/goldvueeHeader";
jest.mock("@salesforce/user/isGuest", () => ({ default: true }), {
  virtual: true
});
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
  const el = createElement("c-goldvuee-header", { is: Component });
  document.body.appendChild(el);
  return el;
};
it("provides site-relative navigation and guest login", () => {
  const el = mount();
  expect(el.shadowRoot.querySelector(".gv-logo").alt).toContain("GoldVuee");
  expect(
    el.shadowRoot.querySelector(".gv-login").getAttribute("href")
  ).toContain("/goldvueevforcesite/login");
  expect(el.shadowRoot.querySelectorAll(".gv-nav a")).toHaveLength(5);
});
it("opens and closes mobile navigation", async () => {
  const el = mount();
  const button = el.shadowRoot.querySelector(".gv-menu-button");
  button.click();
  await flush();
  expect(el.shadowRoot.querySelector(".gv-mobile-nav")).not.toBeNull();
  button.click();
  await flush();
  expect(el.shadowRoot.querySelector(".gv-mobile-nav")).toBeNull();
});
