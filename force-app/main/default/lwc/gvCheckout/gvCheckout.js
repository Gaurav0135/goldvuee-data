// import { LightningElement } from "lwc";
// import isGuest from "@salesforce/user/isGuest";
// import basePath from "@salesforce/community/basePath";
// import loadDelivery from "@salesforce/apex/GVCheckoutController.loadDelivery";
// import prepareOrder from "@salesforce/apex/GVCheckoutController.prepareOrder";
// import loadOrder from "@salesforce/apex/GVCheckoutController.loadOrder";
// import getCart from "@salesforce/apex/GVCartController.getCart";
// import startPayment from "@salesforce/apex/GVRazorpayController.startPayment";
// import retryPayment from "@salesforce/apex/GVRazorpayController.retryPayment";
// import paymentStatus from "@salesforce/apex/GVRazorpayController.paymentStatus";
// import refreshPayment from "@salesforce/apex/GVRazorpayController.refreshPayment";
// import cancelPayment from "@salesforce/apex/GVRazorpayController.cancelPayment";

// const PHONE_PATTERN = /\s*(?:\+91\s?)?[6-9][0-9]{9}\s*/.source;
// const EMPTY = {
//   fullName: "",
//   phone: "",
//   street: "",
//   city: "",
//   state: "",
//   postalCode: "",
//   country: "India"
// };
// const WINDOW_MS = 120000;
// function clean(value) {
//   const text = value == null ? "" : String(value).trim();
//   return /^(undefined|null)$/i.test(text) ? "" : text;
// }
// function normalizePhone(value) {
//   const text = clean(value);
//   return new RegExp(`^${PHONE_PATTERN}$`).test(text)
//     ? text.replace(/\s/g, "").replace(/^\+91/, "")
//     : "";
// }
// function phoneOnly(value) {
//   return /^\+?[0-9][0-9\s().-]{8,}$/.test(clean(value));
// }
// function address(data) {
//   const value = {};
//   Object.keys(EMPTY).forEach((key) => {
//     value[key] = clean(data?.[key]);
//   });
//   value.phone = normalizePhone(value.phone);
//   if (phoneOnly(value.street)) value.street = "";
//   value.country = value.country || "India";
//   return value;
// }

