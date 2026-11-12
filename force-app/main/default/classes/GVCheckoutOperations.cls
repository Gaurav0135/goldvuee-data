/** Operations are restricted to org administrators; no secrets leave this class. */
public without sharing class GVCheckoutOperations {
  private static void admin() {
    Profile p = [
      SELECT PermissionsModifyAllData
      FROM Profile
      WHERE Id = :UserInfo.getProfileId()
      WITH SYSTEM_MODE
    ];
    if (UserInfo.getUserType() != 'Standard' || !p.PermissionsModifyAllData)
      throw new AuraHandledException(
        'GoldVuee operations requires an administrator.'
      );
  }
  public static Map<String, Boolean> configureReconciliation() {
    admin();
    if (
      [
        SELECT COUNT()
        FROM CronTrigger
        WHERE
          CronJobDetail.Name = 'GoldVuee Hourly Reconciliation'
          AND State IN ('WAITING', 'ACQUIRED', 'EXECUTING')
        WITH SYSTEM_MODE
      ] == 0
    )
      System.schedule(
        'GoldVuee Hourly Reconciliation',
        '0 0 * * * ?',
        new GVReconciliationScheduler()
      );
    List<GV_Payment_Config__c> configs = [
      SELECT Razorpay_Test_Secret__c, Webhook_Secret__c
      FROM GV_Payment_Config__c
      WHERE Name = 'RazorpayTest'
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    String secret = configs.isEmpty()
      ? null
      : configs[0].Razorpay_Test_Secret__c;
    String webhook = configs.isEmpty() ? null : configs[0].Webhook_Secret__c;
    return new Map<String, Boolean>{
      'scheduled' => true,
      'checkoutSecretReady' => !String.isBlank(secret) &&
      !secret.contains('****'),
      'webhookSecretReady' => !String.isBlank(webhook) &&
      !webhook.contains('****')
    };
  }
  @AuraEnabled
  public static void reconcilePayment(Id paymentId) {
    admin();
    System.enqueueJob(new GVGatewayWorker(paymentId, 'reconcile'));
  }
  @AuraEnabled
  public static List<Jewellery_Product__c> inventory() {
    admin();
    return [
      SELECT
        Id,
        Name,
        Stock_Quantity__c,
        Reserved_Quantity__c,
        Available_Quantity__c
      FROM Jewellery_Product__c
      WITH SYSTEM_MODE
      ORDER BY Name
      LIMIT 100
    ];
  }
  @AuraEnabled
  public static List<Payment__c> reviewQueue() {
    admin();
    return [
      SELECT
        Id,
        Name,
        Jewellery_Order__c,
        Jewellery_Order__r.Name,
        Payment_Amount__c,
        Payment_Status__c,
        Reconciliation_State__c,
        Last_Checked_At__c
      FROM Payment__c
      WHERE Payment_Status__c = 'Pending'
      WITH SYSTEM_MODE
      ORDER BY CreatedDate DESC
      LIMIT 100
    ];
  }
  @AuraEnabled
  public static List<Jewellery_Order__c> fulfillmentQueue() {
    admin();
    return [
      SELECT Id, Name, Order_Status__c, Grand_Total__c
      FROM Jewellery_Order__c
      WHERE
        Payment_Status__c = 'Paid'
        AND Order_Status__c IN ('Confirmed', 'Processing', 'Shipped')
      WITH SYSTEM_MODE
      ORDER BY Order_Date__c
      LIMIT 100
    ];
  }
  @AuraEnabled
  public static void adjustStock(Id productId, Integer delta, String reason) {
    admin();
    if (
      delta == null ||
      delta == 0 ||
      String.isBlank(reason) ||
      reason.length() > 200
    )
      throw new AuraHandledException(
        'Enter a nonzero whole-unit adjustment and a reason (up to 200 characters).'
      );
    Jewellery_Product__c p = [
      SELECT Id, Stock_Quantity__c, Reserved_Quantity__c
      FROM Jewellery_Product__c
      WHERE Id = :productId
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    Decimal before = p.Stock_Quantity__c == null ? 0 : p.Stock_Quantity__c;
    Decimal after = before + delta;
    if (
      after < 0 ||
      after < (p.Reserved_Quantity__c == null ? 0 : p.Reserved_Quantity__c)
    )
      throw new AuraHandledException(
        'Adjustment would consume reserved stock.'
      );
    Savepoint sp = Database.setSavepoint();
    try {
      p.Stock_Quantity__c = after;
      update as system p;
      insert as system new Inventory_Movement__c(
        Jewellery_Product__c = p.Id,
        Movement_Type__c = delta > 0 ? 'Stock In' : 'Adjustment',
        Quantity__c = Math.abs(delta),
        Stock_Before__c = before,
        Stock_After__c = after,
        Movement_Date__c = System.now(),
        Reason__c = reason
      );
    } catch (Exception e) {
      Database.rollback(sp);
      throw e;
    }
  }
  @AuraEnabled
  public static void advanceOrder(Id orderId, String nextStatus) {
    admin();
    Jewellery_Order__c o = [
      SELECT Id, Order_Status__c, Payment_Status__c
      FROM Jewellery_Order__c
      WHERE Id = :orderId
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    Map<String, String> transitions = new Map<String, String>{
      'Confirmed' => 'Processing',
      'Processing' => 'Shipped',
      'Shipped' => 'Delivered'
    };
    if (
      o.Payment_Status__c != 'Paid' ||
      transitions.get(o.Order_Status__c) != nextStatus
    )
      throw new AuraHandledException(
        'Only paid orders may advance one fulfillment stage at a time.'
      );
    o.Order_Status__c = nextStatus;
    update as system o;
  }
}
