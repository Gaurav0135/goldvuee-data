import { LightningElement } from "lwc";
import isGuest from "@salesforce/user/isGuest";
import basePath from "@salesforce/community/basePath";
import goldvueeLogo from "@salesforce/resourceUrl/goldvueeLogo";

export default class GoldvueeHeader extends LightningElement {
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
