/**
 * Legacy checkout entry point retained for API compatibility.
 *
 * GoldVuee checkout is Razorpay-only. Historical COD orders remain
 * queryable, but this entry point must not create new COD orders.
 */
public with sharing class GVCheckoutController {
  public class CheckoutResult {
    @AuraEnabled
    public Id orderId;
    @AuraEnabled
    public String orderNumber;
    @AuraEnabled
    public Decimal grandTotal;
    @AuraEnabled
    public String orderStatus;
    @AuraEnabled
    public String paymentStatus;
    @AuraEnabled
    public String paymentMethod;
    @AuraEnabled
    public String message;
  }

  @AuraEnabled
  public static CheckoutResult placeOrder(
    String shippingAddress,
    String shippingCity,
    String shippingState,
    String shippingPostalCode,
    String shippingCountry
  ) {
    throw new AuraHandledException(
      'Cash on Delivery is no longer available. Please use Razorpay.'
    );
  }
}