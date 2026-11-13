public without sharing class GVPaymentVerificationService {
  public class VerificationException extends Exception {
  }
  public class Result {
    public Boolean success;
    public Id orderId;
    public String orderNumber;
    public String paymentStatus;
    public String orderStatus;
    public String message;
  }
  public static Result verify(
    Id paymentId,
    String razorpayPaymentId,
    Id currentUserId
  ) {
    if (
      currentUserId != UserInfo.getUserId() ||
      paymentId == null ||
      String.isBlank(razorpayPaymentId) ||
      !Pattern.matches('^pay_[A-Za-z0-9]+$', razorpayPaymentId)
    )
      throw new VerificationException('Invalid payment verification request.');
    Payment__c payment = GVCheckoutEngine.ownedPayment(paymentId);
    if (
      payment.Payment_Status__c == 'Success' &&
      payment.Transaction_ID__c == razorpayPaymentId
    )
      return GVCheckoutEngine.confirmed(
        [
          SELECT Id, Name, Order_Status__c, Payment_Status__c
          FROM Jewellery_Order__c
          WHERE Id = :payment.Jewellery_Order__c
          WITH SYSTEM_MODE
        ],
        'Payment already confirmed.'
      );
    if (
      payment.Payment_Status__c != 'Pending' ||
      payment.Razorpay_Verified_Payment_ID__c != razorpayPaymentId
    )
      throw new VerificationException('Checkout signature is not verified.');
    GVRazorpayService.RazorpayPaymentDetails gateway = GVRazorpayService.fetchPayment(
      razorpayPaymentId
    );
    Savepoint sp = Database.setSavepoint();
    try {
      return GVCheckoutEngine.finalizeCaptured(paymentId, gateway);
    } catch (Exception e) {
      Database.rollback(sp);
      throw e;
    }
  }
}