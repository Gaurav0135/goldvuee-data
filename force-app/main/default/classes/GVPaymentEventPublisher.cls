/** API 66 deliberately preserves system-mode EventBus publication.
 * No external entry point: caller authenticates checkout ownership or bounds raw webhook input.
 * Customers/guests must never receive subscription access to the private verification event.
 */
public without sharing class GVPaymentEventPublisher {
  public static Database.SaveResult publish(
    GoldVuee_Payment_Verification__e eventRecord
  ) {
    return EventBus.publish(eventRecord);
  }
}
