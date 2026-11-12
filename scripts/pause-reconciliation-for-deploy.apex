// Temporarily stop only the schedule created by this rebuild. Restore with enable-reconciliation.apex.
for(CronTrigger job:[SELECT Id FROM CronTrigger WHERE CronJobDetail.Name='GoldVuee Hourly Reconciliation' AND State='WAITING']) {
    System.abortJob(job.Id);
}
System.debug(LoggingLevel.INFO,'GV_RECONCILIATION_SCHEDULE_PAUSED=true');
