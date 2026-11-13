/** Retired queue compatibility shell: never calls the gateway or changes records. */
public without sharing class GVGatewayWorker implements Queueable, Database.AllowsCallouts {
  public GVGatewayWorker(Id paymentId, String operation) {
  }
  public GVGatewayWorker(List<Id> ids) {
  }
  public void execute(QueueableContext context) {
  }
}