// export default class GvCheckout extends LightningElement {
//   guest = isGuest;
//   step = 1;
//   busy = false;
//   error = "";
//   notice = "";
//   delivery = { ...EMPTY };
//   summary;
//   payment;
//   monitoring = false;
//   timedOut = false;
//   seconds = 0;
//   deadline = 0;
//   timer;
//   deadlineTimer;
//   generation = 0;
//   nextGatewayCheck = 0;
//   detached = false;
//   paymentTab;
//   openWhenReady = false;
//   get phonePattern() {
//     return PHONE_PATTERN;
//   }
//   get loginUrl() {
//     return `${basePath}/login`;
//   }
//   get shoppingUrl() {
//     return `${basePath}/collections`;
//   }
//   get cartUrl() {
//     return `${basePath}/shopping-cart`;
//   }
//   get historyUrl() {
//     return `${basePath}/my-orders`;
//   }
//   get addressStep() {
//     return this.step === 1;
//   }
//   get summaryStep() {
//     return this.step === 2;
//   }
//   get paymentStep() {
//     return this.step === 3;
//   }
//   get addressClass() {
//     return this.addressStep ? "active" : "";
//   }
//   get summaryClass() {
//     return this.summaryStep ? "active" : "";
//   }
//   get paymentClass() {
//     return this.paymentStep ? "active" : "";
//   }
//   get items() {
//     return this.summary?.items || [];
//   }
//   get total() {
//     return this.summary?.total || 0;
//   }
//   get orderNumber() {
//     return this.summary?.orderNumber || "";
//   }
//   get paymentId() {
//     return this.summary?.paymentId;
//   }
//   get deadlineKey() {
//     return `gvDeadline:${this.paymentId}`;
//   }
//   get paid() {
//     return this.payment?.paymentStatus === "Success";
//   }
//   get closed() {
//     return this.payment?.paymentStatus === "Failed";
//   }
//   get failedTransaction() {
//     return (
//       this.payment?.state === "Ready" &&
//       this.payment?.lastFailureState === "failed"
//     );
//   }
//   get payDisabled() {
//     return (
//       this.busy ||
//       this.monitoring ||
//       this.paid ||
//       this.closed ||
//       this.payment?.state === "Legacy review"
//     );
//   }
//   get retryDisabled() {
//     return this.busy || this.monitoring || this.paid;
//   }
//   get hasPaymentUrl() {
//     return !!this.payment?.paymentUrl;
//   }
//   get resultTitle() {
//     return this.paid
//       ? this.payment.fulfillment === "Confirmed"
//         ? "Your order is confirmed"
//         : "Payment received; fulfillment needs review"
//       : this.closed || this.failedTransaction
//         ? "Payment unsuccessful"
//         : "Secure Razorpay test payment";
//   }
//   get message() {
//     return this.timedOut && !this.paid && !this.closed
//       ? "Payment not confirmed yet. Continue shopping while this attempt stays pending verification. Do not create a replacement charge."
//       : this.payment?.message ||
//           "Your total is verified by Salesforce. Pay securely on Razorpay.";
//   }
//   get snapshot() {
//     const d = this.summary?.delivery || {};
//     return [
//       d.fullName,
//       d.phone,
//       d.street,
//       [d.city, d.state, d.postalCode].filter(Boolean).join(", "),
//       d.country
//     ]
//       .filter(Boolean)
//       .join("\n");
//   }
//   async connectedCallback() {
//     if (this.guest) return;
//     this.busy = true;
//     try {
//       this.delivery = address(await loadDelivery());
//       const pid = sessionStorage.getItem("gvHostedPayment");
//       if (pid) {
//         const status = await paymentStatus({ paymentId: pid });
//         const cart = await getCart();
//         if (
//           cart.itemCount > 0 &&
//           (status.paymentStatus === "Success" || !status.matchesCurrentCart)
//         ) {
//           sessionStorage.removeItem("gvHostedPayment");
//           this.notice =
//             status.paymentStatus === "Success"
//               ? ""
//               : "Your previous payment is being verified independently. Your current bag is editable.";
//           return;
//         }
//         this.summary = await loadOrder({ orderId: status.orderId });
//         this.delivery = address(this.summary.delivery);
//         this.step = 3;
//         this.applyPayment(status);
//         const deadline = Number(sessionStorage.getItem(this.deadlineKey));
//         if (deadline && !this.paid && !this.closed)
//           this.beginMonitoring(deadline);
//       }
//     } catch (error) {
//       this.error =
//         error.body?.message ||
//         "Enter your delivery address below. We could not restore the previous checkout.";
//     } finally {
//       this.busy = false;
//     }
//   }
//   renderedCallback() {
//     const street = this.template.querySelector('textarea[name="street"]');
//     if (street && street.value !== this.delivery.street)
//       street.value = this.delivery.street;
//   }
//   disconnectedCallback() {
//     this.detached = true;
//     this.stopMonitoring(false);
//   }
//   input(event) {
//     event.target.setCustomValidity("");
//     this.delivery = {
//       ...this.delivery,
//       [event.target.name]: event.target.value
//     };
//     this.error = "";
//   }
//   async review() {
//     if (this.busy) return;
//     const fields = [...this.template.querySelectorAll("input,textarea")];
//     const values = { ...this.delivery };
//     fields.forEach((field) => {
//       values[field.name] = clean(field.value);
//     });
//     values.phone = normalizePhone(values.phone) || values.phone;
//     this.delivery = values;
//     this.busy = true;
//     this.error = "";
//     try {
//       const next = await prepareOrder({ delivery: values });
//       this.stopMonitoring();
//       this.payment = null;
//       this.summary = next;
//       this.timedOut = false;
//       this.step = 2;
//     } catch (error) {
//       this.error = error.body?.message || "Please check your delivery details.";
//     } finally {
//       this.busy = false;
//     }
//   }
//   changeAddress() {
//     this.stopMonitoring();
//     this.step = 1;
//   }
//   continueToPayment() {
//     this.step = 3;
//   }
//   backToSummary() {
//     this.stopMonitoring();
//     this.step = 2;
//   }
//   applyPayment(value) {
//     if (value.paymentId !== this.paymentId) {
//       const oldKey = this.deadlineKey;
//       this.summary = { ...this.summary, paymentId: value.paymentId };
//       sessionStorage.removeItem(oldKey);
//       if (this.deadline)
//         sessionStorage.setItem(this.deadlineKey, String(this.deadline));
//     }
//     // this.payment = value;
//     // sessionStorage.setItem("gvHostedPayment", value.paymentId);

