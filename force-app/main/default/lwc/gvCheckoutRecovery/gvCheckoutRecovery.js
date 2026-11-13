/* eslint-disable no-await-in-loop, @lwc/lwc/no-async-operation -- Bounded, cancellable sequential recovery requests. */
import checkoutRecovery from "@salesforce/apex/GVOnlineCheckoutController.checkoutRecovery";
import requestReconciliation from "@salesforce/apex/GVOnlineCheckoutController.requestReconciliation";
import cancelUnpaidCheckout from "@salesforce/apex/GVOnlineCheckoutController.cancelUnpaidCheckout";

export function checkoutMessage(result) {
  if (result?.state === "Confirmed") return "Payment successful.";
  if (result?.state === "Cancelled") return "Checkout cancelled.";
  if (result?.state === "Interrupted") return "Complete your payment.";
  if (result?.state === "RecoveryRequired")
    return "Your stock reservation expired. Continue secure payment to check availability and reserve it again.";
  if (result?.state === "StockUnavailable")
    return "This item is currently unavailable. Your payment has not been restarted. Check availability again later or contact GoldVuee support.";
  if (result?.state === "Review")
    return "Your payment needs review. Please view My Orders or contact GoldVuee support before paying again.";
  if (result?.state === "Expired" && result.canCancel)
    return "Your checkout has expired. Cancel it to return to your bag.";
  return "Checking payment securely. Your checkout is protected. Please view My Orders before trying another payment.";
}

export function customerMessage(
  error,
  fallback = "We could not complete your request. Please try again."
) {
  const message = String(error?.body?.message || error?.message || "");
  if (/sign in/i.test(message)) return "Please sign in to continue.";
  if (/complete.*delivery|valid Indian|PIN code/i.test(message))
    return "Please complete your delivery information with a valid six-digit PIN code.";
  if (/stock|quantity|product.*unavailable/i.test(message))
    return "The requested quantity is unavailable. Please update your shopping bag.";
  if (/allow popups/i.test(message))
    return "Please allow the secure payment window in your browser.";
  if (/delivery.*frozen|different delivery/i.test(message))
    return "Cancel this checkout before changing delivery details.";
  if (
    /payment|Razorpay|reconcil|signature|callout|credential|Salesforce/i.test(
      message
    )
  )
    return checkoutMessage(null);
  return fallback;
}

// Back to Bag, Cancel and bag recovery share the same authenticated server boundary.
export async function cancelCheckout(paymentId, scope) {
  let result = await checkoutRecovery({ paymentId: paymentId || null });
  if (scope.cancelled) return null;
  if (!result.order) return { state: "Cancelled" };
  if (result.state === "Confirmed" || result.state === "Cancelled")
    return result;
  if (!result.canCancel) return result;
  result = await cancelUnpaidCheckout({ paymentId: result.order.paymentId });
  if (scope.cancelled) return null;
  if (result.state === "Cancelled") rememberPayment(null);
  return result;
}

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
      [
        "Confirmed",
        "Cancelled",
        "Review",
        "Interrupted",
        "Expired",
        "RecoveryRequired",
        "StockUnavailable"
      ].includes(result.state)
    )
      return result;
  }
  return null;
}
