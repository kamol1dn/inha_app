import 'package:webview_flutter/webview_flutter.dart';

class WebViewService {
  static WebViewController createController(String url) {
    return WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(url));
  }
}
