# Initialized checkout reservation recovery (local only)

No deployment, org settings, credentials, or business records were changed.

## Behavior

Customer-requested reconciliation now uses the existing queueable worker's `recover` operation. Scheduled reconciliation remains read reconciliation and does not renew reservations automatically. All gateway GET requests finish before database writes.

Recovery checks the complete gateway payment-attempt collection and fetches the existing gateway order. It requires no captured/authorized/unresolved attempts, the same order identity, INR, the expected amount, zero paid, the full amount due, and a created/attempted order state. Gateway creation is unchanged.

Under the existing customer lock, recovery validates cart/customer/order/payment linkage, pending statuses, payment amount and gateway identity, no recorded capture, and exactly one non-cancelled order for the cart. It preserves live reservations. Otherwise it rejects committed or inconsistent live holds, releases only expired active holds after verified unpaid eligibility, and uses the existing inventory service to reserve order quantities in new records. Failure rolls back the reservation mutation. Expired/released records are never reactivated. The same Order, Payment and Razorpay order IDs remain in use. Serialized duplicate requests reuse the live hold without extending it.

Snapshots expose `RecoveryRequired` and `StockUnavailable`. Genuine unresolved gateway outcomes remain protected for review and can be explicitly checked again. Opening a restored expired checkout does not start background recovery. An explicit customer action requests recovery, waits only for that request, and opens payment with the existing gateway identity after server eligibility succeeds. Cancellation is shown only when allowed by the server and never triggers reconciliation polling when prohibited. Confirmed payments navigate to My Orders.

## Files changed for this request

- `force-app/main/default/classes/GVCheckoutEngine.cls`: locked, atomic unpaid hold renewal.
- `force-app/main/default/classes/GVGatewayWorker.cls`: verified recovery operation and explicit unavailable-stock result.
- `force-app/main/default/classes/GVOnlineCheckoutController.cls`: actionable recovery snapshots and customer recovery job routing.
- `force-app/main/default/classes/GVRazorpayService.cls`: additive read-only order eligibility GET; existing create/signature behavior unchanged.
- `force-app/main/default/classes/GVCheckoutJourneyTest.cls`: eight new Apex tests.
- `force-app/main/default/lwc/gvCheckoutRecovery/gvCheckoutRecovery.js`: terminal actionable states, customer messaging, no prohibited-cancel polling.
- `force-app/main/default/lwc/gvShoppingCart/gvShoppingCart.js`: recovery action label, cancellation eligibility, confirmed navigation.
- `force-app/main/default/lwc/gvShoppingCart/gvShoppingCart.html`: conditional cancellation and recovery wording.
- `force-app/main/default/lwc/goldvueeRazorpayCheckout/goldvueeRazorpayCheckout.js`: explicit recovery, safe popup reuse, no automatic expired-state polling.
- `force-app/main/default/lwc/goldvueeRazorpayCheckout/goldvueeRazorpayCheckout.html`: conditional cancellation.
- `force-app/main/default/lwc/gvCheckoutRecovery/__tests__/gvCheckoutRecovery.test.js`
- `force-app/main/default/lwc/gvShoppingCart/__tests__/gvShoppingCart.test.js`
- `force-app/main/default/lwc/goldvueeRazorpayCheckout/__tests__/goldvueeRazorpayCheckout.test.js`
- This report and `initialized-recovery-tests.json`.

Earlier uncommitted changes in the workspace were preserved.

## Checks

- Full Jest run: 56 tests passed; 9 suites passed. Five unrelated suites could not load `@salesforce/community/basePath`: goldvueeHeader, goldvueeHero, goldvueeFooter, goldvueeCategoryCarousel, gvMyAccount. Full Jest exit code is 1 because of these load failures; it is not a fully green repository run.
- All checkout/recovery tests passed, including seven new Jest cases covering terminal responses, hidden cancellation, confirmed navigation, explicit recovery, double-click protection, unchanged gateway payload, and no further stock-unavailable polling.
- ESLint passed for all six changed production/test JS files.
- Apex parser/round-trip checks passed for all five changed Apex classes. This is not Salesforce compilation or execution.
- Eight new Apex tests cover replacement of a released hold, replacement of an expired still-active hold, unavailable stock, authorization retaining held inventory, captured/authorized/uncertain/paid outcomes, duplicate queued contenders, one active reservation, unchanged inventory stock, preserved historical holds and all order/payment identities.
- Apex runtime tests were not run: modified Apex cannot be tested in Salesforce without first deploying it. No deployment or validation deployment was performed. The last 83-test validation predates this patch.

## Remaining limitations

True simultaneous transaction contention requires org testing; Apex tests exercise two queued contenders and request throttling rather than promising simultaneous execution. Local browser tests use a mocked Razorpay host. Gateway status can change after any read; reuse of the same gateway order and existing server-side capture/webhook verification preserve payment identity and handle later results.

An initialized payable gateway order is still not offered unsafe cancellation. Unavailable stock and unresolved payments expose an explicit action/support state; they do not unlock the cart by discarding the payment risk. Credentials, Named Credentials, webhooks, signatures, inventory commit logic, and existing successful orders are unchanged.