// const wasConfirmed =
//   this.payment?.paymentStatus === "Success" &&
//   this.payment?.fulfillment === "Confirmed";

// this.payment = value;
// sessionStorage.setItem("gvHostedPayment", value.paymentId);

// // Update the header badge only after verified order confirmation.
// if (
//   !wasConfirmed &&
//   this.payment.paymentStatus === "Success" &&
//   this.payment.fulfillment === "Confirmed"
// ) {
//   window.dispatchEvent(
//     new CustomEvent("goldvueecartchange", {
//       detail: { count: 0 }
//     })
//   );
// }

//     if (this.paid || this.closed || this.failedTransaction) {
//       this.timedOut = false;
//       this.stopMonitoring();
//       return;
//     }
//     if (this.openWhenReady && value.paymentUrl?.startsWith("https://rzp.io/")) {
//       this.openWhenReady = false;
//       if (this.paymentTab && !this.paymentTab.closed)
//         this.paymentTab.location.replace(value.paymentUrl);
//       else
//         this.notice =
//           "Use Open Razorpay payment below if your browser blocked the payment tab.";
//     }
//   }
//   pay() {
//     return this.payWith(false);
//   }
//   retry() {
//     return this.payWith(true);
//   }
//   async payWith(retry) {
//     if (this.busy || this.monitoring || this.paid || !this.paymentId) return;
//     this.busy = true;
//     this.error = "";
//     this.paymentTab = window.open("about:blank", "_blank");
//     if (this.paymentTab) this.paymentTab.opener = null;
//     this.openWhenReady = true;
//     sessionStorage.setItem("gvHostedPayment", this.paymentId);
//     this.beginMonitoring();
//     try {
//       const value = retry
//         ? await retryPayment({ paymentId: this.paymentId })
//         : await startPayment({ paymentId: this.paymentId });
//       if (!this.detached) this.applyPayment(value);
//     } catch (error) {
//       this.stopMonitoring();
//       if (this.paymentTab && !this.paymentTab.closed) this.paymentTab.close();
//       this.error =
//         error.body?.message ||
//         "Payment initialization needs verification. No replacement charge was created.";
//     } finally {
//       this.busy = false;
//     }
//   }
//   openPayment() {
//     if (this.payment?.paymentUrl?.startsWith("https://rzp.io/"))
//       window.open(this.payment.paymentUrl, "_blank", "noopener,noreferrer");
//   }
//   beginMonitoring(deadline = Date.now() + WINDOW_MS) {
//     this.stopMonitoring(false);
//     this.deadline = deadline;
//     this.timedOut = false;
//     this.monitoring = true;
//     this.nextGatewayCheck = 0;
//     sessionStorage.setItem(this.deadlineKey, String(deadline));
//     const left = deadline - Date.now();
//     if (left <= 0) {
//       this.expireWindow();
//       return;
//     }
//     // Independent deadline releases the UI even when an RPC stalls.
//     // eslint-disable-next-line @lwc/lwc/no-async-operation
//     this.deadlineTimer = setTimeout(() => this.expireWindow(), left);
//     this.schedule();
//   }
//   stopMonitoring(clearDeadline = true) {
//     this.generation += 1;
//     clearTimeout(this.timer);
//     clearTimeout(this.deadlineTimer);
//     this.monitoring = false;
//     this.seconds = 0;
//     if (clearDeadline) {
//       this.openWhenReady = false;
//       sessionStorage.removeItem(this.deadlineKey);
//     }
//   }
//   expireWindow() {
//     const unopened = this.openWhenReady;
//     this.stopMonitoring(false);
//     this.openWhenReady = false;
//     this.busy = false;
//     this.timedOut = true;
//     if (unopened && this.paymentTab && !this.paymentTab.closed)
//       this.paymentTab.close();
//   }
//   schedule() {
//     if (!this.monitoring || this.detached) return;
//     const left = this.deadline - Date.now();
//     if (left <= 0) {
//       this.expireWindow();
//       return;
//     }
//     this.seconds = Math.ceil(left / 1000);
//     // Bounded status checks, cancelled on disconnect and the UI deadline.
//     // eslint-disable-next-line @lwc/lwc/no-async-operation
//     this.timer = setTimeout(() => this.poll(), Math.min(1500, left));
//   }
//   async poll() {
//     if (!this.monitoring || this.detached) return;
//     const version = this.generation;
//     const pid = this.paymentId;
//     try {
//       const waiting = [
//         "Queued",
//         "Checking",
//         "Cancelling",
//         "Verifying"
//       ].includes(this.payment?.state);
//       const verify = !waiting && Date.now() >= this.nextGatewayCheck;
//       if (verify) this.nextGatewayCheck = Date.now() + 5000;
//       const value = verify
//         ? await refreshPayment({ paymentId: pid })
//         : await paymentStatus({ paymentId: pid });
//       if (
//         !this.detached &&
//         this.generation === version &&
//         this.paymentId === pid
//       )
//         this.applyPayment(value);
//     } catch {
//       if (this.generation === version)
//         this.error =
//           "Verification is temporarily unavailable. This has not marked your payment failed.";
//     } finally {
//       if (this.generation === version) this.schedule();
//     }
//   }
//   refresh() {
//     return this.check(false);
//   }
//   cancel() {
//     return this.check(true);
//   }
//   async check(cancel) {
//     if (this.busy || !this.paymentId) return;
//     this.busy = true;
//     this.error = "";
//     this.openWhenReady = false;
//     try {
//       this.applyPayment(
//         cancel
//           ? await cancelPayment({ paymentId: this.paymentId })
//           : await refreshPayment({ paymentId: this.paymentId })
//       );
//       if (
//         !this.paid &&
//         !this.closed &&
//         !this.failedTransaction &&
//         !this.monitoring
//       )
//         this.beginMonitoring();
//     } catch (error) {
//       this.error =
//         error.body?.message ||
//         "Payment verification is unavailable. Please try again.";
//     } finally {
//       this.busy = false;
//     }
//   }
// }

