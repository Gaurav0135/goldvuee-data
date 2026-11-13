# GoldVuee checkout UX change — local implementation, awaiting Apex validation

Prepared 13 November 2026 for `goldvuee-dev`. No metadata was deployed, no customer data was reset, and no real or test payment was placed. Salesforce test callouts use mocks.

**Read this before reviewing the Git diff.** The repository was behind the org. The approved synchronization imported the deployed checkout architecture before implementation. The large Git diff includes that synchronization, including the existing Razorpay-only policy. It does not represent a new rewrite of payment processing. `baseline-inventory.json` distinguishes files synchronized from the org from subsequent implementation changes. The scoped manifest intentionally excludes unchanged baseline dependencies and all permissions/settings/schema changes.

**Checkpoint and rollback sources**

- Original Git revision: `c8b20f3` (full revision in `backups/checkout-ux-20261113/original-head.txt`).
- Original local source archive: `backups/checkout-ux-20261113/local-source.zip`.
- Deployed rollback baseline: `backups/checkout-ux-20261113/deployed/`.
- Backup directory is ignored by Git; keep it locally until review and rollout finish.
- Payment configuration retrieval contains field definitions only, not credential records or secret values.

**Implementation changes relative to the deployed baseline**

| File or bundle | Reason |
| --- | --- |
| `lwc/gvShoppingCart` | Detect pending checkout, show friendly recovery actions, lock editing before a technical rejection, show availability, refresh the same cart after cancellation, preserve quantity and removal actions. |
| `lwc/gvCheckout` | Visible safe Back to Bag action, journey text, frozen/restored delivery fields, original server order items/total, address autocomplete, keyboard focus styling, confirmation after refresh. |
| `lwc/goldvueeRazorpayCheckout` | Remove permanent Check Payment Status button; automatically reconcile on restore, popup failure, dismissal and closure; show clear preparation/payment/verification states and server-derived payable amount. Preserve popup origin/source/nonce validation and signature/capture confirmation. |
| `lwc/gvCheckoutRecovery` (new) | Shared bounded sequential reconciliation with increasing delays and cancellable waits. A session stores only a payment ID lookup reference; Apex authenticates and supplies every status/amount. |
| `classes/GVCartController.cls` | Add available quantity to the existing customer cart response. Preserve all ownership and mutation guards. |
| `classes/GVOnlineCheckoutController.cls` | Add ownership-checked recovery snapshot and fail-closed cancellation. Lock customer, cart, order and payment; reuse inventory release inside a rollback boundary. Completed cancellation is idempotent. Deduplicate in-flight reconciliation while allowing a fresh lookup after completion. |
| `classes/GVCheckoutEngine.cls` | Return original order lines on restoration; include the cart reference for safe confirmation restoration. Route the legacy expired-cancellation entry point through the same guarded cancellation boundary. |
| `classes/GVPaymentController.cls` | Require recent server reconciliation before reusing an existing gateway order. Recheck payment after acquiring the customer lock. Leave initial job creation, amount conversion and currency unchanged. |
| `classes/GVRazorpayService.cls` | Keep the existing endpoint. Reject incomplete collections, authorized/created/unknown attempts and mismatched order references instead of interpreting them as unpaid. Captured payments still use the original fetch/finalization path. |
| `classes/GVGatewayWorker.cls` | Publish a successful unpaid lookup for resume. Never release an ambiguous initialization or overwrite captured evidence with an unpaid result. Hold expired initialized gateway orders for review. |
| `classes/GVCheckoutJourneyTest.cls` | Add cancellation, ownership, retry, expired/authorized/unknown payment and inventory regression cases. Correct the inherited New Arrivals fixture by marking its test product as a new arrival. |
| Four LWC test suites | Replace three placeholders and test bounded polling, no overlaps, disconnect, restore, duplicate clicks/callbacks, failed verification, cancellation, order totals and refresh confirmation. |

All Apex paths above are under `force-app/main/default/classes`; LWC paths are under `force-app/main/default/lwc`.

**Cancellation prerequisite and deliberate limitation**

Immediate cancellation is supported only when gateway initialization has never started: no gateway order ID, initialization job, transaction ID or captured-payment evidence, and state New/blank. A lock prevents initialization from racing cancellation. The existing inventory service releases the exact reservations once; orders remain in history.

An initialized gateway order remains potentially payable. A lookup showing no captured payment does not revoke that order, nor establish that a delayed payment cannot arrive. Therefore initialized, authorized, captured and ambiguous outcomes cannot be cancelled as unpaid by this UI. Their stock remains held, including after expiry, until safe operational resolution. This can hold inventory longer than the old scheduler did; it is intentional. Customers receive a verification/review message and a My Orders link. Resume remains available after a successful, recent gateway reconciliation and a live matching reservation.

General self-service cancellation after gateway initialization needs an independently verified way to terminate further payment acceptance, or an explicitly approved late-capture/refund workflow. This change does not introduce a refund flow or pretend that closing the popup terminates payment acceptance.

Razorpay documents that the existing order-payments endpoint returns the order's payment attempts, including authorized/failed attempts, and that orders remain attempted until capture: [order payment lookup](https://raw.githubusercontent.com/razorpay/markdown-docs/master/api/orders/fetch-payments.md), [order states](https://github.com/razorpay/markdown-docs/blob/master/api/orders/fetch-all.md).

**Protected integration**

No credential values, Named Credentials, authentication settings, webhook endpoints, signature algorithms, capture logic, currency or INR-to-paise conversion were changed. The inventory service, payment-verification controller/service, signature service, verification-event handler, webhook receiver and event publisher are identical to the retrieved deployed baseline. The existing Visualforce host and its LWS string-envelope fix were synchronized, not redesigned.

