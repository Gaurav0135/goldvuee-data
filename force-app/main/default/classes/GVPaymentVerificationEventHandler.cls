/** Automated Process verifies secrets; bulk queries/DML keep event delivery bounded. */
public without sharing class GVPaymentVerificationEventHandler {
  public static void process(List<GoldVuee_Payment_Verification__e> events) {
    if (events == null || events.isEmpty())
      return;
    List<GV_Payment_Config__c> configs = [
      SELECT Razorpay_Test_Secret__c, Webhook_Secret__c
      FROM GV_Payment_Config__c
      WHERE Name = 'RazorpayTest'
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (configs.isEmpty())
      return;
    GV_Payment_Config__c config = configs[0];
    Set<Id> pids = new Set<Id>();
    Set<String> orderIds = new Set<String>();
    Map<String, String> webhookOrders = new Map<String, String>();
    for (GoldVuee_Payment_Verification__e eventRecord : events) {
      if (eventRecord.Source__c == 'Webhook') {
        if (
          !validHmac(
            eventRecord.Raw_Body__c,
            eventRecord.Razorpay_Signature__c,
            config.Webhook_Secret__c
          )
        )
          continue;
        try {
          Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(
            eventRecord.Raw_Body__c
          );
          if (String.valueOf(data.get('event')) != 'payment.captured')
            continue;
          Map<String, Object> payload = (Map<String, Object>) data.get(
            'payload'
          );
          Map<String, Object> pay = (Map<String, Object>) payload.get(
            'payment'
          );
          Map<String, Object> entity = (Map<String, Object>) pay.get('entity');
          String oid = String.valueOf(entity.get('order_id'));
          if (!Pattern.matches('^order_[A-Za-z0-9]+$', oid))
            continue;
          String digest = EncodingUtil.convertToHex(
            Crypto.generateDigest(
              'SHA-256',
              Blob.valueOf(eventRecord.Raw_Body__c)
            )
          );
          webhookOrders.put(digest, oid);
          orderIds.add(oid);
        } catch (Exception ignored) {
          continue;
        }
      } else {
        try {
          Id pid = Id.valueOf(eventRecord.Payment_Record_ID__c);
          if (pid.getSObjectType() == Payment__c.SObjectType)
            pids.add(pid);
        } catch (Exception ignored) {
          continue;
        }
      }
    }
    Map<Id, Payment__c> payments = new Map<Id, Payment__c>(
      [
        SELECT Id, Razorpay_Order_ID__c, Payment_Status__c
        FROM Payment__c
        WHERE Id IN :pids OR Razorpay_Order_ID__c IN :orderIds
        WITH SYSTEM_MODE
      ]
    );
    Map<Id, Payment__c> proofs = new Map<Id, Payment__c>();
    Set<Id> reconcile = new Set<Id>();
    for (GoldVuee_Payment_Verification__e eventRecord : events) {
      if (eventRecord.Source__c == 'Webhook')
        continue;
      try {
        Id pid = Id.valueOf(eventRecord.Payment_Record_ID__c);
        Payment__c payment = payments.get(pid);
        if (
          payment == null ||
          payment.Payment_Status__c != 'Pending' ||
          String.isBlank(eventRecord.Razorpay_Payment_ID__c) ||
          !Pattern.matches(
            '^pay_[A-Za-z0-9]+$',
            eventRecord.Razorpay_Payment_ID__c
          )
        )
          continue;
        if (
          GVRazorpaySignatureService.isValidSignature(
            payment.Razorpay_Order_ID__c,
            eventRecord.Razorpay_Payment_ID__c,
            eventRecord.Razorpay_Signature__c,
            config.Razorpay_Test_Secret__c
          )
        ) {
          proofs.put(
            pid,
            new Payment__c(
              Id = pid,
              Razorpay_Verified_Payment_ID__c = eventRecord.Razorpay_Payment_ID__c
            )
          );
          reconcile.add(pid);
        }
      } catch (Exception ignored) {
        continue;
      }
    }
    if (!proofs.isEmpty())
      Database.update(proofs.values(), true, AccessLevel.SYSTEM_MODE);
    Set<String> seen = new Set<String>();
    for (GV_Webhook_Receipt__c r : [
      SELECT Digest__c
      FROM GV_Webhook_Receipt__c
      WHERE Digest__c IN :webhookOrders.keySet()
      WITH SYSTEM_MODE
    ])
      seen.add(r.Digest__c);
    List<GV_Webhook_Receipt__c> receipts = new List<GV_Webhook_Receipt__c>();
    Map<String, Id> byOrder = new Map<String, Id>();
    for (Payment__c p : payments.values())
      byOrder.put(p.Razorpay_Order_ID__c, p.Id);
    for (String digest : webhookOrders.keySet())
      if (
        !seen.contains(digest) && byOrder.containsKey(webhookOrders.get(digest))
      ) {
        Id pid = byOrder.get(webhookOrders.get(digest));
        receipts.add(
          new GV_Webhook_Receipt__c(Digest__c = digest, Payment__c = pid)
        );
      }
    if (!receipts.isEmpty()) {
      Database.SaveResult[] results = Database.insert(
        receipts,
        false,
        AccessLevel.SYSTEM_MODE
      );
      for (Integer i = 0; i < results.size(); i++)
        if (results[i].isSuccess())
          reconcile.add(receipts[i].Payment__c);
    }
    if (!reconcile.isEmpty())
      System.enqueueJob(new GVGatewayWorker(new List<Id>(reconcile)));
  }
  public static Boolean validHmac(
    String body,
    String signature,
    String secret
  ) {
    if (
      String.isBlank(body) ||
      String.isBlank(secret) ||
      secret.contains('****') ||
      String.isBlank(signature) ||
      !Pattern.matches('^[a-fA-F0-9]{64}$', signature)
    )
      return false;
    return Crypto.verifyHMac(
      'HmacSHA256',
      Blob.valueOf(body),
      Blob.valueOf(secret),
      EncodingUtil.convertFromHex(signature)
    );
  }
}
