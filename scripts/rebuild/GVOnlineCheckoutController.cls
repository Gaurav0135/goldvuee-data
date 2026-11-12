public with sharing class GVOnlineCheckoutController {
    public class CheckoutResult {
        @AuraEnabled public Id orderId;
        @AuraEnabled public Id paymentId;
        @AuraEnabled public String orderNumber;
        @AuraEnabled public Decimal grandTotal;
        @AuraEnabled public String orderStatus;
        @AuraEnabled public String paymentStatus;
        @AuraEnabled public String message;
    }
    @AuraEnabled public static CheckoutResult prepareOnlineOrder(String shippingAddress,String shippingCity,String shippingState,String shippingPostalCode,String shippingCountry) {
        Savepoint sp=Database.setSavepoint();try{return GVCheckoutEngine.prepare(shippingAddress,shippingCity,shippingState,shippingPostalCode,shippingCountry);}catch(Exception e){Database.rollback(sp);throw new AuraHandledException(e.getMessage());}
    }
}
