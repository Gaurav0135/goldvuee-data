@IsTest
private class GVRazorpaySignatureServiceTest {
  private static final String TEST_ORDER = 'order_GVSignature123';

  private static final String TEST_PAYMENT = 'pay_GVSignature123';

  private static final String DUMMY_SECRET = 'goldvuee_dummy_secret_for_unit_tests';

  private static String generateTestSignature(
    String orderId,
    String paymentId
  ) {
    String payload = orderId + '|' + paymentId;

    Blob mac = Crypto.generateMac(
      'HmacSHA256',
      Blob.valueOf(payload),
      Blob.valueOf(DUMMY_SECRET)
    );

    return EncodingUtil.convertToHex(mac);
  }

  @IsTest
  static void validSignatureShouldPass() {
    String signature = generateTestSignature(TEST_ORDER, TEST_PAYMENT);

    Test.startTest();

    Boolean result = GVRazorpaySignatureService.isValidSignature(
      TEST_ORDER,
      TEST_PAYMENT,
      signature,
      DUMMY_SECRET
    );

    Test.stopTest();

    System.assertEquals(true, result, 'Valid signature must pass.');
  }

  @IsTest
  static void incorrectSignatureShouldFail() {
    String invalidSignature =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' + 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

    Boolean result = GVRazorpaySignatureService.isValidSignature(
      TEST_ORDER,
      TEST_PAYMENT,
      invalidSignature,
      DUMMY_SECRET
    );

    System.assertEquals(false, result);
  }

  @IsTest
  static void modifiedPaymentIdShouldFail() {
    String signature = generateTestSignature(TEST_ORDER, TEST_PAYMENT);

    Boolean result = GVRazorpaySignatureService.isValidSignature(
      TEST_ORDER,
      'pay_Modified123',
      signature,
      DUMMY_SECRET
    );

    System.assertEquals(false, result);
  }

  @IsTest
  static void modifiedOrderIdShouldFail() {
    String signature = generateTestSignature(TEST_ORDER, TEST_PAYMENT);

    Boolean result = GVRazorpaySignatureService.isValidSignature(
      'order_Modified123',
      TEST_PAYMENT,
      signature,
      DUMMY_SECRET
    );

    System.assertEquals(false, result);
  }

  @IsTest
  static void incorrectSecretShouldFail() {
    String signature = generateTestSignature(TEST_ORDER, TEST_PAYMENT);

    Boolean result = GVRazorpaySignatureService.isValidSignature(
      TEST_ORDER,
      TEST_PAYMENT,
      signature,
      'different_secret'
    );

    System.assertEquals(false, result);
  }

  @IsTest
  static void missingInputsShouldFail() {
    System.assertEquals(
      false,
      GVRazorpaySignatureService.isValidSignature(
        TEST_ORDER,
        TEST_PAYMENT,
        null,
        DUMMY_SECRET
      )
    );

    System.assertEquals(
      false,
      GVRazorpaySignatureService.isValidSignature(
        TEST_ORDER,
        TEST_PAYMENT,
        'invalid',
        DUMMY_SECRET
      )
    );

    System.assertEquals(
      false,
      GVRazorpaySignatureService.isValidSignature(
        TEST_ORDER,
        TEST_PAYMENT,
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' + 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        null
      )
    );
  }
}
