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
  get loginUrl() {
    return `${basePath}/login`;
  }
  get shoppingUrl() {
    return `${basePath}/collections`;
  }
  get checkoutUrl() {
    return `${basePath}/checkout`;
  }
  get hasItems() {
    return this.items.length > 0;
  }
  connectedCallback() {
    if (!this.guest) this.load();
  }
  apply(cart) {
    this.items = (cart.items || []).map((i) => ({
      id: i.Id,
      name: i.Jewellery_Product__r.Name,
      image: i.Jewellery_Product__r.Main_Image_URL__c,
      quantity: i.Quantity__c,
      price: i.Unit_Price__c,
      total: i.Line_Total__c,
      min: i.Quantity__c <= 1
    }));
    this.count = cart.itemCount;
    this.total = cart.totalAmount;
    window.dispatchEvent(
      new CustomEvent("goldvueecartchange", { detail: { count: this.count } })
    );
  }
  async load() {
    this.busy = true;
    try {
      this.apply(await getCart());
    } catch (e) {
      this.error = e.body?.message || "Unable to load your bag.";
    } finally {
      this.busy = false;
    }
  }
  async change(event) {
    if (this.busy) return;
    const id = event.currentTarget.dataset.id;
    const item = this.items.find((i) => i.id === id);
    const action = event.currentTarget.dataset.action;
    this.busy = true;
    this.error = "";
    try {
      this.apply(
        action === "remove"
          ? await removeCartItem({ cartItemId: id })
          : await updateCartItem({
              cartItemId: id,
              quantity: item.quantity + (action === "plus" ? 1 : -1)
            })
      );
    } catch (e) {
      this.error = e.body?.message || "Unable to update your bag.";
    } finally {
      this.busy = false;
    }
  }
}
