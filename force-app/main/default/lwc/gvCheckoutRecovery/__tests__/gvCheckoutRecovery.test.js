import {
  pollingScope,
  reconcile,
  cancelCheckout,
  customerMessage
} from "c/gvCheckoutRecovery";
import cancelUnpaidCheckout from "@salesforce/apex/GVOnlineCheckoutController.cancelUnpaidCheckout";
jest.mock(
  "@salesforce/apex/GVOnlineCheckoutController.cancelUnpaidCheckout",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
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
  it.each(["StockUnavailable", "RecoveryRequired", "Review"])(
    "stops after one actionable %s response",
    async (state) => {
      checkoutRecovery.mockResolvedValue({ state, canCancel: false });
      const pending = reconcile("payment1", pollingScope());
      await jest.runAllTimersAsync();
      expect((await pending).state).toBe(state);
      expect(checkoutRecovery).toHaveBeenCalledTimes(1);
      expect(requestReconciliation).toHaveBeenCalledTimes(1);
    }
  );
  it("uses one cancellation workflow after proving an uninitialized checkout safe", async () => {
    checkoutRecovery.mockResolvedValue({
      state: "Interrupted",
      canCancel: true,
      order: { paymentId: "payment1" }
    });
    cancelUnpaidCheckout.mockResolvedValue({ state: "Cancelled" });
    expect((await cancelCheckout("payment1", pollingScope())).state).toBe(
      "Cancelled"
    );
    expect(cancelUnpaidCheckout).toHaveBeenCalledWith({
      paymentId: "payment1"
    });
    expect(requestReconciliation).not.toHaveBeenCalled();
  });
  it("never cancels while a gateway outcome remains uncertain", async () => {
    checkoutRecovery.mockResolvedValue({
      state: "Uncertain",
      canCancel: false,
      order: { paymentId: "payment1" }
    });
    const task = cancelCheckout("payment1", pollingScope());
    await jest.runAllTimersAsync();
    expect((await task).state).toBe("Uncertain");
    expect(cancelUnpaidCheckout).not.toHaveBeenCalled();
    expect(requestReconciliation).not.toHaveBeenCalled();
  });
  it("returns a confirmed payment without attempting cancellation", async () => {
    checkoutRecovery.mockResolvedValue({
      state: "Confirmed",
      order: { paymentId: "payment1" }
    });
    expect((await cancelCheckout("payment1", pollingScope())).state).toBe(
      "Confirmed"
    );
    expect(cancelUnpaidCheckout).not.toHaveBeenCalled();
  });
  it("does not expose implementation errors to customers", () => {
    expect(
      customerMessage({
        body: {
          message: "Named Credential callout failed in GVRazorpayService"
        }
      })
    ).toContain("Checking payment securely");
    expect(
      customerMessage({
        body: { message: "SELECT Id FROM Payment__c: unexpected token" }
      })
    ).not.toContain("SELECT");
  });
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
