import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';

/// Hosts the AWS Face Liveness web flow inside an InAppWebView.
/// flutter_inappwebview is used (not webview_flutter) because it has robust
/// getUserMedia + WebSocket support, which AWS Amplify Liveness needs to
/// stream the camera feed during the analysis phase.
class LivenessScanScreen extends StatefulWidget {
  const LivenessScanScreen({super.key});

  @override
  State<LivenessScanScreen> createState() => _LivenessScanScreenState();
}

class _LivenessScanScreenState extends State<LivenessScanScreen> {
  bool _resultHandled = false;
  bool _loading = true;
  bool _permGranted = false;
  // Generated once per screen visit so the WebView mounts a fresh instance
  // and the React app fetches a brand new AWS Liveness session.
  late final int _cacheBust;
  late final String _url;

  @override
  void initState() {
    super.initState();
    _cacheBust = DateTime.now().millisecondsSinceEpoch;
    _url =
        '${AppConstants.livenessUrl}?company_code=${AppConstants.companyCode}&t=$_cacheBust';
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final cam = await Permission.camera.request();
    final mic = await Permission.microphone.request();
    if (!cam.isGranted || !mic.isGranted) {
      _failWithReason('camera_permission_denied');
      return;
    }
    if (!mounted) return;
    setState(() => _permGranted = true);
  }

  void _onLivenessMessage(List<dynamic> args) {
    if (_resultHandled) return;
    if (args.isEmpty) return;
    _resultHandled = true;

    Map<String, dynamic> data;
    try {
      data = jsonDecode(args.first.toString()) as Map<String, dynamic>;
    } catch (_) {
      _failWithReason('bad_response');
      return;
    }

    HapticFeedback.mediumImpact();
    if (!mounted) return;

    if (data['success'] == true) {
      context.go('/kiosk/success', extra: {
        'employee_name': data['employee_name'],
        'time':          data['time'],
        'action':        data['action'],
      });
    } else {
      context.go('/kiosk/failed');
    }
  }

  void _failWithReason(String _) {
    if (_resultHandled) return;
    _resultHandled = true;
    if (!mounted) return;
    context.go('/kiosk/failed');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            if (_permGranted) _buildWebView(),
            if (_loading)
              const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppTheme.accent),
                    SizedBox(height: 16),
                    Text(
                      'Starting liveness check…',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: _exit,
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.settings, color: Colors.white54),
                onPressed: _showAdminDialog,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebView() {
    // _cacheBust + _url are set once in initState — using a stable key
    // here avoids re-mounting the WebView on every setState (which would
    // create a fresh AWS Liveness session each rebuild and bill us per
    // unused session).
    return InAppWebView(
      key: ValueKey(_cacheBust),
      initialUrlRequest: URLRequest(url: WebUri(_url)),
      initialSettings: InAppWebViewSettings(
        // Camera + mic streaming
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        iframeAllow: 'camera; microphone',
        iframeAllowFullscreen: true,
        // Required so AWS WebSocket origin checks pass
        useHybridComposition: true,
        // Don't auto-grant cookies/clipboard, but allow JS
        javaScriptEnabled: true,
        javaScriptCanOpenWindowsAutomatically: false,
        transparentBackground: false,
        // Mixed content sometimes triggers when AWS uses ws://; force HTTPS only
        mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
      ),
      onWebViewCreated: (controller) {
        controller.addJavaScriptHandler(
          handlerName: 'FlutterLiveness',
          callback: _onLivenessMessage,
        );
        // NOTE: Do NOT call clearAllCache() here — it also resets the
        // WebView's internal permission state, so AWS Liveness then sits on
        // "Waiting for you to allow camera permission" forever on the second
        // attempt. Cache-busting via the URL query param is enough.
      },
      onLoadStop: (controller, _) async {
        // Re-inject the bridge after page load — initial injection runs before
        // the React app boots, so a second pass guarantees window.FlutterLiveness
        // exists when the React code reads it.
        await controller.evaluateJavascript(source: '''
          window.FlutterLiveness = {
            postMessage: function(msg) {
              window.flutter_inappwebview.callHandler('FlutterLiveness', msg);
            }
          };
        ''');
        if (mounted) setState(() => _loading = false);
      },
      onPermissionRequest: (controller, request) async {
        // Some Android OEMs (Vivo, Xiaomi) hand us an empty resources list
        // even though the page asked for camera+mic. Always grant both so
        // the AWS Liveness flow can proceed.
        final resources = request.resources.isEmpty
            ? <PermissionResourceType>[
                PermissionResourceType.CAMERA,
                PermissionResourceType.MICROPHONE,
              ]
            : request.resources;
        return PermissionResponse(
          resources: resources,
          action: PermissionResponseAction.GRANT,
        );
      },
      onConsoleMessage: (_, msg) {
        // Visible via `adb logcat` — useful for diagnosing the AWS WebSocket
        // handshake when something breaks in the field.
        debugPrint('[Liveness console] ${msg.messageLevel}: ${msg.message}');
      },
    );
  }

  void _exit() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      context.go('/kiosk/splash');
    }
  }

  void _showAdminDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.cardBg,
        title: const Text('Settings',
            style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
        content: const Text('App mode switch karna chahte hain?',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove(AppConstants.keyMode);
              if (mounted) context.go('/mode-select');
            },
            child: const Text('Switch Mode'),
          ),
        ],
      ),
    );
  }
}
