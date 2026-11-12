import { createElement } from "lwc";
import Component from "c/goldvueeFooter";

afterEach(() => {
  while (document.body.firstChild)
    document.body.removeChild(document.body.firstChild);
  jest.clearAllMocks();
});
const mount = () => {
  const el = createElement("c-goldvuee-footer", { is: Component });
  document.body.appendChild(el);
  return el;
};
it("links customers to collections within the current site", () => {
  const el = mount();
  expect(
    el.shadowRoot.querySelector('a[href="/goldvueevforcesite/s/collections"]')
  ).not.toBeNull();
  expect(el.shadowRoot.textContent).toContain(String(new Date().getFullYear()));
});
