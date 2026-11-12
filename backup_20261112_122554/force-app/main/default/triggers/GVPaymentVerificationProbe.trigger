
/**
 * GOLDVUEE | RAZORPAY PAYMENT VERIFICATION TRIGGER
 *
 * Receives payment-verification Platform Events
 * and delegates signature validation to the handler.
 *
 * Payment finalization is not enabled yet.
 */
trigger GVPaymentVerificationProbe
    on GoldVuee_Payment_Verification__e (after insert) {

    GVPaymentVerificationEventHandler.process(
        Trigger.new
    );
}
