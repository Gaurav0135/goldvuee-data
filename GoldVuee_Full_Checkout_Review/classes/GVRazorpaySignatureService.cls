
/**
 * GOLDVUEE | RAZORPAY SIGNATURE VERIFICATION
 *
 * Supports Razorpay Test Mode.
 *
 * IMPORTANT:
 * - Never pass the secret from JavaScript.
 * - Retrieve the Razorpay order ID from Salesforce.
 * - Never expose the Key Secret in an LWC.
 */
public without sharing class GVRazorpaySignatureService {

    /**
     * Verify Razorpay Standard Checkout signature.
     *
     * orderId      = trusted Razorpay order ID
     * paymentId    = Razorpay Checkout payment ID
     * signature    = Razorpay Checkout signature
     * secret       = server-side Razorpay Test Key Secret
     */
    public static Boolean isValidSignature(
        String orderId,
        String paymentId,
        String signature,
        String secret
    ) {
        if (
            String.isBlank(orderId) ||
            String.isBlank(paymentId) ||
            String.isBlank(signature) ||
            String.isBlank(secret)
        ) {
            return false;
        }

        // Razorpay returns a 64-character SHA256 hex signature.
        if (
            !Pattern.matches(
                '^[a-fA-F0-9]{64}$',
                signature
            )
        ) {
            return false;
        }

        // Razorpay signs: order_id|payment_id
        String payload = orderId + '|' + paymentId;

        try {
            Blob payloadBlob = Blob.valueOf(payload);
            Blob secretBlob = Blob.valueOf(secret);

            Blob signatureBlob =
                EncodingUtil.convertFromHex(
                    signature.toLowerCase()
                );

            // Salesforce validates the HMAC.
            return Crypto.verifyHMac(
                'HmacSHA256',
                payloadBlob,
                secretBlob,
                signatureBlob
            );

        } catch (Exception e) {
            return false;
        }
    }
}
