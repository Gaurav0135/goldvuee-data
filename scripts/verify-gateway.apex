// Read-only gateway connectivity probe. Never log credentials, request headers or configuration values.
try {
    String found=GVRazorpayService.findOrder('GV-CONNECTIVITY-PROBE-NONE',1);
    System.debug(LoggingLevel.INFO,'GV_GATEWAY_READ_OK='+String.isBlank(found));
} catch(Exception e) {
    System.debug(LoggingLevel.ERROR,'GV_GATEWAY_READ_FAILED='+e.getTypeName()+': '+e.getMessage());
}
