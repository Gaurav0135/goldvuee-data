
import { LightningElement } from "lwc";
import isGuest from "@salesforce/user/isGuest";
import basePath from "@salesforce/community/basePath";

import loadDelivery from "@salesforce/apex/GVCheckoutController.loadDelivery";
import prepareOrder from "@salesforce/apex/GVCheckoutController.prepareOrder";
import loadOrder from "@salesforce/apex/GVCheckoutController.loadOrder";

import startPayment from "@salesforce/apex/GVRazorpayController.startPayment";
import paymentStatus from "@salesforce/apex/GVRazorpayController.paymentStatus";
import refreshPayment from "@salesforce/apex/GVRazorpayController.refreshPayment";
import cancelPayment from "@salesforce/apex/GVRazorpayController.cancelPayment";

import getCart from "@salesforce/apex/GVCartController.getCart";

const WINDOW_MS = 120000;

const PHONE_MESSAGE =
  "Enter a valid Indian mobile number: 9691184503, +919691184503 or +91 9691184503.";

const EMPTY_ADDRESS = {
  fullName: "",
  phone: "",
  street: "",
  city: "",
  state: "",
  postalCode: "",
  country: "India"
};

// FIX 1: Correct Indian mobile validation.

function normalizeIndianPhone(value) {
  const digits = String(value || "")
    .replace(/\D/g, "");

  let phone = digits;

  if (
    phone.length === 12 &&
    phone.startsWith("91")
  ) {
    phone = phone.substring(2);
  }

  if (
    phone.length === 10 &&
    /^[6-9][0-9]{9}$/.test(phone)
  ) {
    return phone;
  }

  return "";
}


// Detect phone numbers incorrectly saved as street.
function looksLikePhoneNumber(value) {
  const text = String(value ?? "").trim();

  return (
    normalizeIndianPhone(text) !== "" ||
    /^\+?[0-9][0-9\s().-]{8,}$/.test(text)
  );
}

export default class GvCheckout extends LightningElement {
  guest = isGuest;

  step = 1;
  busy = false;

  error = "";
  notice = "";

  delivery = { ...EMPTY_ADDRESS };

  summary;
  payment;

  timer;
  deadlineTimer;

  monitoring = false;
  timedOut = false;
  remainingSeconds = 0;

  deadline = 0;
  nextGatewayCheck = 0;

  detached = false;
  pollInFlight = false;
  monitorVersion = 0;

  paymentWindow;
  intentOpen = false;

  // NAVIGATION

  get loginUrl() {
    return `${basePath}/login`;
  }

  get cartUrl() {
    return `${basePath}/shopping-cart`;
  }

  get shoppingUrl() {
    return `${basePath}/collections`;
  }

  // CHECKOUT STEPS

  get addressStep() {
    return this.step === 1;
  }

  get summaryStep() {
    return this.step === 2;
  }

  get paymentStep() {
    return this.step === 3;
  }

  get addressClass() {
    return this.addressStep ? "active" : "";
  }

  get summaryClass() {
    return this.summaryStep ? "active" : "";
  }

  get paymentClass() {
    return this.paymentStep ? "active" : "";
  }

  // ORDER ITEMS

  get items() {
    return (this.summary?.items || []).map((i) => ({
      id: i.Id,
      name: i.Jewellery_Product__r?.Name || "",
      image:
        i.Jewellery_Product__r?.Main_Image_URL__c,
      quantity: i.Quantity__c,
      total: i.Line_Total__c
    }));
  }

  get total() {
    return this.summary?.total || 0;
  }

  get snapshot() {
    const d = this.summary?.delivery || {};

    return [
      d.fullName || "",
      d.phone || "",
      d.street || "",
      [d.city, d.state, d.postalCode]
        .filter(Boolean)
        .join(", "),
      d.country || "India"
    ]
      .filter(Boolean)
      .join("\n");
  }

  // PAYMENT STATE

  get hasPaymentUrl() {
    return !!this.payment?.paymentUrl;
  }

  get payDisabled() {
    return this.busy || this.monitoring || this.paid;
  }

