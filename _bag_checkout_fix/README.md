# GoldVuee Bag + Checkout: expired pending order recovery (review patch)

Prepared from the user-uploaded Bag/Checkout ZIP on 12 Nov 2026. **Not yet compiled, tested, or deployed to Salesforce.**

## Why this is needed
- Order GV-ORD-0027 (₹232,000) is `pending`, payment is `Pending`, both gateway/transaction IDs null, cart `a03jV00000GXF77QAH`.
- Reservation `a0BjV000008k2ewUAA` is `Active` even though it expired on 11 Nov.
- `GVCheckoutController` refuses a second order for any previously used shopping cart; `GVOnlineCheckoutController` rejects a changed shipping address/cart.

## What this patch does
- Adds `GVAbandonedCheckoutService` (server-side only): handles **only expired, active reservations for pending orders with one Pending payment and NO gateway order ID/transaction ID**. It verifies customer ownership, locks rows, checks configured cancellation picklist values, releases inventory with `GVInventoryService.releaseReservation`, then marks payment and order cancelled/failed. If a gateway ID exists or any active hold is unexpired, it leaves the checkout alone.
- Updates `GVCheckoutController` and `GVOnlineCheckoutController` to call the recovery service after locking the customer's cart and to ignore historical cancelled orders in duplicate checks.
- **Does not modify** `GVCartController`, bag/checkout UI, Razorpay popup, paid orders, or `GVInventoryService`. COD's order-placement logic remains intact after the duplicate-check stage.

## Important limitations
1. **Picklists must support** Order_Status__c = `Cancelled`, `Canceled`, or `Abandoned`, AND Payment_Status__c = `Cancelled`, `Canceled`, or `Failed`. Otherwise the service intentionally blocks recovery. Check both picklists with Salesforce field describe before deploy.
2. It is a narrow recovery for **expired uninitialized payments only**, not a general reset of in-flight payments. Cart/address edits during a live hold will still be rejected; users can retry after expiry, or a separate authenticated cancel/reconcile endpoint can be added after gateway webhook reconciliation.
3. A missing gateway order ID is not a guarantee that a remote payment never occurred. This assumes the Razorpay order is created only through GVPaymentController and its ID is persisted before SDK exposure, as in current code. Test integration carefully.
4. A separate scheduled expiry/reconciliation process is needed for holds abandoned without a return visit. Do not invoke checkout repeatedly to release many orders.
5. The inventory release is rolled back if a later checkout action fails in the same transaction, because both checkout controllers use a Savepoint and rollback on exception. To repair historical records consistently even if a new checkout fails, run a dedicated recovery transaction as an admin AFTER picklist validation; see suggested next steps.

## Deploy preparation
First back up current source. Copy the two modified .cls files and new service .cls/.cls-meta.xml into `force-app/main/default/classes`.

```powershell
sf project deploy validate --source-dir force-app/main/default/classes/GVAbandonedCheckoutService.cls --source-dir force-app/main/default/classes/GVCheckoutController.cls --source-dir force-app/main/default/classes/GVOnlineCheckoutController.cls --target-org goldvuee-dev --test-level RunLocalTests
```

If validation succeeds, deploy same three source directories via `sf project deploy start`. After publishing, test expired cart retry on a throwaway test customer, and verify held/physical stock separately. Do not reset a payment with gateway IDs.

## Pending next work
- Build an explicit `Cancel pending checkout` action with a verified gateway reconciliation path for initialized payments.
- Lock carts consistently in GVCartController before add/update/remove and either reject mutations while a gateway order is live or reconcile the uninitialized order.
- Create Apex tests for COD, expired payment, mismatched shipping/cart, live reservations, and initialized gateway orders, plus test that failed recovery rolls back all stock changes.
