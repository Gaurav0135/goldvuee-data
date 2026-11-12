/**
 * GOLDVUEE | RAZORPAY PAYMENT VERIFICATION EVENT HANDLER
 *
 * Validates genuine Razorpay checkout signatures
 * using the server-side Test Key Secret.
 *
 * Security:
 * - Never exposes the secret to the customer.
 * - Uses the trusted Razorpay Order ID from Salesforce.
 * - Rejects invalid payment IDs and signatures.
 * - Does not finalize payments in this version.
 */
public without sharing class GVPaymentVerificationEventHandler {

    public static void process(
        List<GoldVuee_Payment_Verification__e> events
    ) {
        if (events == null || events.isEmpty()) {
            return;
        }

        // STEP 1: COLLECT VALID PAYMENT IDs

        Set<Id> paymentIds = new Set<Id>();

        for (
            GoldVuee_Payment_Verification__e eventRecord :
            events
        ) {
            try {
                if (
                    String.isBlank(
                        eventRecord.Payment_Record_ID__c
                    )
                ) {
                    continue;
                }

                Id paymentId = Id.valueOf(
                    eventRecord.Payment_Record_ID__c
                );

                if (
                    paymentId.getSObjectType() ==
                    Payment__c.SObjectType
                ) {
                    paymentIds.add(paymentId);
                }

            } catch (Exception e) {
                System.debug(
                    LoggingLevel.WARN,
                    'GOLDVUEE_VERIFY: INVALID_PAYMENT_ID'
                );
            }
        }

        if (paymentIds.isEmpty()) {
            return;
        }

        // STEP 2: LOAD TRUSTED SALESFORCE PAYMENTS

        Map<Id, Payment__c> payments =
            new Map<Id, Payment__c>([
                SELECT Id,
                       Razorpay_Order_ID__c,
                       Payment_Status__c,
                       Jewellery_Order__c
                FROM Payment__c
                WHERE Id IN :paymentIds
                WITH SYSTEM_MODE
            ]);

        // STEP 3: LOAD SERVER-SIDE TEST SECRET

        List<GV_Payment_Config__c> configs = [
            SELECT Id,
                   Razorpay_Test_Secret__c
            FROM GV_Payment_Config__c
            WHERE Name = 'RazorpayTest'
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        if (
            configs.isEmpty() ||
            String.isBlank(
                configs[0].Razorpay_Test_Secret__c
            )
        ) {
            System.debug(
                LoggingLevel.ERROR,
                'GOLDVUEE_VERIFY: CONFIG_UNAVAILABLE'
            );
            return;
        }

        String secret =
            configs[0].Razorpay_Test_Secret__c;

        // STEP 4: VERIFY EACH CHECKOUT SIGNATURE

        for (
            GoldVuee_Payment_Verification__e eventRecord :
            events
        ) {
            try {
                if (
                    String.isBlank(
                        eventRecord.Payment_Record_ID__c
                    ) ||
                    String.isBlank(
                        eventRecord.Razorpay_Payment_ID__c
                    ) ||
                    String.isBlank(
                        eventRecord.Razorpay_Signature__c
                    )
                ) {
                    System.debug(
                        LoggingLevel.WARN,
                        'GOLDVUEE_VERIFY: MISSING_INPUT'
                    );
                    continue;
                }

                Id paymentId = Id.valueOf(
                    eventRecord.Payment_Record_ID__c
                );

                Payment__c payment =
                    payments.get(paymentId);

                if (
                    payment == null ||
                    payment.Jewellery_Order__c == null ||
                    payment.Payment_Status__c != 'Pending' ||
                    String.isBlank(
                        payment.Razorpay_Order_ID__c
                    )
                ) {
                    System.debug(
                        LoggingLevel.WARN,
                        'GOLDVUEE_VERIFY: PAYMENT_NOT_PENDING'
                    );
                    continue;
                }

                String razorpayPaymentId =
                    eventRecord.Razorpay_Payment_ID__c;

                String signature =
                    eventRecord.Razorpay_Signature__c;

                if (
                    !Pattern.matches(
                        '^pay_[A-Za-z0-9]+$',
                        razorpayPaymentId
                    ) ||
                    !Pattern.matches(
                        '^[a-fA-F0-9]{64}$',
                        signature
                    ) ||
                    !Pattern.matches(
                        '^order_[A-Za-z0-9]+$',
                        payment.Razorpay_Order_ID__c
                    )
                ) {
                    System.debug(
                        LoggingLevel.WARN,
                        'GOLDVUEE_VERIFY: INVALID_FORMAT'
                    );
                    continue;
                }

                // Verify the genuine Razorpay checkout HMAC.
                // Message format: razorpay_order_id|razorpay_payment_id

                String signedMessage =
                    payment.Razorpay_Order_ID__c +
                    '|' +
                    razorpayPaymentId;

               // Verify Razorpay HMAC-SHA256 securely.
// signedMessage = razorpay_order_id + '|' + razorpay_payment_id

Boolean valid = Crypto.verifyHMac(
    'HmacSHA256',
    Blob.valueOf(signedMessage),
    Blob.valueOf(secret),
    EncodingUtil.convertFromHex(signature)
);

                if (!valid) {
                    System.debug(
                        LoggingLevel.WARN,
                        'GOLDVUEE_VERIFY: INVALID_SIGNATURE'
                    );
                    continue;
                }

                System.debug(
                    LoggingLevel.INFO,
                    'GOLDVUEE_VERIFY: SIGNATURE_VALID'
                );

                // Recheck the payment under a record lock and
                // persist the ID whose Razorpay signature was valid.
                // This is NOT payment confirmation; the customer
                // controller still fetches captured gateway payment.
                List<Payment__c> lockedMatches = [
                    SELECT Id, Payment_Status__c,
                           Razorpay_Order_ID__c,
                           Razorpay_Verified_Payment_ID__c
                    FROM Payment__c
                    WHERE Id = :paymentId
                    WITH SYSTEM_MODE
                    LIMIT 1
                    FOR UPDATE
                ];

                if (
                    lockedMatches.isEmpty() ||
                    lockedMatches[0].Payment_Status__c != 'Pending' ||
                    lockedMatches[0].Razorpay_Order_ID__c !=
                        payment.Razorpay_Order_ID__c
                ) {
                    continue;
                }

                lockedMatches[0].Razorpay_Verified_Payment_ID__c =
                    razorpayPaymentId;

                Database.update(
                    lockedMatches[0], true, AccessLevel.SYSTEM_MODE
                );

                System.debug(
                    LoggingLevel.INFO,
                    'GOLDVUEE_VERIFY: SIGNATURE_PROOF_STORED'
                );

            } catch (Exception e) {
                System.debug(
                    LoggingLevel.ERROR,
                    'GOLDVUEE_VERIFY: VALIDATION_ERROR | ' +
                    e.getTypeName()
                );
            }
        }
    }
}