**Validation evidence**

- Focused Jest: 23 tests passing in four suites (including refresh and duplicate-callback cases).
- ESLint: modified production LWC JavaScript passes.
- Prettier: modified implementation source parses and passes formatting checks.
- Existing deployed Apex baseline: 46 tests, 45 passing, one pre-existing failure in `GVCheckoutJourneyTest.browseAndOwnership` (missing New Arrival fixture flag). This is not a test of local changes. Evidence: `baseline-apex.json`.
- Validation-only metadata check: `0AfjV000006PLFVSA4`, `checkOnly=true`. Salesforce rejected Apex updates because the hourly reconciliation schedule has pending jobs and the deployment setting forbids changes to those dependencies. The missing LWC Apex-action message is consequential to the controller being rejected. Evidence: `validation-blocked.json`.
- New Apex tests have been authored but have NOT run against the changed code. No claim of Salesforce compile success, passing coverage, deploy readiness or live storefront verification is made.
- The validation attempt predates the final local refinements. Revalidate the final scoped manifest once the org restriction is resolved.

An administrator must approve a suitable validation environment or the deployment-with-pending-Apex-jobs setting. The schedule and org settings were not altered. Any actual deployment still requires separate explicit approval.

**Run checks locally**

```powershell
node node_modules/@salesforce/sfdx-lwc-jest/bin/sfdx-lwc-jest -- --runInBand --runTestsByPath force-app/main/default/lwc/gvShoppingCart/__tests__/gvShoppingCart.test.js force-app/main/default/lwc/gvCheckout/__tests__/gvCheckout.test.js force-app/main/default/lwc/goldvueeRazorpayCheckout/__tests__/goldvueeRazorpayCheckout.test.js force-app/main/default/lwc/gvCheckoutRecovery/__tests__/gvCheckoutRecovery.test.js
node node_modules/eslint/bin/eslint.js force-app/main/default/lwc/gvShoppingCart/gvShoppingCart.js force-app/main/default/lwc/gvCheckout/gvCheckout.js force-app/main/default/lwc/goldvueeRazorpayCheckout/goldvueeRazorpayCheckout.js force-app/main/default/lwc/gvCheckoutRecovery/gvCheckoutRecovery.js
```

After resolving the org restriction, validate without deploying:

```powershell
$env:SF_DISABLE_LOG_FILE='true'
sf project deploy start --dry-run --target-org goldvuee-dev --manifest manifest/checkout-ux.xml --test-level RunSpecifiedTests --tests GVCheckoutJourneyTest --tests GVInventoryServiceTest --tests GVPaymentFinalizationTest --tests GVPaymentVerificationControllerTest --tests GVRazorpaySignatureServiceTest --tests GVPaymentVerificationEventHandlerTest --tests GVWebhookTest --tests GVCheckoutRebuildTest --wait 10
```

Review results and per-class coverage. Do not quick-deploy the historical validation attempt. Do not deploy the whole synchronized tree as the UX change.

**Manual acceptance after separately approved deployment**

1. As a customer, add jewellery, edit quantity/remove, verify totals and availability. Inspect desktop, tablet and mobile spacing, keyboard focus, delivery labels and validation. Confirm the catalog behaves normally.
2. Enter delivery details and continue. Verify one pending Salesforce order, one payment and the expected active reservations. The final Pay Securely button must use that order total.
3. Before starting the gateway, cancel from checkout and from the bag. Verify reserved stock releases once, physical stock stays unchanged, the order stays Cancelled in history, and cart edits/fresh checkout work. Repeat the server cancellation request to verify no second release.
4. Refresh a pending checkout. Verify saved delivery/order lines/amount restore without creating or reserving anything again. Back, tab close and direct bag navigation must not automatically cancel.
5. In Razorpay Test Mode only, complete payment. Verify server-confirmed order/paid state, one inventory movement per committed reservation, one physical-stock deduction, and confirmation after refresh.
6. Close/fail the popup and check automatic verification. Retry may reuse the original gateway order only after server reconciliation and a live hold. Verify no duplicate Salesforce order or reservation.
7. Simulate delayed verification or a gateway outage with mocks/sandbox controls. Verify bounded progress followed by a recovery message, no automatic repayment, and no inventory release. Navigate away during polling and verify no further polls.
8. For initialized or authorized payments, click Cancel/Back to Bag. Verify uncertainty/review keeps stock held. Capture arriving during cancellation must confirm or enter review, never be treated as unpaid.
9. Replay callbacks/webhooks in the test environment. Verify inventory is committed once. Attempt another customer's payment ID as a different user: restore, cancellation and verification must be rejected.
10. For expired initialized holds, confirm the review path preserves stock and directs the customer to My Orders/support. Verify operator recovery through the existing operational workflow; do not force order statuses manually.

**Rollback**

Before deployment, preserve unrelated later work and restore only implementation files from `backups/checkout-ux-20261113/deployed/`. Remove the newly introduced `gvCheckoutRecovery` bundle only when none of the restored components reference it. To return to the original stale repository instead, use the local source ZIP in an isolated directory; do not deploy that stale snapshot to the org.

After an approved deployment, prepare a scoped rollback package from the retrieved deployed baseline for the seven Apex classes and three modified LWC bundles, plus the baseline journey test. Validate it with the same tests and scheduler constraints. Restore those callers before removing the new utility module. Do not delete, reset or restore customer/order/payment/inventory records. Configuration and credentials need no rollback because this task did not change them.
