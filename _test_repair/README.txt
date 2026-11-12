GoldVuee — Apex test repairs (NOT a full checkout/production release)

Includes 4 TEST classes only; no production classes are changed.

Changes:
1. Checkout tests: use the external-user creation pattern that was already
   used successfully in GVPaymentFinalizationTest (role-bearing account owner,
   GoldVuee customer profile). If your org blocks external-profile creation
   globally, admin configuration may still be required.
2. Payment finalization: test fixture now models a payment ID that already
   passed server-side signature verification; the production security check
   stays mandatory. Additional negative tests are still needed.
3. Null request: catches the service's actual VerificationException.
4. Platform event test: publishes an invalid verification event and delivers
   it to exercise the actual subscriber trigger. It does not mark a payment paid.

Suggested first validation, for these 4 test classes only:
sf project deploy validate --source-dir force-app/main/default/classes/GVCheckoutControllerTest.cls --source-dir force-app/main/default/classes/GVPaymentFinalizationTest.cls --source-dir force-app/main/default/classes/GVPaymentVerificationControllerTest.cls --source-dir force-app/main/default/classes/GVPaymentVerificationEventHandlerTest.cls --source-dir force-app/main/default/classes/GVAbandonedCheckoutService.cls --source-dir force-app/main/default/classes/GVCheckoutController.cls --source-dir force-app/main/default/classes/GVOnlineCheckoutController.cls --target-org goldvuee-dev --test-level RunLocalTests

Do NOT use --test-level NoTestRun as evidence that the checkout is safe.
Do NOT deploy payment/checkout to production until all functional workflows
and webhook/reconciliation scenarios have been tested.
