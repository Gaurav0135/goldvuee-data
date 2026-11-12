# GoldVuee checkout and inventory audit

Date: 12 November 2026. Scope: current local working tree in `D:\GoldVuee\goldvuee`, with `force-app` as the sole package directory. No application source was changed, no deployment was run, and no org data was modified during this audit.

## Assessment

The current source is not ready for checkout acceptance or a reproducible deployment. Useful security controls exist, but missing metadata, incomplete payment recovery, concurrency gaps, and insufficient tests prevent certification of the requested guarantees. These are local-source conclusions; the deployed org may contain dependencies absent here.

| Requirement | Local evidence | Assessment |
| --- | --- | --- |
| No COD | Legacy `placeOrder` always rejects COD; checkout UI offers Razorpay | Implemented in these entry points. Payment picklist still permits COD and no metadata rule prohibits new COD records through other writers. Preserve historical records and add an insert/transition policy. |
| Server-side verification | Event subscriber verifies HMAC using stored gateway order ID; finalizer fetches captured payment and checks order, amount, INR, ownership and proof | Good foundation; secret configuration and permissions are absent, event processing is not bulk safe, and recovery depends on the browser. |
| No overselling | Product row locks, available-stock checks, atomic reservation counters, commit/release guards | Protected on examined service paths, but global invariant enforcement and concurrent integration evidence are missing. |
| No duplicate checkout/payment | Cart lock and pending-order reuse; finalizer locks and repeats same-payment success safely | Incomplete: cart creation races, gateway initialization uncertainty, nonunique gateway IDs and unrestricted cart mutation remain. |
| Experience Cloud checkout | Community page targets, Contact-based identity, VF popup bridge with source/origin/nonce checks | Org-bound host URL, broad host allowlist, missing site/security metadata and incomplete interruption handling. |
| Tests and deployment verification | Six Apex test classes, twelve Jest files, partial patch deployment script | No current runtime pass or coverage verified; eleven Jest files are placeholders. Clean deployment has unresolved dependencies. |

## Inventory and dependency map

- 21 Apex classes: 15 implementation classes and six test classes; one platform-event trigger.
- 12 LWC bundles: `goldvueeHeader`, `goldvueeFooter`, `goldvueeHero`, `goldvueeCategoryCarousel`, `gvProductCatalog`, `gvProductDetails`, `gvNewArrivals`, `gvShoppingCart`, `gvCheckout`, `goldvueeRazorpayCheckout`, `gvMyAccount`, `gvMyOrders`.
- Five object definitions: `Jewellery_Product__c`, `Shopping_Cart__c`, `Jewellery_Order__c`, `Payment__c`, `GoldVuee_Payment_Verification__e`.
- Two Visualforce pages: `GVRazorpayHost` and `GVRazorpayPopupDemo`; one bundled Razorpay static resource. Active host loads the remote official checkout script rather than this static resource.
- 105 XML files parsed successfully. XML syntax is not Salesforce schema, formula, Apex compiler, or deployment validation.
- Project source API version is 68.0; the payment child LWC uses 66.0. This difference is not itself a defect; target-org compatibility still needs validation.
- No project `AGENTS.md` was found by the repository scan.
- Working tree already contains substantial modified and untracked code, patches, ZIPs, recovery scripts and backups. Preserve these until an approved cleanup. Audit findings refer to current working files, not historical snapshots.

Active flow:

`gvProductCatalog/gvProductDetails -> GVProductController -> GVCartController -> gvShoppingCart -> gvCheckout -> goldvueeRazorpayCheckout -> GVOnlineCheckoutController.prepareOnlineOrder -> GVInventoryService.reserveStock -> GVPaymentController.initiatePayment -> GVRazorpayService.createOrder -> GVRazorpayHost -> requestSignatureVerification -> platform event -> GVPaymentVerificationEventHandler -> signatureVerificationState -> GVPaymentVerificationService.verify -> fetchPayment -> inventory commit + payment success + order confirmation + cart conversion`

`gvMyOrders -> GVOrderHistoryController` provides customer-scoped history but no payment reconciliation action. `gvMyAccount -> GVMyAccountController` returns only current-user account information. `gvNewArrivals -> GVNewArrivalsController` uses available quantity. Header, footer, hero and category carousel supply navigation/presentation dependencies.

Missing source required by existing code or metadata:

