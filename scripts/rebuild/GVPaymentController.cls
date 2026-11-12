/** Initialization ownership is persisted before the one authorized callout worker is enqueued. */
public without sharing class GVPaymentController {
    public class PaymentResult {
        @AuraEnabled public Id paymentId;
        @AuraEnabled public Id orderId;
        @AuraEnabled public String razorpayOrderId;
        @AuraEnabled public Long amountPaise;
        @AuraEnabled public String currencyCode;
        @AuraEnabled public String message;
        @AuraEnabled public String state;
    }
    @AuraEnabled public static PaymentResult initiatePayment(Id paymentId) {
        Payment__c pre=GVCheckoutEngine.ownedPayment(paymentId);GVCheckoutEngine.lockCustomer(pre.Jewellery_Order__r.Customer__c);
        Payment__c payment=[SELECT Id,Jewellery_Order__c,Payment_Amount__c,Payment_Status__c,Razorpay_Order_ID__c,Initialization_State__c FROM Payment__c WHERE Id=:paymentId FOR UPDATE];
        if(payment.Payment_Status__c!='Pending' || pre.Jewellery_Order__r.Order_Status__c!='pending' || pre.Jewellery_Order__r.Payment_Status__c!='Pending' || payment.Payment_Amount__c!=pre.Jewellery_Order__r.Grand_Total__c) throw new AuraHandledException('This order is not awaiting payment.');
        GVCheckoutEngine.reservationIds(payment.Jewellery_Order__c,true);
        if(String.isBlank(payment.Razorpay_Order_ID__c) && (String.isBlank(payment.Initialization_State__c) || payment.Initialization_State__c=='New')) {
            payment.Initialization_State__c='Queued';payment.Last_Checked_At__c=System.now();
            payment.Initialization_Job__c=System.enqueueJob(new GVGatewayWorker(payment.Id,'initialize'));update payment;
        }
        return result(payment);
    }
    @AuraEnabled public static PaymentResult paymentState(Id paymentId) { return result(GVCheckoutEngine.ownedPayment(paymentId)); }
    private static PaymentResult result(Payment__c p) {PaymentResult r=new PaymentResult();r.paymentId=p.Id;r.orderId=p.Jewellery_Order__c;r.razorpayOrderId=p.Razorpay_Order_ID__c;r.amountPaise=(p.Payment_Amount__c*100).longValue();r.currencyCode='INR';r.state=String.isBlank(p.Razorpay_Order_ID__c)?p.Initialization_State__c:'Ready';r.message='Payment initialization '+r.state;return r;}
}
