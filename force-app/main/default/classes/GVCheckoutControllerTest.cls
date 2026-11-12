@IsTest
private class GVCheckoutControllerTest {
  @IsTest
  static void testCashOnDeliveryIsUnavailable() {
    Boolean rejected = false;

    try {
      GVCheckoutController.placeOrder(
        '123 Gold Street',
        'Jabalpur',
        'Madhya Pradesh',
        '482001',
        'India'
      );
    } catch (AuraHandledException exceptionRecord) {
      rejected = true;
    }

    System.assertEquals(
      true,
      rejected,
      'The legacy COD entry point must reject new orders.'
    );
  }
}