| Dependency | Evidence / effect |
| --- | --- |
| `Cart_Item__c` | Used by cart/checkout and Shopping Cart total rollup, but no object/fields/validation metadata supplied. |
| `Jewellery_Order_Item__c` | Used by checkout, payment verification and order details; missing definition and fields. |
| `Stock_Reservation__c` | Inventory and verification require fields, picklists and relationships not in source. |
| `Inventory_Movement__c` | Required by stock commitment; missing object, relationship and movement fields. |
| `Jewellery_Category__c` | Product lookup, product queries and tests depend on it; missing definition. |
| `GV_Payment_Config__c.Razorpay_Test_Secret__c` | Subscriber queries named configuration `RazorpayTest`; neither object/field nor secure provisioning procedure is supplied. Encryption/access behavior cannot be confirmed locally. |
| Named/External Credential `GV_Razorpay_Test` | Required by all gateway callouts; metadata, principal access and provisioning instructions are missing. Never commit the credential secret. |
| Experience site and authorization | No site/experience bundle, sharing sets/rules, customer profiles, permission sets, VF access, credential principal permissions or trusted-site configuration supplied. Permissionsets directory is empty. |
| Customer test profile | Finalization test requires a customer profile whose name contains `GoldVuee`; not included in source. |

## Prioritized findings

### F01 — Blocker: deployment cannot be reproduced from this repository

The missing dependencies above prevent compiling/deploying into a clean org. `manifest/package.xml` contains only a version, so it selects no components. The patch deployment script selects five paths and omits much of the changed checkout/payment implementation and its dependencies. Scratch definition does not provision the Experience Cloud setup needed by this flow. A successful partial patch would not demonstrate complete checkout deployment.

Remedy: retrieve and review required metadata from an explicitly selected development/test org, supply least-privilege access metadata, create a complete release manifest and separate validation from deployment. Do not infer absent definitions or overwrite existing org configuration without comparison.

### F02 — High: gateway order creation is not serialized across the callout

`GVPaymentController.initiatePayment` locks Payment, calls Razorpay, then locks Payment again. Salesforce releases `FOR UPDATE` locks during callouts. Two requests can therefore both reach `createOrder`; the later recheck can discard one external order reference, but cannot undo external creation. A timeout or failed Salesforce update also leaves an uncertain external result with no durable attempt/recovery state. Passing Payment ID as receipt is useful correlation but is not sufficient evidence of end-to-end idempotency.

The second lock rechecks amount and order status but does not recheck the stock reservations after the callout. Initial reservation query is also sharing-dependent, unlike other privileged reservation reads.

Remedy: persist a uniquely keyed initialization attempt in a separate committed transaction, let one worker own it, track ambiguous outcomes, and reconcile before retrying external creation. Confirm gateway duplicate-receipt behavior against current API contract; do not assume it. Refresh reservation eligibility before offering payment. Tests must cover concurrent calls, timeout after external success and local persistence failure.

### F03 — High: captured payments can remain permanently unconfirmed

HMAC verification only stores a verified payment ID. Finalization runs from the browser after polling up to about 30 seconds. Closing the tab, lost popup messages, slow event processing or an expired hold can leave a captured payment pending in Salesforce. Finalizer correctly refuses expired reservations, but no webhook endpoint, reconciliation worker, durable exception queue or refund workflow exists in active source. Abandoned-checkout recovery intentionally refuses any order with a gateway reference, leaving initialized abandoned orders and their reserved counters unresolved.

Remedy: authenticated, signed webhook intake with deduplication and replay protection; durable reconciliation using authoritative gateway state; explicit late-payment policy and operator queue. Webhooks and browser callbacks must converge on one idempotent finalization service. Never release uncertain paid inventory or ask a customer to pay again merely because a callback timed out.

### F04 — High: cart creation/mutation does not share the checkout lock protocol

`GVCartController.getOrCreateCart` uses query-then-insert without serialization or a unique active-cart key. Concurrent first additions can create two Active carts, which later checkout refuses. Existing cart-item read/increment/write is also unlocked. Add, update and remove do not lock the cart or reject an initialized pending checkout. They can race preparation/finalization or change a bag after payment starts. Rollup parent locks may serialize some DML, but do not replace the missing state check and consistent lock protocol.

Remedy: unique active-cart identity, serialized item mutation, unique cart/product key and immutable/versioned checkout snapshot. Every mutation and finalization must follow the same parent/state lock protocol; direct customer DML permissions must not bypass it.

### F05 — High: database invariants are incomplete

Payment transaction ID, gateway order ID and signature-verified payment ID are nonunique Text fields. Duplicate transaction prevention is a query rather than a database uniqueness constraint. There are no explicit checkout/attempt/reservation idempotency keys. Product validation covers code and price but not `0 <= reserved <= stock`, nonnegative physical stock or whole-unit inventory. Missing child-object metadata prevents assessing their guards.

`GVInventoryService.reserveStock` returns an existing active reservation without comparing its reserved quantity to the requested quantity, and permits a null order ID. This can silently accept an inconsistent internal request. Current callers usually supply an order and do additional checks, which reduces but does not eliminate the contract defect.

