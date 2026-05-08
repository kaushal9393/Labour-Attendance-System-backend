import 'dart:async';
import 'dart:convert';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_custom_tabs/flutter_custom_tabs.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';

/// Opens the AWS Face Liveness flow in a Chrome Custom Tab (real Chrome
/// engine, runs in-app) and waits for the result to come back via the
/// garage://liveness-done deep link the React page redirects to.
class LivenessScanScreen extends StatefulWidget {
  const LivenessScanScreen({super.key});

  @override
  State<LivenessScanScreen> createState() => _LivenessScanScreenState();
}

class _LivenessScanScreenState extends State<LivenessScanScreen> {
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;
  bool _resultHandled = false;
  bool _launching = true;

  @override
  void initState() {
    super.initState();
    _linkSub = _appLinks.uriLinkStream.listen(_onDeepLink, onError: (_) {});
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final cacheBust = DateTime.now().millisecondsSinceEpoch;
    final url =
        '${AppConstants.livenessUrl}?company_code=${AppConstants.companyCode}&t=$cacheBust';

    try {
      await launchUrl(
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
    } catch (e) {
      _failWithReason('cant_open_browser');
      return;
    }

    if (mounted) setState(() => _launching = false);
  }

  void _onDeepLink(Uri uri) {
    if (_resultHandled) return;
    if (uri.scheme != 'garage' || uri.host != 'liveness-done') return;
    _resultHandled = true;

    // Close the Chrome Custom Tab so the user lands back on this screen
    // before we route to success/failed.
    closeCustomTabs().catchError((_) {});

    final raw = uri.queryParameters['data'];
    if (raw == null) {
      _failWithReason('missing_data');
      return;
    }

    Map<String, dynamic> data;
    try {
      data = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      _failWithReason('bad_data');
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
  void dispose() {
    _linkSub?.cancel();
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