  get paid() {
    return (
      this.payment?.paymentStatus === "Success"
    );
  }

  get unpaid() {
    return !this.paid;
  }

  get terminal() {
    return (
      ["Cancelled", "Expired"].includes(
        this.payment?.state
      ) ||
      this.payment?.paymentStatus === "Failed"
    );
  }

  get failedAttempt() {
    return (
      this.payment?.state === "Ready" &&
      this.payment?.lastFailureState === "failed"
    );
  }

  get showResult() {
    return (
      this.paid ||
      this.terminal ||
      this.failedAttempt
    );
  }

  get paymentId() {
    return this.summary?.paymentId;
  }

  get deadlineKey() {
    return `gvPaymentDeadline:${this.paymentId}`;
  }

  get message() {
    if (
      this.timedOut &&
      !this.paid &&
      !this.terminal
    ) {
      return "Payment not confirmed yet. You can keep shopping. This attempt remains pending verification; do not create a replacement charge.";
    }

    return (
      this.payment?.message ||
      "Pay securely on Razorpay using Test Mode."
    );
  }

  // ADDRESS NORMALIZATION

  normalizeDelivery(data, autofill = true) {
    const result = {};

    Object.keys(EMPTY_ADDRESS).forEach((key) => {
      const value = data?.[key];

      const clean =
        value === null || value === undefined
          ? ""
          : String(value).trim();

      result[key] =
        /^(undefined|null)$/i.test(clean)
          ? ""
          : clean;
    });

    result.country = result.country || "India";

    if (autofill) {
      // Normalize valid Contact mobile numbers.
      result.phone =
        normalizeIndianPhone(result.phone) ||
        result.phone;

      // Never prefill street with a mobile number.
      if (looksLikePhoneNumber(result.street)) {
        result.street = "";
      }

      // Prevent invalid Contact values from autofilling.
      const limits = {
        fullName: 120,
        street: 1000,
        city: 50,
        state: 50
      };

      Object.keys(limits).forEach((key) => {
        if (result[key].length > limits[key]) {
          result[key] = "";
        }
      });

      if (
        !/^[1-9][0-9]{5}$/.test(
          result.postalCode
        )
      ) {
        result.postalCode = "";
      }

      if (
        result.country.toLowerCase() !== "india"
      ) {
        result.country = "India";
      }
    }

    return result;
  }

  // LOAD CUSTOMER DELIVERY INFORMATION

  async connectedCallback() {
    this.detached = false;

    if (this.guest) {
      return;
    }

    this.busy = true;

    try {
      this.delivery = this.normalizeDelivery(
        await loadDelivery()
      );

      const pid = sessionStorage.getItem(
        "gvHostedPayment"
      );

      if (pid) {
        const state = await paymentStatus({
          paymentId: pid
        });

        const cart = await getCart();

        if (
          cart.itemCount > 0 &&
          (state.paymentStatus === "Success" ||
            (state.cartId &&
              cart.cartId &&
              state.cartId !== cart.cartId))
        ) {
          sessionStorage.removeItem(
            "gvHostedPayment"
          );

          this.notice =
            state.paymentStatus === "Success"
              ? ""
              : "Your previous payment is being verified independently. You can check out your current bag.";

          return;
        }

        this.summary = await loadOrder({
          orderId: state.orderId
        });

        if (this.detached) {
          return;
        }

        this.step = 3;
        this.acceptPayment(state);

        const savedDeadline = Number(
          sessionStorage.getItem(
            this.deadlineKey
          )
        );

        if (
          !this.paid &&
          !this.terminal &&
          !this.failedAttempt &&
          savedDeadline
        ) {
          this.beginMonitoring(savedDeadline);
        }
      }
    } catch (e) {
      this.error =
        e?.body?.message ||
        "Unable to restore checkout. You can enter your delivery details below.";
    } finally {
      this.busy = false;
    }
  }

  // KEEP STREET TEXTAREA SYNCHRONIZED

