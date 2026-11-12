import { createElement } from "lwc";
import Component from "c/gvMyAccount";
import getAccount from "@salesforce/apex/GVMyAccountController.getMyAccount";
jest.mock(
  "@salesforce/apex/GVMyAccountController.getMyAccount",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
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
  const el = createElement("c-gv-my-account", { is: Component });
  document.body.appendChild(el);
  return el;
};
it("shows customer identity from Apex", async () => {
  getAccount.mockResolvedValue({
    loggedIn: true,
    firstName: "Asha",
    fullName: "Asha Test",
    email: "asha@example.test"
  });
  const el = mount();
  await flush();
  expect(el.shadowRoot.textContent).toContain("Asha");
  expect(el.shadowRoot.textContent).toContain("asha@example.test");
});
it("shows server errors without customer details", async () => {
  getAccount.mockRejectedValue({ body: { message: "Account unavailable" } });
  const el = mount();
  await flush();
  expect(el.shadowRoot.textContent).toContain("Account unavailable");
});
