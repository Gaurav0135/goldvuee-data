import { LightningElement } from "lwc";
import isGuest from "@salesforce/user/isGuest";
import basePath from "@salesforce/community/basePath";
import getCart from "@salesforce/apex/GVCartController.getCart";
import goldvueeLogo from "@salesforce/resourceUrl/goldvueeLogo";

export default class GoldvueeHeader extends LightningElement {
  bagCount = 0;
  cartVersion = 0;
  detached = false;
  cartChanged = (event) => {
    this.cartVersion += 1;
    const count = event.detail?.count;
    if (Number.isInteger(count) && count >= 0) this.bagCount = count;
    else this.refreshCart();
    try {
      localStorage.setItem(
        "goldvueecartrefresh",
        String(Date.now()) + ":" + Math.random()
      );
    } catch {
      /* Storage can be unavailable in restricted browsers. */
    }
  };
  refreshCart = async () => {
    if (isGuest || this.detached) return;
    const version = ++this.cartVersion;
    try {
      const cart = await getCart();
      if (
        !this.detached &&
        version === this.cartVersion &&
        Number.isInteger(cart.itemCount) &&
        cart.itemCount >= 0
      ) {
        this.bagCount = cart.itemCount;
      }
    } catch {
      /* Preserve the last known count if Salesforce is unavailable. */
    }
  };
  cartStorageChanged = (event) => {
    if (event.key === "goldvueecartrefresh") this.refreshCart();
  };
  cartVisible = () => {
    if (document.visibilityState === "visible") this.refreshCart();
  };
  connectedCallback() {
    this.detached = false;
    window.addEventListener("goldvueecartchange", this.cartChanged);
    window.addEventListener("focus", this.refreshCart);
    window.addEventListener("storage", this.cartStorageChanged);
    document.addEventListener("visibilitychange", this.cartVisible);
    this.refreshCart();
  }
  disconnectedCallback() {
    this.detached = true;
    this.cartVersion += 1;
    window.removeEventListener("goldvueecartchange", this.cartChanged);
    window.removeEventListener("focus", this.refreshCart);
    window.removeEventListener("storage", this.cartStorageChanged);
    document.removeEventListener("visibilitychange", this.cartVisible);
  }
  logoUrl = goldvueeLogo;
  isMobileMenuOpen = false;

  // Guest vs logged-in user
  get isLoggedIn() {
    return !isGuest;
  }

  // Site root
  get siteRoot() {
    return basePath.endsWith("/s")
      ? basePath.slice(0, -2)
      : basePath.replace(/\/$/, "");
  }

  // Navigation URLs
  get homeUrl() {
    return `${basePath}/`;
  }

  get collectionsUrl() {
    return `${basePath}/collections`;
  }

  get newArrivalsUrl() {
    return `${basePath}/new-arrivals`;
  }

  get storyUrl() {
    return `${basePath}/our-story`;
  }

  get contactUrl() {
    return `${basePath}/contact`;
  }

  // Customer URLs
  get cartUrl() {
    return `${basePath}/shopping-cart`;
  }

  get accountUrl() {
    return `${basePath}/my-account`;
  }

  get loginUrl() {
    return `${this.siteRoot}/login`;
  }

  // Mobile menu
  toggleMobileMenu() {
    this.isMobileMenuOpen = !this.isMobileMenuOpen;
  }

  get mobileMenuIcon() {
    return this.isMobileMenuOpen ? "utility:close" : "utility:rows";
  }
}
