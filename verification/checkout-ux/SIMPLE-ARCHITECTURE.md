# Simple cart and checkout architecture — local implementation

Prepared 13 November 2026. This report describes the latest local changes and supersedes the earlier flow description in FINAL-FIX.md. Earlier local fixes were preserved. No Salesforce deployment, validation-only deployment, org-setting change, credential change, payment transaction or customer-data update was performed.

## Old flow and new flow

| Area | Previous local behavior | Updated behavior |
| --- | --- | --- |
| Add to Cart | Existing cart controller validates prices, customer ownership and available stock; no order or reservation is created. Product Details reads physical stock. | Existing server behavior is preserved. Product Details reads available stock, and the product-detail query includes that formula field. |
| Proceed to Checkout | Shopping Bag navigates; an order/reservation is prepared later, after delivery entry. | Shopping Bag calls `GVOnlineCheckoutController.beginCheckout()` before navigation. The existing engine creates/reuses one pending draft, payment and reservation set. |
| Delivery information | Required when creating the pending order. | Editable on the pending draft. Existing `prepareOnlineOrder()` validates and saves it on the same order, preserving payment ID, amount, lines and reservations. Fields freeze after delivery is saved. |
| Pay | Existing secure initiation, popup, signature and capture verification. | Same flow, with an added server prerequisite that delivery must be complete before initialization. A draft's Continue button saves delivery first; Pay Securely then opens the payment window. |
| Back / Cancel | Similar cancellation/reconciliation logic repeated across components. | All callers use the same `cancelCheckout()` helper and the existing ownership-checked, locked Apex cancellation boundary. Uncertain outcomes reconcile before cancellation is attempted. |
| Messages | Some server errors and recovery terminology reach the UI. | Checkout states and errors map to simple customer messages. Internal reconciliation states remain internal. |
| My Orders | Prior local fixes provide fresh reads and accurate status labels. | Retained: pending/unresolved is Processing, verified paid is Confirmed, and safely cancelled/failed records retain accurate terminal statuses. |

## New or extended implementation files for this request

Paths are relative to `force-app/main/default` unless stated otherwise.

| File | Purpose |
| --- | --- |
| `classes/GVCheckoutEngine.cls` | Add an idempotent bag-entry draft path inside the existing engine; extract the existing delivery validation for reuse; save draft delivery without creating another order/payment/reservation; return canonical cart, delivery and original order details. |
| `classes/GVOnlineCheckoutController.cls` | Expose `beginCheckout()` using the existing transaction rollback pattern. |
| `classes/GVPaymentController.cls` | Add one `requireDelivery()` prerequisite after identity/ownership locking. Existing gateway initialization, amount conversion, currency and eligibility security remain intact. |
| `classes/GVProductController.cls` | Add `Available_Quantity__c` to the existing product-detail query. Preserve USER_MODE and existing query filters. |
| `lwc/gvShoppingCart/gvShoppingCart.js` | Prepare before navigation, prevent duplicate Proceed clicks, reuse pending checkout, and use the shared cancellation/message helpers. |
| `lwc/gvCheckout/gvCheckout.js` | Use the same helper for the Back fallback, retain safe navigation, show the delivery step for unfinished drafts and sanitize customer errors. |
| `lwc/goldvueeRazorpayCheckout/goldvueeRazorpayCheckout.js` | Save delivery on an existing draft before payment; retain the verified popup lifecycle corrections; keep draft fields editable until save; restore fields after failed save; simplify labels and messages. |
| `lwc/gvCheckoutRecovery/gvCheckoutRecovery.js` | Centralize Back/Cancel/bag cancellation, bounded reconciliation and customer-facing state/error messages. |
| `lwc/gvProductDetails/gvProductDetails.js` | Use available stock for purchase controls and customer-friendly errors. |
| `classes/GVCheckoutJourneyTest.cls` | Add draft/idempotency, address-before-payment, no-reservation-on-add, same-reservation delivery save, cancel/release/fresh-checkout, invalid delivery and stale-stock regression cases. Earlier fixture corrections remain intact. |
| Shopping Bag, checkout, payment, recovery and Product Details `__tests__/*.test.js` | Test preparation before navigation, duplicate clicks, draft delivery, shared cancellation, uncertainty, failed-save recovery, server verification, stock controls and safe error messages. |
| Repository `manifest/checkout-ux.xml` | Include the affected Product Details component/controller in the existing scoped package for later validation. No deployment was run. |

