import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';

/// Hosts the AWS Face Liveness web flow inside a WebView and routes the
/// final verify result to the existing success/failed screens.
class LivenessScanScreen extends StatefulWidget {
  const LivenessScanScreen({super.key});

  @override
  State<LivenessScanScreen> createState() => _LivenessScanScreenState();
}

class _LivenessScanScreenState extends State<LivenessScanScreen> {
  late final WebViewController _controller;
  bool _resultHandled = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final granted = await Permission.camera.request();
    if (!granted.isGranted) {
      _failWithReason('camera_permission_denied');
      return;
    }

    const url = '${AppConstants.livenessUrl}?company_code=${AppConstants.companyCode}';

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel(
        'FlutterLiveness',
        onMessageReceived: _onLivenessMessage,
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
        onWebResourceError: (err) {
          // Only treat top-level navigation failures as fatal — sub-resource
          // errors (e.g. analytics) should not break the flow.
          if (err.isForMainFrame ?? false) {
            _failWithReason('webview_load_error');
          }
        },
      ))
      ..loadRequest(Uri.parse(url));

    if (mounted) setState(() {});
  }

  void _onLivenessMessage(JavaScriptMessage msg) {
    if (_resultHandled) return;
    _resultHandled = true;

    Map<String, dynamic> data;
    try {
      data = jsonDecode(msg.message) as Map<String, dynamic>;
    } catch (_) {
      _failWithReason('bad_response');
      return;
    }

    HapticFeedback.mediumImpact();

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
            WebViewWidget(controller: _controller),
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
                onPressed: () => _exit(),
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