  renderedCallback() {
    const street = this.template.querySelector(
      'textarea[name="street"]'
    );

    if (
      street &&
      street.value !== this.delivery.street
    ) {
      street.value = this.delivery.street;
    }
  }

  disconnectedCallback() {
    this.detached = true;
    this.monitoring = false;

    clearTimeout(this.timer);
    clearTimeout(this.deadlineTimer);
  }

  // FIX 2: INPUT HANDLING

  input(event) {
    const field = event.target;

    field.setCustomValidity("");

    this.delivery = {
      ...this.delivery,
      [field.name]: field.value || ""
    };

    // Clear previous error after user edits.
    this.error = "";
  }

  // FIX 3: COMPLETE ADDRESS VALIDATION

  async review() {
    if (this.busy) {
      return;
    }

    this.error = "";

    const fields = [
      ...this.template.querySelectorAll(
        "input[name], textarea[name]"
      )
    ];

    // Read latest values directly from fields.
    const formData = { ...this.delivery };

    fields.forEach((field) => {
      field.setCustomValidity("");

      formData[field.name] =
        field.value || "";
    });

    const normalized =
      this.normalizeDelivery(formData, false);

    const phone = normalizeIndianPhone(
      normalized.phone
      
    );
console.log("PHONE DEBUG:", {
  length: String(normalized.phone).length,
  digits: String(normalized.phone).replace(/\D/g, "").length,
  valid: Boolean(phone)
});


    const phoneInput = this.template.querySelector(
      'input[name="phone"]'
    );

    // Mobile number validation.
    if (!phone) {
      if (phoneInput) {
        phoneInput.setCustomValidity(
          PHONE_MESSAGE
        );

        phoneInput.reportValidity();
      }

      this.error = PHONE_MESSAGE;
      return;
    }

    const requiredFields = [
      "fullName",
      "street",
      "city",
      "state",
      "postalCode",
      "country"
    ];

    const missingField = requiredFields.find(
      (key) =>
        !String(normalized[key] || "").trim()
    );

    if (missingField) {
      const field = this.template.querySelector(
        `[name="${missingField}"]`
      );

      if (field) {
        field.setCustomValidity(
          "This field is required."
        );

        field.reportValidity();
      }

      this.error =
        "Please complete all delivery fields.";

      return;
    }

    // Indian PIN validation.
    if (
      !/^[1-9][0-9]{5}$/.test(
        normalized.postalCode
      )
    ) {
      this.error =
        "Enter a valid six-digit Indian PIN code.";

      const pinInput =
        this.template.querySelector(
          'input[name="postalCode"]'
        );

      if (pinInput) {
        pinInput.setCustomValidity(
          this.error
        );

        pinInput.reportValidity();
      }

      return;
    }

    // Country validation.
    if (
      normalized.country.toLowerCase() !==
      "india"
    ) {
      this.error =
        "Delivery is currently available in India only.";

      return;
    }

    // Street should not be a phone number.
    if (
      looksLikePhoneNumber(normalized.street)
    ) {
      this.error =
        "Enter your street address, not a phone number.";

      return;
    }

    // Match Apex field length restrictions.
    if (
      normalized.fullName.length > 120 ||
      normalized.street.length > 1000 ||
      normalized.city.length > 50 ||
      normalized.state.length > 50 ||
      normalized.country.length > 50
    ) {
      this.error =
        "One or more address fields exceed the allowed length.";

      return;
    }

    // Apex always receives 10-digit number.
    normalized.phone = phone;

    // Check other native HTML constraints.
    // Phone HTML pattern must be removed.
    const formValid = fields
      .map((field) => field.reportValidity())
      .every(Boolean);

    if (!formValid) {
      this.error =
        "Please correct the highlighted fields.";

      return;
    }

    this.delivery = normalized;

    this.busy = true;
    this.error = "";

    try {
      const next = await prepareOrder({
        delivery: normalized
      });

      if (
        this.summary?.paymentId &&
        this.summary.paymentId !== next.paymentId
      ) {
        this.stopMonitoring();

        this.payment = null;
        this.timedOut = false;

        sessionStorage.removeItem(
          "gvHostedPayment"
        );
      }

      this.summary = next;

      if (!this.detached) {
        this.step = 2;
      }
    } catch (e) {
      this.error =
        e?.body?.message ||
        e?.message ||
        "Unable to prepare your order.";
    } finally {
      this.busy = false;
    }
  }