The existing uncommitted My Orders, safe-cancellation/expiry status-consistency and Visualforce host lifecycle fixes were retained. `GVCartController`, `GVInventoryService` and `GVCheckoutOperations` were reviewed and did not require new changes.

## Cart locks and inventory

Adding/removing/updating products continues through `GVCartController`. Customer locking serializes cart changes and prevents duplicate product lines. Stock and price checks remain server-side. Adding a product does not create an order/payment or reserve stock.

Proceed creates a pending order only if no non-cancelled checkout exists. It reserves through the existing inventory service. For stock 10 and quantity 1, physical stock stays 10 while reserved becomes 1. Repeated preparation or restoration reuses the order and payment without reserving again. Saving delivery also reuses those records.

The cart remains locked while a non-cancelled checkout protects inventory/payment state. Safe cancellation releases the original reservations exactly once, marks the order Cancelled and its payment Failed, and removes that order from the cart mutation guard. Physical stock is not restored because it was not deducted. A fresh checkout can then reserve the edited quantities. Successful verified capture uses the existing idempotent commit path to deduct physical and reserved stock once.

Refresh, component disconnect and tab close do not request cancellation. Independently scheduled expiry/reconciliation retains its existing security rules.

## Shared cancellation and protected uncertainty

Back to Shopping Bag, Cancel Unpaid Checkout and bag recovery call the same helper:

1. Fetch the authenticated customer's current checkout status.
2. Return an already-confirmed outcome to My Orders, or an already-cancelled outcome to the bag.
3. If safe cancellation is not established, request existing server reconciliation and poll sequentially with bounded delays.
4. Call the existing Apex cancellation boundary only when cancellation is eligible. Apex rechecks ownership, state and locks, then releases inventory transactionally.
5. On uncertainty, keep the order and inventory protected and show a simple Checking payment securely message. Do not create another order/charge or mark the payment Failed.

**Existing gateway limitation remains:** an initialized Razorpay order can remain payable even if a current lookup finds no captured payment. The existing integration has no verified operation to terminate that acceptance. Therefore immediate self-service cancellation is supported for provably uninitialized/unpaid drafts; initialized, authorized, captured or ambiguous cases remain protected for reconciliation/review. This implementation does not misrepresent a transient unpaid lookup as a permanent cancellation. General initialized-order cancellation still needs a verified gateway termination or an explicitly approved late-capture/refund workflow.

## Preserved gateway and security

`GVRazorpayService`, the inventory service, signature services, verification controller/service, webhook receiver/handler, admin operations and cart controller remain unchanged from the checkpoint. No additional changes were made to the Visualforce host in this request; the previously verified lifecycle fix remains in the working tree. Named Credentials, keys, endpoints, currency, paise conversion, capture and signature checks were not changed.

The only new initiation security condition rejects a draft without valid delivery information before any gateway initialization job can be queued. Existing browser messages still require the expected origin, source and nonce. Success still requires secure server verification and inventory commitment; a client success message alone does not change order/payment records.

## Checks and results

- **47 Jest tests passed, 0 failed, across 7 suites.** Machine-readable evidence: `simple-architecture-tests.json`.
- ESLint passed for all six reviewed production LWC JavaScript files.
- Local Apex parser/round-trip checks passed for the modified engine, checkout controller, payment controller, product controller and journey tests.
- Git whitespace check passed using `cr-at-eol` for the Windows working tree.
- Protected-service comparison confirmed unchanged gateway, signature/webhook, inventory, cart-security and operations implementations.
- The new Apex regression cases were authored but have **not** run in Salesforce. Local parsing does not establish Salesforce compilation, runtime results or coverage. The user's previous 79/79 result predates these changes.
- Tests mock all Apex calls and the Razorpay SDK; no gateway transaction was placed. Real browser acceptance testing remains for a separately approved rollout.

## Remaining rollout checks

Run Salesforce validation separately, including customer ownership, draft creation, cancellation/repeated cancellation, stale stock, capture/duplicate callback and uncertain-payment cases. Verify customer field access to available quantity and ensure the published Experience Cloud site loads the current component assets. Older cached/published clients will not invoke the new bag preparation path until the separate rollout refreshes those assets.

Keep historical orders and payments intact. Do not convert existing Processing records to Failed in bulk, force a captured/uncertain order to Cancelled, or release initialized gateway holds to bypass a cart lock.
