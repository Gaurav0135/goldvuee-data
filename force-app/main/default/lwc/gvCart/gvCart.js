import { LightningElement } from "lwc";
import isGuest from "@salesforce/user/isGuest";
import basePath from "@salesforce/community/basePath";
import getCart from "@salesforce/apex/GVCartController.getCart";
import updateCartItem from "@salesforce/apex/GVCartController.updateCartItem";
import removeCartItem from "@salesforce/apex/GVCartController.removeCartItem";

export default class GvCart extends LightningElement {
  guest = isGuest;
  busy = false;
  error = "";
  items = [];
  count = 0;
  total = 0;
  get shoppingUrl() {
    return `${basePath}/collections`;
  }
  get checkoutUrl() {
    return `${basePath}/checkout`;
  }
  get loginUrl() {
    return `${basePath}/login`;
  }
  get hasItems() {
    return this.items.length > 0;
  }
  get rows() {
    return this.items.map((item) => ({
      ...item,
      decreaseDisabled: this.busy || item.quantity <= 1,
      increaseDisabled: this.busy || item.quantity >= 100
    }));
  }
  connectedCallback() {
    if (!this.guest) this.load();
  }
  apply(cart) {
    this.items = cart.items || [];
    this.count = cart.itemCount || 0;
    this.total = cart.totalAmount || 0;
    window.dispatchEvent(
      new CustomEvent("goldvueecartchange", { detail: { count: this.count } })
    );
  }
  async load() {
    this.busy = true;
    this.error = "";
    try {
      this.apply(await getCart());
    } catch (error) {
      this.error =
        error.body?.message || "We could not load your bag. Please refresh.";
    } finally {
      this.busy = false;
    }
  }
  async change(event) {
    if (this.busy) return;
    const { id, action } = event.currentTarget.dataset;
    const selected = this.items.find((item) => item.lineId === id);
    this.busy = true;
    this.error = "";
    try {
      const cart =
        action === "remove"
          ? await removeCartItem({ cartItemId: id })
          : await updateCartItem({
              cartItemId: id,
              quantity: selected.quantity + (action === "plus" ? 1 : -1)
            });
      this.apply(cart);
    } catch (error) {
      this.error =
        error.body?.message ||
        "We could not update your bag. Please try again.";
    } finally {
      this.busy = false;
    }
  }
}