  // CHECKOUT NAVIGATION

  address() {
    this.stopMonitoring();
    this.step = 1;
  }

  paymentStepNext() {
    this.step = 3;
  }

  backToSummary() {
    this.stopMonitoring();
    this.step = 2;
  }

  // PAYMENT MONITORING

  beginMonitoring(
    deadline = Date.now() + WINDOW_MS
  ) {
    this.monitorVersion += 1;
    this.pollInFlight = false;

    clearTimeout(this.timer);

    this.deadline = deadline;
    this.timedOut = false;
    this.monitoring = true;
    this.nextGatewayCheck = 0;

    sessionStorage.setItem(
      this.deadlineKey,
      String(deadline)
    );

    const left = deadline - Date.now();

    if (left <= 0) {
      this.expireWindow();
      return;
    }

    clearTimeout(this.deadlineTimer);

    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.deadlineTimer = setTimeout(
      () => this.expireWindow(),
      left
    );

    this.schedule();
  }

  stopMonitoring() {
    this.monitorVersion += 1;
    this.pollInFlight = false;

    clearTimeout(this.timer);
    clearTimeout(this.deadlineTimer);

    this.monitoring = false;
    this.remainingSeconds = 0;
    this.intentOpen = false;

    sessionStorage.removeItem(
      this.deadlineKey
    );
  }

  expireWindow() {
    this.monitorVersion += 1;
    this.pollInFlight = false;

    clearTimeout(this.timer);
    clearTimeout(this.deadlineTimer);

    this.monitoring = false;
    this.remainingSeconds = 0;
    this.busy = false;
    this.timedOut = true;
    this.intentOpen = false;

    // Server reconciliation remains active.
    // Payment is not automatically marked failed.
  }

  acceptPayment(state) {
    this.payment = state;

    if (
      this.paid ||
      this.terminal ||
      this.failedAttempt
    ) {
      this.timedOut = false;
      this.stopMonitoring();
      return;
    }

    if (
      this.intentOpen &&
      state.paymentUrl
    ) {
      this.launchHosted(state.paymentUrl);
    }
  }

  // START RAZORPAY PAYMENT

  async pay() {
    if (
      this.payDisabled ||
      !this.summary?.paymentId
    ) {
      return;
    }

    this.busy = true;
    this.error = "";
    this.intentOpen = true;

    // Open tab during click to avoid popup blocking.
    this.paymentWindow = window.open(
      "about:blank",
      "_blank"
    );

    if (this.paymentWindow) {
      this.paymentWindow.opener = null;
    }

    const deadline =
      Date.now() + WINDOW_MS;

    try {
      sessionStorage.setItem(
        "gvHostedPayment",
        this.paymentId
      );

      this.acceptPayment(
        await startPayment({
          paymentId: this.paymentId
        })
      );

      if (
        !this.paid &&
        !this.terminal &&
        !this.failedAttempt
      ) {
        this.beginMonitoring(deadline);
      }
    } catch (e) {
      this.intentOpen = false;

      if (
        this.paymentWindow &&
        !this.paymentWindow.closed
      ) {
        this.paymentWindow.close();
      }

      this.error =
        e?.body?.message ||
        "Unable to start payment. Verify the existing attempt before retrying.";
    } finally {
      this.busy = false;
    }
  }

  launchHosted(url) {
    if (
      !url?.startsWith("https://rzp.io/")
    ) {
      return;
    }

    this.intentOpen = false;

    if (
      this.paymentWindow &&
      !this.paymentWindow.closed
    ) {
      this.paymentWindow.location.replace(url);
    } else {
      this.notice =
        "Allow popups or use Open secure Razorpay payment. This checkout remains here to verify the result.";
    }
  }

