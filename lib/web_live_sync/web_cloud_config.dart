// FILE: lib/web_live_sync/web_cloud_config.dart

class WebCloudConfig {
  static const String webPortalUrl = "https://pharoah-erp.pages.dev";
  static const String cloudRelayEndpoint =
      "https://script.google.com/macros/s/AKfycbyKFFt9WK-xB1qLRTD7M-b4jSlpCBoBfJ18x8FUP1wFBzbQ-dQgyjm1qPfvl2kQmaSl/exec";
  static const String actionPushStore = "PUSH_STORE_DATA";
  static const String actionPullStore = "PULL_STORE_DATA";
  static const String actionVerifyLogin = "VERIFY_STORE_LOGIN";
  static const Duration networkTimeout = Duration(seconds: 30);
  static const Map<String, String> standardHeaders = {
    "Content-Type": "text/plain;charset=utf-8",
  };
}
