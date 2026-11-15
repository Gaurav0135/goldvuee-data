import { LightningElement } from "lwc";
import storyImages from "@salesforce/resourceUrl/gvStoryImages";

export default class GvOurStory extends LightningElement {
  // Images stored in one Salesforce Static Resource ZIP
  heroImage = `${storyImages}/hero.jpg`;
  craftImage = `${storyImages}/craft.jpg`;
  detailImage = `${storyImages}/detail.jpg`;

  // Experience Cloud relative route
  // Confirm this matches the existing Collections page.
  collectionsUrl = "./collections";
}
