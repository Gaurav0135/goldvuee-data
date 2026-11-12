import { createElement } from "lwc";
import Component from "c/goldvueeHero";

afterEach(() => {
  while (document.body.firstChild)
    document.body.removeChild(document.body.firstChild);
  jest.clearAllMocks();
});
const mount = () => {
  const el = createElement("c-goldvuee-hero", { is: Component });
  document.body.appendChild(el);
  return el;
};
it("preserves hero navigation to both storefront routes", () => {
  const el = mount();
  expect(
    el.shadowRoot.querySelector('a[href="/goldvueevforcesite/s/collections"]')
  ).not.toBeNull();
  expect(
    el.shadowRoot.querySelector('a[href="/goldvueevforcesite/s/new-arrivals"]')
  ).not.toBeNull();
});
