import { createElement } from "lwc";
import Carousel from "c/goldvueeCategoryCarousel";
const flush = () => Promise.resolve();
afterEach(() => {
  while (document.body.firstChild) {
    document.body.removeChild(document.body.firstChild);
  }
});
function mount() {
  const element = createElement("c-goldvuee-category-carousel", {
    is: Carousel
  });
  document.body.appendChild(element);
  return element.shadowRoot;
}
test("prepares the next face, locks repeated clicks, then commits counter and image", async () => {
  const root = mount();
  const next = root.querySelector(".gv-arrow-right");
  const original = root.querySelector(".gv-flip-front img").src;
  next.click();
  await flush();
  expect(next.disabled).toBe(true);
  expect(root.querySelector(".gv-image-counter").textContent).toMatch(/1 \/ 3/);
  const prepared = root.querySelector(".gv-flip-back img").src;
  expect(prepared).not.toBe(original);
  next.dispatchEvent(new MouseEvent("click"));
  await flush();
  root
    .querySelector(".gv-image-rotator")
    .dispatchEvent(new CustomEvent("animationend"));
  await flush();
  expect(root.querySelector(".gv-flip-front img").src).toBe(prepared);
  expect(root.querySelector(".gv-image-counter").textContent).toMatch(/2 \/ 3/);
  expect(next.disabled).toBe(false);
  expect(root.querySelectorAll(".gv-image-counter")[1].textContent).toMatch(
    /1 \/ 3/
  );
});
test("previous wraps and a left swipe advances without changing other cards", async () => {
  const root = mount();
  root.querySelector(".gv-arrow-left").click();
  await flush();
  root
    .querySelector(".gv-image-rotator")
    .dispatchEvent(new CustomEvent("animationend"));
  await flush();
  expect(root.querySelector(".gv-image-counter").textContent).toMatch(/3 \/ 3/);
  const frame = root.querySelector(".gv-image-frame");
  const start = new CustomEvent("touchstart");
  Object.defineProperty(start, "touches", { value: [{ clientX: 200 }] });
  frame.dispatchEvent(start);
  const end = new CustomEvent("touchend");
  Object.defineProperty(end, "changedTouches", { value: [{ clientX: 100 }] });
  frame.dispatchEvent(end);
  await flush();
  root
    .querySelector(".gv-image-rotator")
    .dispatchEvent(new CustomEvent("animationend"));
  await flush();
  expect(root.querySelector(".gv-image-counter").textContent).toMatch(/1 \/ 3/);
});
