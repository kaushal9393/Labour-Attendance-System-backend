import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_custom_tabs/flutter_custom_tabs.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';

/// Opens the AWS Face Liveness flow in a Chrome Custom Tab and polls the
/// backend for the result. Polling is used (not deep links) because Android
/// won't reliably dispatch a custom-scheme URL back to a foreground app.
class LivenessScanScreen extends StatefulWidget {
  const LivenessScanScreen({super.key});

  @override
  State<LivenessScanScreen> createState() => _LivenessScanScreenState();
}

class _LivenessScanScreenState extends State<LivenessScanScreen> {
  Timer? _pollTimer;
  bool _resultHandled = false;
  bool _launching = true;
  String? _scanId;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // 1. Reserve a scan_id we can poll on. The web page reads it from the
    //    URL query string and includes it on /verify so the result lands in
    //    the same bucket we're watching.
    final String scanId;
    try {
      final resp = await ApiService().reserveScanId();
      scanId = resp.data['scan_id'] as String;
    } catch (_) {
      _failWithReason('cant_start_session');
      return;
    }
    _scanId = scanId;

    // 2. Open the Custom Tab with the scan_id so the React page can pass it
    //    along on /verify and we can poll on the same key.
    final cacheBust = DateTime.now().millisecondsSinceEpoch;
    final url =
        '${AppConstants.livenessUrl}?company_code=${AppConstants.companyCode}&scan_id=$scanId&t=$cacheBust';

    try {
      // launchUrl returns when the user dismisses the Custom Tab — don't await
      // it (we'd block polling). Fire-and-forget is the documented pattern.
      // ignore: unawaited_futures
      launchUrl(
        Uri.parse(url),
        customTabsOptions: CustomTabsOptions(
          colorSchemes: CustomTabsColorSchemes.defaults(
            toolbarColor: AppTheme.surface,
          ),
          shareState: CustomTabsShareState.off,
          urlBarHidingEnabled: true,
          showTitle: false,
          closeButton: CustomTabsCloseButton(
            icon: CustomTabsCloseButtonIcons.back,
          ),
        ),
      );
    } catch (_) {
      _failWithReason('cant_open_browser');
      return;
    }

    if (mounted) setState(() => _launching = false);

    // 3. Start polling. The first hit usually returns 204 (not ready).
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: 1500),
      (_) => _pollResult(),
    );
  }

  Future<void> _pollResult() async {
    if (_resultHandled || _scanId == null) return;
    try {
      final resp = await ApiService().getLivenessResult(_scanId!);
      if (resp.statusCode == 204 || resp.data == null || resp.data == '') {
        return; // not ready yet
      }
      if (resp.statusCode != 200) return;
      final data = (resp.data as Map).cast<String, dynamic>();
      _handleResult(data);
    } catch (_) {
      // Network blip — keep polling.
    }
  }

  void _handleResult(Map<String, dynamic> data) {
    if (_resultHandled) return;
    _resultHandled = true;
    _pollTimer?.cancel();

    // Bring the user back to the app from the Custom Tab.
    closeCustomTabs().catchError((_) {});

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
    _pollTimer?.cancel();
    if (!mounted) return;
    context.go('/kiosk/failed');
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: AppTheme.accentLight,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.accent, width: 2),
                      ),
                      child: const Icon(Icons.face_retouching_natural,
                          color: AppTheme.accent, size: 56),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      _launching ? 'Camera khul raha hai…' : 'Face scan jaari hai',
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Apna chehra oval ke andar rakho.\n'
                      'Screen pe rang flash honge — bilkul mat hilo.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 32),
                    const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        color: AppTheme.accent,
                        strokeWidth: 3,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Scan complete hone par yahan automatic vaapas aa jaaoge',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 36),
                    OutlinedButton.icon(
                      onPressed: _exit,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textSecondary,
                        side: const BorderSide(color: AppTheme.divider),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.settings,
                    color: AppTheme.textSecondary),
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
            style: TextStyle(
                color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
        content: const Text('App mode switch karna chahte hain?',
            style:
                TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
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
