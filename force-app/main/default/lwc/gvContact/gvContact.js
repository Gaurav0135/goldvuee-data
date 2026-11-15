import { LightningElement } from "lwc";
import storyImages from "@salesforce/resourceUrl/gvStoryImages";

export default class GvContact extends LightningElement {
  // Reuse the existing public marketing images.
  heroImage = `${storyImages}/detail.jpg`;

  // Existing Experience Cloud Collections route.
  collectionsUrl = "./collections";

  fullName = "";
  email = "";
  phone = "";
  enquiryType = "";
  orderNumber = "";
  message = "";

  showPreview = false;

  get showOrderNumber() {
    return this.enquiryType === "Order Support";
  }

  handleInputChange(event) {
    const field = event.target.name;
    const value = event.target.value;

    const allowedFields = [
      "fullName",
      "email",
      "phone",
      "enquiryType",
      "orderNumber",
      "message"
    ];

    if (allowedFields.includes(field)) {
      this[field] = value;
    }

    if (field === "enquiryType" && !this.showOrderNumber) {
      this.orderNumber = "";
    }

    this.showPreview = false;
  }

  handleSubmit(event) {
    event.preventDefault();

    const fields = this.template.querySelectorAll("input, select, textarea");

    let isValid = true;

    fields.forEach((field) => {
      if (!field.checkValidity()) {
        field.reportValidity();
        isValid = false;
      }
    });

    if (!isValid) {
      return;
    }

    // Phase 1: UI preview only.
    // No Salesforce Case is created here.
    this.showPreview = true;
  }

  dismissPreview() {
    this.showPreview = false;
  }
}