import { LightningElement } from "lwc";
import isGuest from "@salesforce/user/isGuest";
import basePath from "@salesforce/community/basePath";

import loadDelivery from "@salesforce/apex/GVCheckoutController.loadDelivery";
import prepareOrder from "@salesforce/apex/GVCheckoutController.prepareOrder";
import loadOrder from "@salesforce/apex/GVCheckoutController.loadOrder";
import getCart from "@salesforce/apex/GVCartController.getCart";

import startPayment from "@salesforce/apex/GVRazorpayController.startPayment";
import retryPayment from "@salesforce/apex/GVRazorpayController.retryPayment";
import paymentStatus from "@salesforce/apex/GVRazorpayController.paymentStatus";
import refreshPayment from "@salesforce/apex/GVRazorpayController.refreshPayment";
import cancelPayment from "@salesforce/apex/GVRazorpayController.cancelPayment";

const PHONE_PATTERN = /\s*(?:\+91\s?)?[6-9][0-9]{9}\s*/.source;

const EMPTY = {
  fullName: "",
  phone: "",
  street: "",
  city: "",
  state: "",
  postalCode: "",
  country: "India"
};

const WINDOW_MS = 120000;

function clean(value) {
  const text = value == null ? "" : String(value).trim();
  return /^(undefined|null)$/i.test(text) ? "" : text;
}

function normalizePhone(value) {
  const text = clean(value);
  return new RegExp(`^${PHONE_PATTERN}$`).test(text)
    ? text.replace(/\s/g, "").replace(/^\+91/, "")
    : "";
}

function phoneOnly(value) {
  return /^\+?[0-9][0-9\s().-]{8,}$/.test(clean(value));
}

function address(data) {
  const value = {};

  Object.keys(EMPTY).forEach((key) => {
    value[key] = clean(data?.[key]);
  });

  value.phone = normalizePhone(value.phone);

  if (phoneOnly(value.street)) {
    value.street = "";
  }

  value.country = value.country || "India";

  return value;
}