Remedy: database keys and validation rules, restricted inventory/payment writers, reservation quantity/order checks and an auditable adjustment service. Scan existing data for conflicts before enabling unique constraints; any cleanup requires separate approval.

### F06 — High: inventory operations and event handling do not scale safely

Inventory services issue queries, DML and savepoints per reservation. Checkout, reconciliation and finalization invoke them in loops without a cart-size bound. Event handler queries a lock and updates a payment for each valid event; a sufficiently large valid event batch can exceed transaction limits. Catching `Exception` per event does not make governor-limit exhaustion recoverable.

Lock order also differs: prepare starts at cart then order/reservations/products; verify starts at payment then order/reservations/products and finally cart; reserve locks product before an existing reservation while release/commit lock reservation before product. These paths can deadlock or time out under contention. Sorting a later processing loop does not establish a common cross-service lock protocol.

Remedy: bulk query/update APIs, a documented common lock hierarchy, bounded cart size and gateway initialization transactions isolated from database finalization. Test realistic multi-product baskets and valid event batches, plus concurrent API/browser sessions.

### F07 — High: security deployment cannot be verified

Customer identity and explicit Contact ownership checks are strong existing controls. However, system-mode/without-sharing services rely on metadata permissions that are not included. The signature-proof field, payment success fields, order amounts and stock counters must not be customer-writable. Customer event publishing and direct payment/object access must be tightly scoped. Event subscriber needs tested access to the decrypted secret; comments describing encryption are not evidence of correct field type or masking/decryption permissions.

Product catalogue/detail queries use USER_MODE but select physical stock; product detail displays physical stock rather than stock minus reservations. This can force granting internal-stock FLS or break the entire query for customers without it. Align product DTOs and FLS with the intended public availability policy.

Remedy: version least-privilege permissions and sharing, explicitly protect gateway proof/state fields, test with two unrelated customer users and a guest, and verify configuration access as Automated Process. Never solve checkout access errors by giving customers inventory edit privileges.

### F08 — High: popup and retry behavior is not portable or interruption-safe

Payment LWC hardcodes a development-org Visualforce hostname. Host allows any HTTPS `*.my.site.com` origin, while rejecting custom Experience domains. Source/window/nonce checks are good, but configuration should allow only the actual site's approved origins. Custom domains, sandbox refreshes, login redirects, popup blockers and mobile browsers need explicit verification.

No popup-close watcher or READY timeout exists; manually closing before a terminal message can leave `isWorking` true indefinitely. Cached pending/gateway orders survive retry without revalidating changed shipping, cart state or reservation lifetime. After a verification failure the component re-enables Pay, retains no durable browser-independent verification recovery, and can reopen checkout rather than resuming confirmation of the known payment ID. Parent `isPlacingOrder` is never set true by the child, so shipping fields remain mutable during payment preparation.

Remedy: configurable host/origin data, payment state propagated to parent, locked shipping snapshot, bounded handshake/close handling, and distinct resume-confirmation versus new-payment behavior. Payment/order status must come from the server after reload.

### F09 — Medium: contradictory pending-order and pricing behavior

Prepare rejects changed shipping early, making its later `addressChanged` update branch unreachable. Comments promise delivery updates that cannot occur. Renewal and abandoned recovery overlap. Taxes, shipping and discounts at order level are all set to zero; this is an implemented pricing policy, not a complete tax/shipping design. The checkout summary uses cart-stored prices while preparation recalculates current prices, so a stale cart can display a different amount from the payable server total.

Remedy: one explicit quote/snapshot and repricing policy, clear address-edit lifecycle and business-approved tax/shipping rules. Present the authoritative total before opening payment.

### F10 — Medium: COD restriction is narrower than the requirement

The current legacy Apex method rejects COD and the active UI has no COD option. `Payment_Method__c` still includes COD; payment validation only checks amount and successful transaction presence. Other privileged writers can still create COD records. Stale inventory comments mention approved COD.

Remedy: prohibit new COD payments and transitions into COD at the server/metadata boundary while preserving historical records. No deletion of historical orders or picklist values is required to enforce the policy.

### F11 — High: current tests do not establish acceptance

