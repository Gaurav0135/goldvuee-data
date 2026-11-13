/** Hourly bounded batch: each payment gets a separate callout/DML transaction. */
public without sharing class GVReconciliationScheduler implements Schedulable, Database.Batchable<SObject>, Database.AllowsCallouts {
  public void execute(SchedulableContext context) {
    Database.executeBatch(new GVReconciliationScheduler(), 1);
  }
  public Database.QueryLocator start(Database.BatchableContext context) {
    return Database.getQueryLocator(
      [
        SELECT Id
        FROM Payment__c
        WHERE
          Payment_Status__c = 'Pending'
          AND (Last_Checked_At__c = NULL
          OR Last_Checked_At__c < :System.now().addMinutes(-10))
        WITH SYSTEM_MODE
        ORDER BY Last_Checked_At__c ASC NULLS FIRST
        LIMIT 500
      ]
    );
  }
  public void execute(
    Database.BatchableContext context,
    List<Payment__c> scope
  ) {
    if (!scope.isEmpty())
      new GVGatewayWorker(scope[0].Id, 'reconcile').execute(null);
  }
  public void finish(Database.BatchableContext context) {
  }
}