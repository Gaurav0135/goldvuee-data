import { pollingScope, reconcile } from "c/gvCheckoutRecovery";
import checkoutRecovery from "@salesforce/apex/GVOnlineCheckoutController.checkoutRecovery";
import requestReconciliation from "@salesforce/apex/GVOnlineCheckoutController.requestReconciliation";
jest.mock(
  "@salesforce/apex/GVOnlineCheckoutController.checkoutRecovery",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/GVOnlineCheckoutController.requestReconciliation",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
describe("bounded recovery polling", () => {
  beforeEach(() => {
    jest.useFakeTimers();
    requestReconciliation.mockResolvedValue();
  });
  afterEach(() => {
    jest.clearAllTimers();
    jest.useRealTimers();
    jest.resetAllMocks();
  });
  it("stops after six uncertain responses without assuming payment failed", async () => {
    checkoutRecovery.mockResolvedValue({ state: "Uncertain" });
    const updates = jest.fn();
    const pending = reconcile("payment1", pollingScope(), updates);
    await jest.runAllTimersAsync();
    expect(await pending).toBeNull();
    expect(checkoutRecovery).toHaveBeenCalledTimes(6);
    expect(
      updates.mock.calls.every(([state]) => state.state === "Uncertain")
    ).toBe(true);
  });
  it("never overlaps verification requests", async () => {
    let resolve;
    checkoutRecovery
      .mockImplementationOnce(
        () =>
          new Promise((done) => {
            resolve = done;
          })
      )
      .mockResolvedValue({ state: "Confirmed" });
    const pending = reconcile("payment1", pollingScope());
    await jest.advanceTimersByTimeAsync(600);
    await jest.advanceTimersByTimeAsync(30000);
    expect(checkoutRecovery).toHaveBeenCalledTimes(1);
    resolve({ state: "Uncertain" });
    await jest.runAllTimersAsync();
    expect((await pending).state).toBe("Confirmed");
    expect(checkoutRecovery).toHaveBeenCalledTimes(2);
  });
  it("cancels outstanding delays without another request", async () => {
    const scope = pollingScope();
    const pending = reconcile("payment1", scope);
    await Promise.resolve();
    scope.cancel();
    await jest.runAllTimersAsync();
    expect(await pending).toBeNull();
    expect(checkoutRecovery).not.toHaveBeenCalled();
  });
  it("suppresses a response that arrives after disconnect", async () => {
    let resolve;
    const scope = pollingScope();
    const updates = jest.fn();
    checkoutRecovery.mockImplementation(
      () =>
        new Promise((done) => {
          resolve = done;
        })
    );
    const pending = reconcile("payment1", scope, updates);
    await jest.advanceTimersByTimeAsync(600);
    scope.cancel();
    resolve({ state: "Confirmed" });
    expect(await pending).toBeNull();
    expect(updates).not.toHaveBeenCalled();
  });
});
