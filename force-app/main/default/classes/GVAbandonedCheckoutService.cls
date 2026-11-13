/** Only uninitialized, expired, unpaid checkouts can be cancelled without a gateway lookup. */
public without sharing class GVAbandonedCheckoutService {
  public class RecoveryException extends Exception {
  }
  public static Boolean recoverExpiredCheckout(Id cartId, Id contactId) {
    if (cartId == null || contactId == null)
      throw new RecoveryException('Customer and bag are required.');
    GVCheckoutEngine.lockCustomer(contactId);
    List<Jewellery_Order__c> orders = [
      SELECT Id, Customer__c, Payment_Status__c
      FROM Jewellery_Order__c
      WHERE Shopping_Cart__c = :cartId AND Order_Status__c = 'pending'
      WITH SYSTEM_MODE
      LIMIT 2
      FOR UPDATE
    ];
    if (orders.isEmpty())
      return false;
    if (
      orders.size() != 1 ||
      orders[0].Customer__c != contactId ||
      orders[0].Payment_Status__c != 'Pending'
    )
      throw new RecoveryException('Existing checkout requires review.');
    Id oid = orders[0].Id;
    List<Payment__c> payments = [
      SELECT
        Id,
        Payment_Status__c,
        Razorpay_Order_ID__c,
        Transaction_ID__c,
        Initialization_State__c
      FROM Payment__c
      WHERE Jewellery_Order__c = :oid
      WITH SYSTEM_MODE
      LIMIT 2
      FOR UPDATE
    ];
    if (payments.size() != 1 || payments[0].Payment_Status__c != 'Pending')
      throw new RecoveryException('Payment requires review.');
    Payment__c p = payments[0];
    if (
      !String.isBlank(p.Razorpay_Order_ID__c) ||
      !String.isBlank(p.Transaction_ID__c) ||
      (!String.isBlank(p.Initialization_State__c) &&
      p.Initialization_State__c != 'New')
    )
      return false;
    Set<Id> ids = new Set<Id>();
    for (Stock_Reservation__c r : [
      SELECT Id, Reservation_Status__c, Expires_At__c
      FROM Stock_Reservation__c
      WHERE Jewellery_Order__c = :oid
      WITH SYSTEM_MODE
    ]) {
      if (r.Reservation_Status__c == 'Committed')
        throw new RecoveryException('Committed stock requires review.');
      if (r.Reservation_Status__c == 'Active') {
        if (r.Expires_At__c == null || r.Expires_At__c > System.now())
          return false;
        ids.add(r.Id);
      }
    }
    if (ids.isEmpty())
      return false;
    GVInventoryService.change(ids, false);
    p.Payment_Status__c = 'Failed';
    update as system p;
    update as system new Jewellery_Order__c(
      Id = oid,
      Order_Status__c = 'Cancelled'
    );
    return true;
  }
}