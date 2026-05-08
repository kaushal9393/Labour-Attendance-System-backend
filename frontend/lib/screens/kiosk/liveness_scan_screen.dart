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
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: AppTheme.accent),
                  const SizedBox(height: 24),
                  Text(
                    _launching
                        ? 'Opening liveness scan…'
                        : 'Complete the scan in the browser…',
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      'When you finish, this screen will continue automatically.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: AppTheme.textPrimary),
                onPressed: _exit,
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.settings, color: AppTheme.textSecondary),
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
