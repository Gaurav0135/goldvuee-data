import { LightningElement } from "lwc";
import inventory from "@salesforce/apex/GVCheckoutOperations.inventory";
import reviewQueue from "@salesforce/apex/GVCheckoutOperations.reviewQueue";
import fulfillmentQueue from "@salesforce/apex/GVCheckoutOperations.fulfillmentQueue";
import adjustStock from "@salesforce/apex/GVCheckoutOperations.adjustStock";
import reconcilePayment from "@salesforce/apex/GVCheckoutOperations.reconcilePayment";
import advanceOrder from "@salesforce/apex/GVCheckoutOperations.advanceOrder";
export default class GvOperationsConsole extends LightningElement {
  products = [];
  payments = [];
  orders = [];
  busy = false;
  error = "";
  message = "";
  productId = "";
  delta = "";
  reason = "";
  connectedCallback() {
    this.refresh();
  }
  get productOptions() {
    return this.products.map((p) => ({ label: p.Name, value: p.Id }));
  }
  get hasPayments() {
    return this.payments.length > 0;
  }
  get hasOrders() {
    return this.orders.length > 0;
  }
  async refresh() {
    this.busy = true;
    this.error = "";
    try {
      const [products, payments, orders] = await Promise.all([
        inventory(),
        reviewQueue(),
        fulfillmentQueue()
      ]);
      this.products = products;
      this.payments = payments.map((p) => ({
        ...p,
        orderName: p.Jewellery_Order__r?.Name
      }));
      const next = {
        Confirmed: "Processing",
        Processing: "Shipped",
        Shipped: "Delivered"
      };
      this.orders = orders.map((o) => ({
        ...o,
        next: next[o.Order_Status__c]
      }));
    } catch (e) {
      this.error = e?.body?.message || e.message;
    } finally {
      this.busy = false;
    }
  }
  handleField(event) {
    this[event.target.name] = event.detail?.value ?? event.target.value;
  }
  async handleAdjustment() {
    if (this.busy) return;
    const delta = Number(this.delta);
    if (
      !this.productId ||
      !Number.isInteger(delta) ||
      delta === 0 ||
      !this.reason.trim()
    ) {
      this.error =
        "Select a product, enter a nonzero whole-unit change and a reason.";
      return;
    }
    await this.perform(
      () =>
        adjustStock({
          productId: this.productId,
          delta,
          reason: this.reason.trim()
        }),
      "Inventory adjustment recorded."
    );
  }
  async handleReconcile(event) {
    const paymentId = event.target.dataset.id;
    await this.perform(
      () => reconcilePayment({ paymentId }),
      "Reconciliation queued. Refresh to see the result."
    );
  }
  async handleAdvance(event) {
    const orderId = event.target.dataset.id;
    const nextStatus = event.target.dataset.next;
    await this.perform(
      () => advanceOrder({ orderId, nextStatus }),
      "Order advanced to " + nextStatus + "."
    );
  }
  async perform(action, message) {
    if (this.busy) return;
    this.busy = true;
    this.error = "";
    this.message = "";
    try {
      await action();
      this.message = message;
      await this.refresh();
    } catch (e) {
      this.error = e?.body?.message || e.message;
    } finally {
      this.busy = false;
    }
  }
}
