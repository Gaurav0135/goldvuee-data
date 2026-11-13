/** Only the hosted-link verification path is active. */
trigger GVPaymentVerificationProbe on GoldVuee_Payment_Verification__e(
  after insert
) {
  List<GoldVuee_Payment_Verification__e> hosted = new List<GoldVuee_Payment_Verification__e>();
  for (GoldVuee_Payment_Verification__e event : Trigger.new)
    if (event.Source__c == 'HostedLink')
      hosted.add(event);
  if (!hosted.isEmpty()) GVPaymentWebhook.deliver(hosted);
}