  openPayment() {
    const url =
      this.payment?.paymentUrl;

    if (
      url?.startsWith("https://rzp.io/")
    ) {
      window.open(
        url,
        "_blank",
        "noopener,noreferrer"
      );
    }
  }

  // PAYMENT POLLING

  schedule() {
    if (
      this.detached ||
      !this.monitoring
    ) {
      return;
    }

    const left =
      this.deadline - Date.now();

    if (left <= 0) {
      this.expireWindow();
      return;
    }

    this.remainingSeconds =
      Math.ceil(left / 1000);

    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.timer = setTimeout(
      () => this.poll(),
      Math.min(1500, left)
    );
  }

  async poll() {
    if (
      !this.monitoring ||
      this.detached
    ) {
      return;
    }

    if (
      Date.now() >= this.deadline
    ) {
      this.expireWindow();
      return;
    }

    if (this.pollInFlight) {
      this.schedule();
      return;
    }

    this.pollInFlight = true;

    const pid = this.paymentId;
    const version = this.monitorVersion;

    try {
      const waiting = [
        "Queued",
        "Checking",
        "Cancelling",
        "Verifying"
      ].includes(this.payment?.state);

      const gatewayCheck =
        !waiting &&
        Date.now() >= this.nextGatewayCheck;

      if (gatewayCheck) {
        this.nextGatewayCheck =
          Date.now() + 5000;
      }

      const state = gatewayCheck
        ? await refreshPayment({
            paymentId: pid
          })
        : await paymentStatus({
            paymentId: pid
          });

      if (
        this.detached ||
        this.paymentId !== pid ||
        version !== this.monitorVersion
      ) {
        return;
      }

      this.acceptPayment(state);
    } catch {
      if (
        version === this.monitorVersion
      ) {
        this.error =
          "Payment verification is temporarily unavailable. Your payment has not been marked failed.";
      }
    } finally {
      if (
        version === this.monitorVersion
      ) {
        this.pollInFlight = false;
        this.schedule();
      }
    }
  }

  // REFRESH PAYMENT STATUS

  async refresh() {
    if (
      this.busy ||
      !this.paymentId
    ) {
      return;
    }

    this.busy = true;
    this.error = "";

    try {
      this.acceptPayment(
        await refreshPayment({
          paymentId: this.paymentId
        })
      );

      if (
        !this.paid &&
        !this.terminal &&
        !this.failedAttempt &&
        !this.monitoring
      ) {
        this.beginMonitoring();
      }
    } catch (e) {
      this.error =
        e?.body?.message ||
        "Verification unavailable. Please try again.";
    } finally {
      this.busy = false;
    }
  }

  // CANCEL UNPAID PAYMENT

  async cancel() {
    if (
      this.busy ||
      !this.paymentId
    ) {
      return;
    }

    this.busy = true;
    this.error = "";
    this.intentOpen = false;

    try {
      this.acceptPayment(
        await cancelPayment({
          paymentId: this.paymentId
        })
      );

      if (
        !this.paid &&
        !this.terminal &&
        !this.failedAttempt &&
        !this.monitoring
      ) {
        this.beginMonitoring();
      }
    } catch (e) {
      this.error =
        e?.body?.message ||
        "Cancellation is not confirmed. The attempt remains pending verification.";
    } finally {
      this.busy = false;
    }
  }

  // RETRY PAYMENT SAFELY

  async retry() {
    if (this.busy) {
      return;
    }

    if (!this.terminal) {
      this.notice =
        "Reusing and verifying the existing payment attempt. No second charge is being created.";

      if (!this.monitoring) {
        await this.pay();
      }

      return;
    }

    this.stopMonitoring();
    this.busy = true;
    this.error = "";

    try {
      this.summary = await prepareOrder({
        delivery: this.delivery
      });

      this.payment = null;
      this.timedOut = false;
      this.step = 3;

      sessionStorage.setItem(
        "gvHostedPayment",
        this.paymentId
      );
    } catch (e) {
      this.error =
        e?.body?.message ||
        "Unable to prepare a safe retry. Please verify payment status.";
    } finally {
      this.busy = false;
    }
  }
}
