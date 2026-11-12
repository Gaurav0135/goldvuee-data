import { LightningElement } from "lwc";
import basePath from "@salesforce/community/basePath";
import heroBanner from "@salesforce/resourceUrl/goldvueeHeroBanner";

export default class GoldvueeHero extends LightningElement {
  renderedCallback() {
    this.template.host.style.setProperty(
      "--gv-hero-image",
      `url("${heroBanner}")`
    );
  }

  get collectionsUrl() {
    return `${basePath}/collections`;
  }

  get newArrivalsUrl() {
    return `${basePath}/new-arrivals`;
  }
}
