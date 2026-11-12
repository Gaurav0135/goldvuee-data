import { createElement } from "lwc";
import Component from "c/goldvueeCategoryCarousel";

afterEach(() => {
  while (document.body.firstChild)
    document.body.removeChild(document.body.firstChild);
  jest.clearAllMocks();
});
const mount = () => {
  const el = createElement("c-goldvuee-category-carousel", { is: Component });
  document.body.appendChild(el);
  return el;
};
it("renders collection links and image descriptions", () => {
  const el = mount();
  expect(el.shadowRoot.querySelectorAll("a").length).toBeGreaterThanOrEqual(3);
  expect(el.shadowRoot.textContent).toContain("Signature");
  expect(el.shadowRoot.querySelector("img").alt).toBeTruthy();
});
