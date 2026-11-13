import { LightningElement, api } from "lwc";
import basePath from "@salesforce/community/basePath";
import paymentStatus from "@salesforce/apex/GVRazorpayController.paymentStatus";
import refreshPayment from "@salesforce/apex/GVRazorpayController.refreshPayment";
export default class GvPaymentResult extends LightningElement {
  @api paymentId;
  restoredPaymentId;
  state;
  busy = false;
  error = "";
  get message() {
    return this.state?.message || "Refresh to verify the payment securely.";
  }
  get historyUrl() {
    return `${basePath}/my-orders`;
  }
  get checkoutUrl() {
    return `${basePath}/checkout`;
  }
  get shoppingUrl() {
    return `${basePath}/collections`;
  }
  async connectedCallback() {
    this.restoredPaymentId =
      this.paymentId || sessionStorage.getItem("gvHostedPayment");
    if (this.restoredPaymentId) {
      try {
        this.state = await paymentStatus({ paymentId: this.restoredPaymentId });
      } catch {
        this.error =
          "Sign in to the account that owns this order to view payment status.";
      }
    }
  }
  async refresh() {
    const paymentId = this.paymentId || this.restoredPaymentId;
    if (!paymentId || this.busy) return;
    this.busy = true;
    this.error = "";
    try {
      this.state = await refreshPayment({ paymentId });
    } catch (e) {
      this.error =
        e.body?.message ||
        "Payment verification unavailable. Please try again.";
    } finally {
      this.busy = false;
    }
  }
}