- `GVCheckoutControllerTest`: COD rejection only; does not test online preparation.
- `GVInventoryServiceTest`: useful reserve/commit/release/expiry and duplicate-operation assertions, but no real concurrent-session proof, bulk basket or external-writer invariant tests.
- `GVRazorpaySignatureServiceTest`: positive/negative helper HMAC tests; subscriber duplicates cryptographic implementation rather than calling the helper.
- `GVPaymentVerificationControllerTest`: mostly gateway service mocks/input validation, despite controller-oriented name. Does not establish the complete customer controller/event flow.
- `GVPaymentVerificationEventHandlerTest`: predominantly malformed/empty input and unconditional assertions; no valid-signature persistence, secret access or valid-event-batch acceptance coverage.
- `GVPaymentFinalizationTest`: useful captured-payment and repeat-finalization assertions, but depends on an org-specific GoldVuee customer profile. It manually seeds signature proof, so it does not prove end-to-end HMAC/event processing.
- Eleven of twelve LWC test files have generated TODO tests with `expect(1).toBe(1)`. Header tests contain actual UI assertions. Checkout, payment bridge, retry, timeout, origin rejection and order confirmation therefore lack meaningful Jest coverage.
- No dedicated online preparation, cart, abandoned-checkout, order history, account or catalogue test class exists. They may receive indirect coverage; actual percentages are unknown.

## Verification performed and limits

- Read current Apex, checkout LWCs, related component dependencies, object metadata, test sources, manifests, scratch definition, deployment helper and local patch structure.
- Parsed all 105 source XML files: zero malformed XML files.
- Confirmed Salesforce CLI version `2.154.4` with bundled Node `v24.21.0`. Initial CLI invocation failed because its diagnostic log was outside the workspace; approved elevated version check succeeded.
- Standalone `node`/`npm` were not on this shell's PATH; no project `node_modules` or package lockfile exists. Jest/lint were not run. Bundled CLI Node does not establish an installed project test toolchain.
- Apex compilation/tests, code coverage, clean-org deployment and Experience Cloud browser checkout were not run. No target org was selected or audited. Existing local logs are historical evidence, not proof about current source. In particular `checkout-error.txt` describes a much older legacy method with hundreds of lines; the current method is a short COD rejection.
- No secrets or authentication tokens were requested or printed. Backup/patch source was inventoried as historical material, not certified as a second deployment target.

Platform behavior checked against official documentation: Salesforce [locking statements](https://developer.salesforce.com/docs/platform/apex-dev/references/apex-dev/langcon-apex-locking-statements.html) explains callout lock release. Razorpay [Standard Checkout best practices](https://tfs.np.razorpay.in/docs/payments/payment-gateway/web-integration/standard/best-practices) requires signature validation and payment/order status checking before fulfillment.

## Proposed rebuild for approval

1. Establish a reproducible source baseline: retrieve missing dependencies from a selected development/test org into a review area; compare definitions, automation, access and data constraints. Preserve current edits and backups. Confirm authenticated-customer checkout as the initial scope, INR/India delivery and the late-capture policy.
2. Implement a single checkout lifecycle: uniquely keyed cart/snapshot and payment attempt; trusted server quote; explicit pending, initializing, awaiting-payment, verifying, paid, expired, failed and reconciliation states. Keep financial state distinct from fulfillment state. Reject COD server-side.
3. Replace per-record inventory loops with bulk reserve/commit/release operations, validation invariants, a common lock protocol and scheduled expiry/reconciliation. One payment can commit one reservation set once; late captures must follow a defined stock/refund/manual-review policy.
4. Build Razorpay Test Mode initialization and verification around durable attempts, protected credentials, HMAC validation, authoritative capture/amount/order checks and signed deduplicated webhooks. Recover ambiguous callouts before retry. Do not promise exactly-once external effects from a Salesforce transaction alone.
5. Rebuild Experience checkout around server state, authoritative totals, frozen shipping/payment snapshot, configurable popup host, strict approved origins, confirmation recovery, reload safety and useful customer error states.
6. Add meaningful Apex and Jest tests and a reproducible deployment/verification runbook. Validate the whole release in the selected nonproduction org before any deployment approval for production.

Acceptance evidence required:

- Apex positive/negative paths for ownership, guest rejection, tampering, absent/invalid proof, captured/authorized/failed payment, wrong amount/currency/order, duplicate callbacks, webhook replay, expired hold, local rollback, external timeout and bulk events/baskets.
- Two-session integration tests competing for the last unit and racing cart creation, initialization and finalization. Assert nonnegative stock, reserved not exceeding physical stock, one confirmed order/payment and one movement per committed reservation.
- Jest tests for shipping/quote, disabled payment state, popup errors and closure, untrusted messages, double clicks, verification delays/failures, reload/resume and confirmed order display.
- Full-source dry-run, required Apex deployment coverage with passing tests, least-privilege customer/guest checks, real Razorpay Test Mode success/failure/late-callback runs on the published Experience site, and postdeployment metadata/status checks.
- Before enabling uniqueness, scan existing duplicates; remediation and any data deletion/production mutation require an explained, separate approval.

Approval requested for the proposed local rebuild and non-destructive source additions/edits after the development/test metadata baseline is selected. No file deletion, destructive metadata operation, production deployment or production data modification is included in that approval.
