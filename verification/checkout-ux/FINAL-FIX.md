# Checkout runtime correction — local changes only

No deployment, Experience Cloud publication, org-setting change, payment transaction, or data repair was performed.

The previous read-only audit confirmed an older checkout client in the open browser tab calling the newer Apex contract. Its popup opened before initialization was accepted, and its catch block immediately closed the host on rejection. The current sources also closed the host on `payment.failed`/host errors and started the handshake watchdog before gateway initialization finished. These changes address those narrow lifecycle issues. They cannot replace the older assets in the live site without a later approved rollout and fresh asset load.

## Changes

Paths below are relative to `force-app/main/default`.

| File | Change |
| --- | --- |
| `lwc/goldvueeRazorpayCheckout/goldvueeRazorpayCheckout.js` | Recheck server retry eligibility before initialization/reuse. Preserve the host on setup rejection or host error so the failure remains visible. Keep the Razorpay SDK modal alive on failed attempts. Prevent a second active payment window. Stop the handshake timeout when READY arrives rather than waiting for the gateway order. A missing handshake stops local work without declaring failure or releasing stock. Close the host after server-confirmed success or actual modal dismissal. |
| `pages/GVRazorpayHost.page` | Prevent dismissal from interrupting an already-returned success response. Keep the existing SDK retry/dismiss lifecycle intact after a failed attempt. Origin, source and nonce checks and payment payloads are unchanged. |
| `lwc/gvCheckout/gvCheckout.js` | Use Experience Cloud navigation to My Orders after verified success, and Shopping Bag after successful cancellation. Deduplicate navigation. Keep uncertain cancellation on checkout. |
| `lwc/gvMyOrders/gvMyOrders.js` | Display pending/unknown payments as Processing, Paid as Confirmed, and server-recorded Failed as Failed. Preserve cancellation, refund and fulfillment status distinctions. |
| `classes/GVOrderHistoryController.cls` | Remove client caching from the two existing imperative history reads so refresh/navigation obtains current server state. No ownership or query filters changed. |
| `classes/GVOnlineCheckoutController.cls` | On existing safely-unpaid cancellation only, mark the order payment status Failed consistently with the payment record. |
| `classes/GVGatewayWorker.cls` | Apply the same status consistency within the existing uninitialized/unpaid expiry branch. No initialized/uncertain release rule was relaxed. |
| `classes/GVAbandonedCheckoutService.cls` | Apply the same status consistency to existing safe abandoned-checkout recovery. |
| `classes/GVCheckoutJourneyTest.cls` | Add an assertion for the cancelled order's authoritative Failed payment status in history. Retain the earlier callout-context and reconciliation-throttle fixture fixes already present at the start of this task. |
| `lwc/goldvueeRazorpayCheckout/__tests__/goldvueeRazorpayCheckout.test.js` | Cover setup rejection, fresh preflight eligibility, delayed initialization, host errors and keeping the SDK modal alive after failure. Preserve existing verification, disconnect, duplicate-callback and recovery tests. |
| `lwc/goldvueeRazorpayCheckout/__tests__/hostLifecycle.test.js` (new) | Execute the real inline host script with a mocked Razorpay SDK. Verify amount/order/key wiring, wrong-nonce rejection, success-then-dismiss and failure-then-dismiss behavior. |
| `lwc/gvCheckout/__tests__/gvCheckout.test.js` | Assert verified-success navigation, safe-cancellation navigation and no navigation during uncertain cancellation. |
| `lwc/gvMyOrders/__tests__/gvMyOrders.test.js` | Replace the placeholder with order-list, refresh and detail status tests. |

`manifest/checkout-ux.xml` includes the affected history component, host page and supporting classes for a later validation/rollout. It was not deployed.

## Payment and inventory safety

Cart mutations and initial stock reservation are unchanged. The existing server still owns identity checks, reservation matching, payment eligibility, cancellation, signature verification, captured-payment verification and idempotent inventory commitment. No credentials, Named Credentials, gateway creation endpoints, currency conversion, webhook processing or inventory service logic changed.

An explicitly failed SDK attempt remains a pending order until server reconciliation establishes the outcome. A timeout or popup close never marks it Failed or releases stock.

The existing cancellation limitation remains: initialization must never have started before immediate cancellation is provably safe. An initialized gateway order remains potentially payable, so a transient unpaid lookup cannot safely authorize releasing its stock. Those orders remain held for verification/review rather than being forcibly cancelled. General cancellation of initialized orders still needs a verified gateway termination or separately approved late-capture/refund workflow. No unsafe shortcut was added.

## Checks executed

- **35 tests passed across 6 Jest suites:** Shopping Bag, checkout navigation, payment recovery/lifecycle, bounded polling, My Orders and Visualforce host script.
- **ESLint passed** for the three modified production LWC JavaScript files.
- **Prettier Apex parser/round-trip checks passed** for the five changed Apex classes, including the test class.
- **Git whitespace check passed**, using `cr-at-eol` for the Windows working tree.
- Existing cart editing, pending-checkout locks, duplicate callback guards and bounded polling tests still pass.
- The prior deployment's 79/79 Apex result was supplied by the user. **These local Apex changes have not been compiled or run in Salesforce.** No deployment or validation-only deployment was initiated for this task.
- Real browser/Razorpay acceptance testing of these changes remains for a later approved rollout; the local host tests mock the SDK and never take a payment.

Focused Jest command:

```powershell
node node_modules/@salesforce/sfdx-lwc-jest/bin/sfdx-lwc-jest -- --runInBand --runTestsByPath force-app/main/default/lwc/gvShoppingCart/__tests__/gvShoppingCart.test.js force-app/main/default/lwc/gvCheckout/__tests__/gvCheckout.test.js force-app/main/default/lwc/goldvueeRazorpayCheckout/__tests__/goldvueeRazorpayCheckout.test.js force-app/main/default/lwc/gvCheckoutRecovery/__tests__/gvCheckoutRecovery.test.js force-app/main/default/lwc/gvMyOrders/__tests__/gvMyOrders.test.js force-app/main/default/lwc/goldvueeRazorpayCheckout/__tests__/hostLifecycle.test.js
```

For later acceptance, verify a fresh published client first: it should display `Pay Securely · ₹…`, rather than the old status button. Then exercise prepare, safe cancel, resumed payment, SDK failure/retry, verified success to My Orders and delayed verification. Confirm one order/reservation set and one stock deduction, and ensure initialized/uncertain payments remain protected.
