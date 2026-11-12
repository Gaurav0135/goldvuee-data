# GoldVuee Razorpay Checkout — Reviewed Code Patch (12 November 2026)

This patch is prepared from the 16 source files uploaded by the user. It is **not deployed or compiled in the user's Salesforce org**. Use the deployment checks below and validate in the dev org before trusting the flow.

## What the patch does

1. Keeps `gvCheckout.js`, `.html`, `.css`, COD, `GVRazorpayHost.page`, and `GVRazorpayService.cls` **unchanged**.
2. `GVPaymentController`: uses system-mode DML when saving the Razorpay order ID on a customer payment; checks only live/active stock reservations.
3. `GVOnlineCheckoutController`: when the same cart already has a pending, unpaid order and no gateway order was initialized, securely renews expired stock reservations using the existing `GVInventoryService` methods. Preserves the original order ID/payment ID; handles historical released/expired reservation rows. It refuses to renew when `Razorpay_Order_ID__c` exists, because a gateway payment may need reconciliation.
4. New `Payment__c.Razorpay_Verified_Payment_ID__c` text field: stores only the payment reference that passed Razorpay checkout HMAC verification in the Automated Process subscriber. This is not the secret or signature.
5. `GVPaymentVerificationController`: offers `requestSignatureVerification` and `signatureVerificationState` to the customer LWC while checking the user's Contact ownership. It publishes your existing `GoldVuee_Payment_Verification__e` event.
6. `GVPaymentVerificationEventHandler`: after verifying Razorpay HMAC against the encrypted server secret in Automated Process, writes the verified payment reference to `Payment__c`. It does **not** confirm the payment or deduct inventory.
7. `GVPaymentVerificationService`: rejects finalization unless the verified signature payment reference matches; still fetches captured payment directly from Razorpay and checks amount, order ID and customer before committing stock. Historical closed reservations are ignored.
8. `goldvueeRazorpayCheckout.js`: after Razorpay's success response, requests the server-side signature check, polls for the signed-proof result, then calls the existing capture/stock/order finalization controller.

## Verify before applying

- Confirm the Experience Cloud customer has enabled Apex class access to `GVOnlineCheckoutController`, `GVPaymentController`, `GVPaymentVerificationController` and the Razorpay External Credential's **specific named principal**. Avoid broad admin privileges.
- Confirm `GV_Payment_Config__c` record `Name='RazorpayTest'` contains the correct Razorpay Test Key Secret and the existing event trigger runs as Automated Process. Do not paste secrets into files or screenshots.
- Ensure `GVRazorpayHost.page` is available to the authenticated Experience Cloud customer and uses the **official** SDK URL `https://checkout.razorpay.com/v1/checkout.js` (already correct in the uploaded file).
- The standalone admin-only Razorpay ₹1 payment does **not** confirm customer permissions or the complete real checkout.

## Deploy in your Salesforce dev org

1. Back up your existing source files locally before copying this patch into `D:\GoldVuee\goldvuee`.
2. Copy the patch's `force-app\main\default\...` files into the same locations in your project (overwrite only the included files).
3. Deploy the new field first:

```powershell
sf project deploy start --source-dir force-app/main/default/objects/Payment__c/fields/Razorpay_Verified_Payment_ID__c.field-meta.xml --target-org goldvuee-dev
```

4. IMPORTANT: The supplied original `GVRazorpayService.cls` already has the correct `/v1` API URLs, but your org might still have an **older deployed version**. Deploy that existing local service file too:

```powershell
sf project deploy start --source-dir force-app/main/default/classes/GVRazorpayService.cls --target-org goldvuee-dev
```

5. Deploy these Apex classes together:

```powershell
sf project deploy start --source-dir force-app/main/default/classes/GVPaymentController.cls --source-dir force-app/main/default/classes/GVOnlineCheckoutController.cls --source-dir force-app/main/default/classes/GVPaymentVerificationController.cls --source-dir force-app/main/default/classes/GVPaymentVerificationService.cls --source-dir force-app/main/default/classes/GVPaymentVerificationEventHandler.cls --target-org goldvuee-dev
```

6. Deploy the LWC:

```powershell
sf project deploy start --source-dir force-app/main/default/lwc/goldvueeRazorpayCheckout --target-org goldvuee-dev
```

7. In Experience Builder, publish the site. Sign in as a customer in a fresh browser session and test a new checkout on the **real GoldVuee checkout page**.

## Required checks / expected behaviour

- COD still orders normally (unmodified code).
- Select Razorpay, press Pay. Salesforce prepares/resumes a pending order, authenticates callout using Named Credential and returns an `order_...` ID, then LWC opens the Visualforce host window to display Razorpay's official popup. The customer-facing checkout is still an LWC; this patch **does not remove** the Visualforce host.
- Complete Test Mode payment within the 15-minute stock reservation window. The host passes `paymentId`, `orderId`, and `signature` to LWC. Salesforce validates the signature asynchronously in Automated Process and verifies `captured` status, amount and order ID before inventory and order confirmation.
- On failure, the order remains pending, and a captured-but-unconfirmed payment requires reconciliation. Never blindly attempt to pay again after a potentially successful gateway response.

Read-only record check:

```powershell
sf data query --target-org goldvuee-dev --query "SELECT Id, Payment_Status__c, Razorpay_Order_ID__c, Razorpay_Verified_Payment_ID__c, Transaction_ID__c FROM Payment__c ORDER BY CreatedDate DESC LIMIT 5"
sf data query --target-org goldvuee-dev --query "SELECT Id, Name, Order_Status__c, Payment_Status__c FROM Jewellery_Order__c ORDER BY CreatedDate DESC LIMIT 5"
```

## Remaining work before production

- Run existing Apex tests including `GVPaymentFinalizationTest`, `GVPaymentVerificationControllerTest`, `GVPaymentVerificationEventHandlerTest`, `GVInventoryServiceTest`, `GVCheckoutControllerTest`; update tests for new signed-proof behaviour and add tampered-signature, expired stock, concurrent retry, and captured-but-interrupted cases.
- Verify event subscriber's access to `GV_Payment_Config__c` and its encrypted key in this specific org and verify its HMAC event completes within the polling window.
- Implement authenticated Razorpay webhook reconciliation for successful gateway payments when the customer's tab is closed or callback/polling fails.
- Test a captured payment that arrives after reservation expiry; do not mark it paid unless inventory can be reconciled safely. Consider improving the 15-minute checkout reservation design.
- This package is not a standalone pure-LWC Razorpay SDK implementation. Razorpay rejected Salesforce-hosted `checkout.js`; the Visualforce host uses Razorpay's required official script URL. An LWR privileged script integration may be explored later, but it has not been proven to work with this payment SDK.

## Security notes

- Never grant guest users payment initialization or verification Apex methods.
- Never expose `GV_Payment_Config__c.Razorpay_Test_Secret__c`, a private key or Named Credential secrets to LWC or Visualforce.
- Only trusted server-side gateway amounts and order IDs should control charges and fulfillment.
- The signed proof field must remain system-managed, not writable through any customer-facing API or record-edit UI.
