
/**
 * GOLDVUEE | PAYMENT VERIFICATION CONTROLLER
 *
 * Customer-facing entry point.
 * Delegates sensitive payment operations
 * to GVPaymentVerificationService.
 */
public with sharing class GVPaymentVerificationController {

    public class VerificationResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public Id orderId;
        @AuraEnabled public String orderNumber;
        @AuraEnabled public String paymentStatus;
        @AuraEnabled public String orderStatus;
        @AuraEnabled public String message;
    }

    @AuraEnabled
    public static VerificationResult verifyPayment(
        Id paymentId,
        String razorpayPaymentId
    ) {
        try {

            GVPaymentVerificationService.Result serviceResult =
                GVPaymentVerificationService.verify(
                    paymentId,
                    razorpayPaymentId,
                    UserInfo.getUserId()
                );

            VerificationResult result =
                new VerificationResult();

            result.success = serviceResult.success;
            result.orderId = serviceResult.orderId;
            result.orderNumber = serviceResult.orderNumber;
            result.paymentStatus =
                serviceResult.paymentStatus;
            result.orderStatus =
                serviceResult.orderStatus;
            result.message = serviceResult.message;

            return result;

        } catch (Exception e) {

            System.debug(
                LoggingLevel.ERROR,
                'GOLDVUEE PAYMENT VERIFICATION ERROR | ' +
                e.getTypeName() + ': ' + e.getMessage()
            );

            // Preserve original exceptions during tests.
            if (Test.isRunningTest()) {
                throw e;
            }

            throw new AuraHandledException(
                'Unable to complete payment confirmation. ' +
                'Please check your order before retrying.'
            );
        }
    }
}
