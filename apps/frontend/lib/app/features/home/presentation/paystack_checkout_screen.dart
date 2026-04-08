/// lib/app/features/home/presentation/paystack_checkout_screen.dart
/// ------------------------------------------------------------
/// WHAT:
/// - In-app Paystack checkout screen (mobile).
///
/// WHY:
/// - Allows us to intercept callback URL and route back into Flutter.
/// - Prevents external browser bounce on Android/iOS.
///
/// HOW:
/// - Loads Paystack authorizationUrl in WebView.
/// - Watches navigation for callbackUrl, then redirects to /payment-success.
///
/// DEBUGGING:
/// - Logs build, page start/finish, navigation, errors, and button taps.
/// ------------------------------------------------------------
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/platform/platform_info.dart';

class PaystackCheckoutArgs {
  final String authorizationUrl;
  final String callbackUrl;
  final String? successRedirect;

  const PaystackCheckoutArgs({
    required this.authorizationUrl,
    required this.callbackUrl,
    this.successRedirect,
  });
}

class PaystackCheckoutScreen extends StatefulWidget {
  final PaystackCheckoutArgs args;

  const PaystackCheckoutScreen({super.key, required this.args});

  @override
  State<PaystackCheckoutScreen> createState() =>
      _PaystackCheckoutScreenState();
}

class _PaystackCheckoutScreenState extends State<PaystackCheckoutScreen> {
  late final WebViewController _controller;

  bool _isLoading = true;
  bool _hasError = false;
  bool _handledCallback = false;

  @override
  void initState() {
    super.initState();

    AppDebug.log("PAYSTACK_WEBVIEW", "initState()");

    // WHY: WebView only makes sense on mobile; show fallback on web.
    if (PlatformInfo.isWeb) return;

    _controller =
        WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setNavigationDelegate(
            NavigationDelegate(
              onPageStarted: (url) {
                AppDebug.log(
                  "PAYSTACK_WEBVIEW",
                  "onPageStarted()",
                  extra: {"url": url},
                );
                setState(() {
                  _isLoading = true;
                  _hasError = false;
                });
              },
              onPageFinished: (url) {
                AppDebug.log(
                  "PAYSTACK_WEBVIEW",
                  "onPageFinished()",
                  extra: {"url": url},
                );
                setState(() => _isLoading = false);
              },
              onNavigationRequest: (request) {
                final url = request.url;
                AppDebug.log(
                  "PAYSTACK_WEBVIEW",
                  "onNavigationRequest()",
                  extra: {"url": url},
                );

                if (_isCallbackUrl(url)) {
                  _handleCallback(url);
                  return NavigationDecision.prevent;
                }

                return NavigationDecision.navigate;
              },
              onWebResourceError: (error) {
                AppDebug.log(
                  "PAYSTACK_WEBVIEW",
                  "onWebResourceError()",
                  extra: {
                    "code": error.errorCode,
                    "desc": error.description,
                    "url": error.url ?? "",
                  },
                );
                setState(() {
                  _hasError = true;
                  _isLoading = false;
                });
              },
            ),
          )
          ..loadRequest(Uri.parse(widget.args.authorizationUrl));
  }

  bool _isCallbackUrl(String url) {
    if (widget.args.callbackUrl.isEmpty) return false;

    final callbackUri = Uri.parse(widget.args.callbackUrl);
    final incoming = Uri.tryParse(url);
    if (incoming == null) return false;

    // WHY: Match scheme + host + path to avoid false positives.
    return incoming.scheme == callbackUri.scheme &&
        incoming.host == callbackUri.host &&
        incoming.path == callbackUri.path;
  }

  void _handleCallback(String url) {
    if (_handledCallback) return;
    _handledCallback = true;

    final callbackUri = Uri.parse(url);
    final reference = callbackUri.queryParameters["reference"] ?? "";
    final successRedirect = widget.args.successRedirect?.trim();

    AppDebug.log(
      "PAYSTACK_WEBVIEW",
      "Callback detected",
      extra: {"reference": reference},
    );

    // WHY: Route back into the app with reference (if any).
    if (!mounted) return;

    // WHY: Allow tenant payments to override the post-success destination.
    final route = reference.isNotEmpty
        ? Uri(
            path: "/payment-success",
            queryParameters: {
              "reference": reference,
              if (successRedirect != null && successRedirect.isNotEmpty)
                "next": successRedirect,
            },
          ).toString()
        : Uri(
            path: "/payment-success",
            queryParameters: {
              if (successRedirect != null && successRedirect.isNotEmpty)
                "next": successRedirect,
            },
          ).toString();

    AppDebug.log(
      "PAYSTACK_WEBVIEW",
      "Navigate -> payment_success",
      extra: {
        "hasReference": reference.isNotEmpty,
        "hasNext": successRedirect != null && successRedirect.isNotEmpty,
      },
    );

    context.go(route);
  }

  Future<void> _openInBrowser() async {
    AppDebug.log("PAYSTACK_WEBVIEW", "Open in browser tapped");

    final uri = Uri.parse(widget.args.authorizationUrl);
    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to open browser")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log("PAYSTACK_WEBVIEW", "build()");

    // WHY: Web doesn't support in-app WebView flow in this app.
    if (PlatformInfo.isWeb) {
      return Scaffold(
        appBar: AppBar(title: const Text("Paystack Checkout")),
        body: const Center(
          child: Text("Paystack WebView is mobile-only."),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Paystack Checkout"),
        leading: IconButton(
          onPressed: () {
            AppDebug.log("PAYSTACK_WEBVIEW", "Close tapped");
            context.pop();
          },
          icon: const Icon(Icons.close),
        ),
        actions: [
          IconButton(
            onPressed: _openInBrowser,
            icon: const Icon(Icons.open_in_browser),
            tooltip: "Open in browser",
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(child: CircularProgressIndicator()),
          if (_hasError)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Paystack failed to load."),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _openInBrowser,
                      child: const Text("Open in browser"),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