export default class GvCheckout extends LightningElement {
  guest = isGuest;
  step = 1;
  busy = false;
  error = "";
  notice = "";

  delivery = { ...EMPTY };
  summary;
  payment;

  monitoring = false;
  timedOut = false;
  seconds = 0;
  deadline = 0;
  timer;
  deadlineTimer;
  generation = 0;
  nextGatewayCheck = 0;
  detached = false;
  paymentTab;
  openWhenReady = false;
  cartVersion = 0;
  cartChanged = () => {
    this.cartVersion += 1;
  };
  cartStorageChanged = (event) => {
    if (event.key === "goldvueecartrefresh") this.cartVersion += 1;
  };
  cartFocus = () => {
    if (this.paid && this.payment?.fulfillment === "Confirmed") {
      this.syncCartBadge(this.payment.paymentId);
    }
  };
  cartSyncPending = false;
  cartSyncedPayment;
  gatewayDeadlineKey;
  gatewayDeadline;
  gatewayExpiryReached = false;

  get phonePattern() {
    return PHONE_PATTERN;
  }

  get loginUrl() {
    return `${basePath}/login`;
  }

  get shoppingUrl() {
    return `${basePath}/collections`;
  }

  get cartUrl() {
    return `${basePath}/shopping-cart`;
  }

  get historyUrl() {
    return `${basePath}/my-orders`;
  }

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

  get items() {
    return this.summary?.items || [];
  }

  get total() {
    return this.summary?.total || 0;
  }

  get orderNumber() {
    return this.summary?.orderNumber || "";
  }

  get paymentId() {
    return this.summary?.paymentId;
  }

  get deadlineKey() {
    return `gvDeadline:${this.paymentId}`;
  }

  get paid() {
    return this.payment?.paymentStatus === "Success";
  }

  get closed() {
    return this.payment?.paymentStatus === "Failed";
  }

  get failedTransaction() {
    return (
      this.payment?.paymentStatus === "Pending" &&
      ["Ready", "Checking", "Cancelling"].includes(this.payment?.state) &&
      this.payment?.lastFailureState === "failed"
    );
  }

  get payDisabled() {
    return (
      this.busy ||
      this.monitoring ||
      this.paid ||
      this.closed ||
      this.gatewayExpiryReached ||
      this.payment?.state === "Legacy review"
    );
  }

  get retryDisabled() {
    return (
      this.busy ||
      this.monitoring ||
      this.paid ||
      (this.gatewayExpiryReached && !this.closed)
    );
  }

  get hasPaymentUrl() {
    return !!this.payment?.paymentUrl && !this.gatewayExpiryReached;
  }

  get resultTitle() {
    return this.paid
      ? this.payment.fulfillment === "Confirmed"
        ? "Your order is confirmed"
        : "Payment received; fulfillment needs review"
      : this.payment?.expiredByTimer
        ? "Payment time expired"
        : this.closed || this.failedTransaction
          ? "Payment unsuccessful"
          : "Secure Razorpay test payment";
  }

  get message() {
    if (this.gatewayExpiryReached && !this.paid && !this.closed) {
      return "Payment window ended. Verifying that the unpaid link is closed before allowing a new attempt. A captured payment will still be honored.";
    }
    if (this.failedTransaction && this.payment?.state === "Ready") {
      return "Payment unsuccessful - retry available using the existing payment link.";
    }
    return this.timedOut &&
      !this.paid &&
      !this.closed &&
      !this.failedTransaction
      ? "Payment not confirmed yet. Continue shopping while this attempt stays pending verification. Do not create a replacement charge."
      : this.payment?.message ||
          "Your total is verified by Salesforce. Pay securely on Razorpay.";
  }

  get monitoringMessage() {
    if (this.gatewayExpiryReached)
      return "Payment window ended. Checking final payment status.";
    if (this.payment?.state === "Queued" && !this.payment?.paymentExpiresAt)
      return "Preparing your secure payment link.";
    return `Verifying payment - ${this.seconds} seconds remaining`;
  }

