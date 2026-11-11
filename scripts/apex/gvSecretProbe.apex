GoldVuee_Payment_Verification__e eventRecord =
    new GoldVuee_Payment_Verification__e();

Database.SaveResult result =
    EventBus.publish(eventRecord);

System.debug(
    LoggingLevel.ERROR,
    'GOLDVUEE TEST EVENT PUBLISHED: ' +
    result.isSuccess()
);
