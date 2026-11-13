/* eslint-disable no-await-in-loop, @lwc/lwc/no-async-operation -- Bounded, cancellable sequential recovery requests. */
import checkoutRecovery from "@salesforce/apex/GVOnlineCheckoutController.checkoutRecovery";
import requestReconciliation from "@salesforce/apex/GVOnlineCheckoutController.requestReconciliation";

// Store only a lookup reference. Every restored status and total is fetched from Apex.
export function savedPaymentId() {
  try {
    return window.sessionStorage.getItem("goldvuee.checkout.payment") || null;
  } catch {
    return null;
  }
}
export function rememberPayment(paymentId) {
  try {
    if (paymentId)
      window.sessionStorage.setItem("goldvuee.checkout.payment", paymentId);
    else window.sessionStorage.removeItem("goldvuee.checkout.payment");
  } catch {
    /* Checkout remains usable when browser storage is unavailable. */
  }
}

// Each component owns one scope. Cancelling settles delays and suppresses late responses.
export function pollingScope() {
  let cancelled = false;
  let timer;
  let settle;
  return {
    get cancelled() {
      return cancelled;
    },
    cancel() {
      cancelled = true;
      clearTimeout(timer);
      if (settle) settle(false);
    },
    wait(ms) {
      if (cancelled) return Promise.resolve(false);
      return new Promise((resolve) => {
        settle = resolve;
        timer = setTimeout(() => {
          settle = null;
          resolve(!cancelled);
        }, ms);
      });
    }
  };
}

export async function reconcile(paymentId, scope, onUpdate = () => {}) {
  await requestReconciliation({ paymentId });
  for (const delay of [600, 1000, 1800, 3000, 5000, 8000]) {
    if (!(await scope.wait(delay))) return null;
    const result = await checkoutRecovery({ paymentId });
    if (scope.cancelled) return null;
    onUpdate(result);
    if (
      ["Confirmed", "Cancelled", "Review", "Interrupted", "Expired"].includes(
        result.state
      )
    )
      return result;
  }
  return null;
}