  get snapshot() {
    const d = this.summary?.delivery || {};

    return [
      d.fullName,
      d.phone,
      d.street,
      [d.city, d.state, d.postalCode].filter(Boolean).join(", "),
      d.country
    ]
      .filter(Boolean)
      .join("\n");
  }

  async connectedCallback() {
    this.detached = false;
    this.gatewayDeadlineKey = null;
    this.cartSyncedPayment = null;
    window.addEventListener("goldvueecartchange", this.cartChanged);
    window.addEventListener("focus", this.cartFocus);
    window.addEventListener("storage", this.cartStorageChanged);
    if (this.guest) return;

    this.busy = true;

    try {
      this.delivery = address(await loadDelivery());

      const pid = sessionStorage.getItem("gvHostedPayment");

      if (pid) {
        const status = await paymentStatus({
          paymentId: pid
        });

        const cart = await getCart();
        if (
          status.paymentStatus === "Success" &&
          status.fulfillment === "Confirmed"
        ) {
          this.syncCartBadge(status.paymentId, true);
        }

        if (
          cart.itemCount > 0 &&
          (status.paymentStatus === "Success" || !status.matchesCurrentCart)
        ) {
          sessionStorage.removeItem("gvHostedPayment");

          this.notice =
            status.paymentStatus === "Success"
              ? ""
              : "Your previous payment is being verified independently. Your current bag is editable.";

          return;
        }

        this.summary = await loadOrder({
          orderId: status.orderId
        });

        this.delivery = address(this.summary.delivery);
        this.step = 3;

        this.applyPayment(status);

        const deadline = Number(sessionStorage.getItem(this.deadlineKey));

        if (
          deadline &&
          !this.paid &&
          !this.closed &&
          !status.paymentExpiresAt
        ) {
          this.beginMonitoring(deadline);
        }
      }
    } catch (error) {
      this.error =
        error.body?.message ||
        "Enter your delivery address below. We could not restore the previous checkout.";
    } finally {
      this.busy = false;
    }
  }

  renderedCallback() {
    const street = this.template.querySelector('textarea[name="street"]');

    if (street && street.value !== this.delivery.street) {
      street.value = this.delivery.street;
    }
  }

  disconnectedCallback() {
    this.detached = true;
    this.cartVersion += 1;
    window.removeEventListener("goldvueecartchange", this.cartChanged);
    window.removeEventListener("focus", this.cartFocus);
    window.removeEventListener("storage", this.cartStorageChanged);
    this.stopMonitoring(false);
  }

  input(event) {
    event.target.setCustomValidity("");

    this.delivery = {
      ...this.delivery,
      [event.target.name]: event.target.value
    };

    this.error = "";
  }

  async review() {
    if (this.busy) return;

    const fields = [...this.template.querySelectorAll("input,textarea")];

    const values = { ...this.delivery };

    fields.forEach((field) => {
      values[field.name] = clean(field.value);
    });

    values.phone = normalizePhone(values.phone) || values.phone;

    this.delivery = values;
    this.busy = true;
    this.error = "";

    try {
      const next = await prepareOrder({
        delivery: values
      });

      this.stopMonitoring();

      this.payment = null;
      this.gatewayDeadlineKey = null;
      this.gatewayExpiryReached = false;
      this.summary = next;
      this.timedOut = false;
      this.step = 2;
    } catch (error) {
      this.error = error.body?.message || "Please check your delivery details.";
    } finally {
      this.busy = false;
    }
  }

  changeAddress() {
    this.stopMonitoring();
    this.step = 1;
  }

  continueToPayment() {
    this.step = 3;
  }

  backToSummary() {
    this.stopMonitoring();
    this.step = 2;
  }

