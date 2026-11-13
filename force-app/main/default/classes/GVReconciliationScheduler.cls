/** Retired scheduled/batch shell. Existing scheduler is separately stopped after deployment. */
public without sharing class GVReconciliationScheduler implements Schedulable, Database.Batchable<SObject>, Database.AllowsCallouts {
  public void execute(SchedulableContext context) {
  }
  public Database.QueryLocator start(Database.BatchableContext context) {
    return Database.getQueryLocator(
      [SELECT Id FROM Payment__c WHERE Id = NULL WITH SYSTEM_MODE]
    );
  }
  public void execute(
    Database.BatchableContext context,
    List<Payment__c> scope
  ) {
  }
  public void finish(Database.BatchableContext context) {
  }
}
