/** Expiry sweep dispatches only new expiry-policy attempts to the existing gateway worker. */
public without sharing class GVPaymentExpiryScheduler implements Schedulable, Database.Batchable<SObject> {
  public void execute(SchedulableContext context) {
    // Avoid overlapping sweeps under batch backlog; Salesforce execution is not exact-time.
    if (
      [
        SELECT COUNT()
        FROM AsyncApexJob
        WHERE
          ApexClass.Name = 'GVPaymentExpiryScheduler'
          AND JobType = 'BatchApex'
          AND Status IN ('Holding', 'Queued', 'Preparing', 'Processing')
        WITH SYSTEM_MODE
      ] == 0
    )
      Database.executeBatch(new GVPaymentExpiryScheduler(), 1);
  }
  public Database.QueryLocator start(Database.BatchableContext context) {
    return Database.getQueryLocator(
      [
        SELECT Id, Gateway_Response__c, Razorpay_Order_ID__c
        FROM Payment__c
        WHERE Payment_Status__c = 'Pending'
        WITH SYSTEM_MODE
      ]
    );
  }
  public void execute(Database.BatchableContext context, List<SObject> scope) {
    for (SObject record : scope) {
      Payment__c p = (Payment__c) record;
      GVCheckoutService.Attempt a = GVCheckoutService.attempt(p);
      if (
        a.expirySeconds == 120 &&
        (a.linkCreatedAt == null ||
        System.now().getTime() >= (a.linkCreatedAt + 120) * 1000)
      )
        GVRazorpayController.reconcileForAdmin(p.Id);
    }
  }
  public void finish(Database.BatchableContext context) {
  }
}