  applyPayment(value) {
    if (value.paymentId !== this.paymentId) {
      const oldKey = this.deadlineKey;

      this.summary = {
        ...this.summary,
        paymentId: value.paymentId
      };

      sessionStorage.removeItem(oldKey);

      if (this.deadline) {
        sessionStorage.setItem(this.deadlineKey, String(this.deadline));
      }
    }

    this.payment = value;
    const expiresAt = Number(value.paymentExpiresAt);
    const serverNow = Number(value.serverNow);
    const deadlineKey = `${value.paymentId}:${expiresAt}`;
    if (
      expiresAt > 0 &&
      serverNow > 0 &&
      !this.paid &&
      !this.closed &&
      this.gatewayDeadlineKey !== deadlineKey
    ) {
      this.gatewayDeadlineKey = deadlineKey;
      this.gatewayExpiryReached = false;
      // Use remaining gateway time, adjusted for the client clock; never restart on reload.
      this.gatewayDeadline = Date.now() + Math.max(0, expiresAt - serverNow);
      this.beginMonitoring(this.gatewayDeadline);
    }
    if (this.paid || this.closed) this.gatewayExpiryReached = false;

    sessionStorage.setItem("gvHostedPayment", value.paymentId);

    // NEW: Sync cart badge using the actual Salesforce cart.
    if (
      value.paymentStatus === "Success" &&
      value.fulfillment === "Confirmed"
    ) {
      this.syncCartBadge(value.paymentId);
    }

    // Existing payment lifecycle remains unchanged.
    if (
      this.paid ||
      this.closed ||
      (this.failedTransaction &&
        value.state === "Ready" &&
        !this.gatewayExpiryReached)
    ) {
      this.timedOut = false;
      this.stopMonitoring();
      if (
        this.failedTransaction &&
        value.paymentExpiresAt &&
        !this.gatewayExpiryReached
      ) {
        // Keep the link deadline armed while allowing a safe retry of this same active link.
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.deadlineTimer = setTimeout(
          () => this.expireWindow(),
          Math.max(0, this.gatewayDeadline - Date.now())
        );
      }
      return;
    }

    if (this.openWhenReady && value.paymentUrl?.startsWith("https://rzp.io/")) {
      this.openWhenReady = false;

      if (this.paymentTab && !this.paymentTab.closed) {
        this.paymentTab.location.replace(value.paymentUrl);
      } else {
        this.notice =
          "Use Open Razorpay payment below if your browser blocked the payment tab.";
      }
    }
  }

  // NEW: Read real cart count after successful fulfillment.
  async syncCartBadge(confirmedPaymentId, restoring = false) {
    if (this.cartSyncPending || this.cartSyncedPayment === confirmedPaymentId)
      return;
    this.cartSyncPending = true;
    const version = this.cartVersion;
    try {
      const cart = await getCart();

      if (
        !this.detached &&
        version === this.cartVersion &&
        Number.isInteger(cart.itemCount) &&
        cart.itemCount >= 0 &&
        (restoring ||
          (this.payment?.paymentId === confirmedPaymentId &&
            this.payment?.paymentStatus === "Success" &&
            this.payment?.fulfillment === "Confirmed"))
      ) {
        this.cartSyncedPayment = confirmedPaymentId;
        window.dispatchEvent(
          new CustomEvent("goldvueecartchange", {
            detail: {
              count: cart.itemCount
            }
          })
        );
      }
    } catch {
      // Do not show an incorrect zero if refresh fails.
      // Existing payment confirmation remains unaffected.
    } finally {
      this.cartSyncPending = false;
    }
  }

  pay() {
    return this.payWith(false);
  }

  retry() {
    return this.payWith(true);
  }

  async payWith(retry) {
    if (this.busy || this.monitoring || this.paid || !this.paymentId) {
      return;
    }

    this.busy = true;
    this.error = "";

    this.paymentTab = window.open("about:blank", "_blank");

    if (this.paymentTab) {
      this.paymentTab.opener = null;
    }

    this.openWhenReady = true;

    sessionStorage.setItem("gvHostedPayment", this.paymentId);

    this.beginMonitoring();

    try {
      const value = retry
        ? await retryPayment({
            paymentId: this.paymentId
          })
        : await startPayment({
            paymentId: this.paymentId
          });

      if (!this.detached) {
        this.applyPayment(value);
      }
    } catch (error) {
      this.stopMonitoring();

      if (this.paymentTab && !this.paymentTab.closed) {
        this.paymentTab.close();
      }

      this.error =
        error.body?.message ||
        "Payment initialization needs verification. No replacement charge was created.";
    } finally {
      this.busy = false;
    }
  }

  openPayment() {
    if (this.payment?.paymentUrl?.startsWith("https://rzp.io/")) {
      window.open(this.payment.paymentUrl, "_blank", "noopener,noreferrer");
    }
  }

