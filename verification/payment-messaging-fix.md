# Payment popup messaging fix — 12 November 2026

The checkout's outgoing `postMessage` used an object envelope. The user's browser rejected that envelope with `DataCloneError: [object Object] could not be cloned`, leaving the Visualforce host waiting for payment details. This is consistent with object proxies at the Lightning Web Security boundary.

Both the LWC and Visualforce bridge now send primitive JSON strings, decode incoming strings defensively, and retain origin, source-window, nonce and payment-data validation. Legacy object messages are accepted during rollout. Malformed/oversized strings are ignored. A failed send clears the misleading completion instruction, closes the failed host and unlocks retry; `paymentSent` is set only after successful transmission.

Deployment `0AfjV000006NQw1SAG` succeeded in the verified Developer Edition `goldvuee-dev`. Site publication `08PjV00000GvGbhUAF` completed.

Validation:

- 32 Jest UI tests passed across 13 suites (`payment-messaging-jest.json`).
- Four Node tests executed the actual Visualforce script: serialized initialization/callback, origin/source/nonce rejection, malformed data/invalid amounts, and duplicate initialization.
- Component lint: zero errors and warnings (`payment-messaging-lint.json`).
- Retried the existing signed-in checkout in the browser. The actual Razorpay Test Mode window opened at the contact-details step with GoldVuee and the correct INR 238,600 amount. No payment was submitted during this check.

Only the payment LWC, Visualforce bridge and regression tests were changed. No order, inventory, credentials, webhook configuration or Lightning Web Security settings were modified by this fix. The existing gateway order was reused during the browser check.

Reference: [Salesforce documentation on LWS cross-window identity](https://help.salesforce.com/s/articleView?id=000392327&language=en_US&type=1).