  beginMonitoring(deadline) {
    deadline =
      deadline ??
      (this.payment?.paymentExpiresAt &&
      !this.gatewayExpiryReached &&
      this.gatewayDeadlineKey?.startsWith(`${this.paymentId}:`)
        ? this.gatewayDeadline
        : Date.now() + WINDOW_MS);
    this.stopMonitoring(false);

    this.deadline = deadline;
    this.timedOut = false;
    this.monitoring = true;
    this.nextGatewayCheck = 0;

    sessionStorage.setItem(this.deadlineKey, String(deadline));

    const left = deadline - Date.now();

    if (left <= 0) {
      // Let the current status RPC release busy before requesting terminal verification.
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      this.deadlineTimer = setTimeout(() => this.expireWindow(), 0);
      return;
    }

    // Independent deadline releases UI if an RPC stalls.
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.deadlineTimer = setTimeout(() => this.expireWindow(), left);

    this.schedule();
  }

  stopMonitoring(clearDeadline = true) {
    this.generation += 1;

    clearTimeout(this.timer);
    clearTimeout(this.deadlineTimer);

    this.monitoring = false;
    this.seconds = 0;

    if (clearDeadline) {
      this.openWhenReady = false;
      sessionStorage.removeItem(this.deadlineKey);
    }
  }

  expireWindow() {
    const unopened = this.openWhenReady;

    this.stopMonitoring(false);

    this.openWhenReady = false;
    this.busy = false;
    this.timedOut = true;
    if (
      this.payment?.paymentExpiresAt &&
      !this.gatewayExpiryReached &&
      !this.paid &&
      !this.closed &&
      !this.detached
    ) {
      this.gatewayExpiryReached = true;
      this.openWhenReady = false;
      this.check(false);
    }

    if (unopened && this.paymentTab && !this.paymentTab.closed) {
      this.paymentTab.close();
    }
  }

  schedule() {
    if (!this.monitoring || this.detached) {
      return;
    }

    const left = this.deadline - Date.now();

    if (left <= 0) {
      this.expireWindow();
      return;
    }

    this.seconds = Math.ceil(left / 1000);

    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.timer = setTimeout(() => this.poll(), Math.min(1500, left));
  }

  async poll() {
    if (!this.monitoring || this.detached) {
      return;
    }

    const version = this.generation;
    const pid = this.paymentId;

    try {
      const waiting = [
        "Queued",
        "Checking",
        "Cancelling",
        "Verifying"
      ].includes(this.payment?.state);

      const verify = !waiting && Date.now() >= this.nextGatewayCheck;

      if (verify) {
        this.nextGatewayCheck = Date.now() + 5000;
      }

      const value = verify
        ? await refreshPayment({
            paymentId: pid
          })
        : await paymentStatus({
            paymentId: pid
          });

      if (
        !this.detached &&
        this.generation === version &&
        this.paymentId === pid
      ) {
        this.applyPayment(value);
      }
    } catch {
      if (this.generation === version) {
        this.error =
          "Verification is temporarily unavailable. This has not marked your payment failed.";
      }
    } finally {
      if (this.generation === version) {
        this.schedule();
      }
    }
  }

  refresh() {
    return this.check(false);
  }

  cancel() {
    return this.check(true);
  }

  async check(cancel) {
    if (this.busy || !this.paymentId) {
      return;
    }

    this.busy = true;
    this.error = "";
    this.openWhenReady = false;

    try {
      this.applyPayment(
        cancel
          ? await cancelPayment({
              paymentId: this.paymentId
            })
          : await refreshPayment({
              paymentId: this.paymentId
            })
      );

      if (
        !this.paid &&
        !this.closed &&
        !(
          this.failedTransaction &&
          this.payment?.state === "Ready" &&
          !this.gatewayExpiryReached
        ) &&
        !this.monitoring
      ) {
        this.beginMonitoring(
          this.gatewayExpiryReached ? Date.now() + 30000 : undefined
        );
      }
    } catch (error) {
      this.error =
        error.body?.message ||
        "Payment verification is unavailable. Please try again.";
    } finally {
      this.busy = false;
    }
  }
}
