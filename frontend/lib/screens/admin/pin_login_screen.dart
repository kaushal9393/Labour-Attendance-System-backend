import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';

class PinLoginScreen extends ConsumerStatefulWidget {
  const PinLoginScreen({super.key});

  @override
  ConsumerState<PinLoginScreen> createState() => _PinLoginScreenState();
}

class _PinLoginScreenState extends ConsumerState<PinLoginScreen> {
  static const _kPin   = 'admin_pin';
  static const _kEmail = 'saved_email';
  static const _kPass  = 'saved_password';

  String _entered = '';
  String _error   = '';
  bool   _loading = false;

  void _onKey(String digit) {
    if (_entered.length >= 6) return;
    setState(() { _entered += digit; _error = ''; });
    if (_entered.length == 6) _verify();
  }

  void _onDelete() {
    if (_entered.isEmpty) return;
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  Future<void> _verify() async {
    setState(() => _loading = true);
    final prefs   = await SharedPreferences.getInstance();
    final savedPin = prefs.getString(_kPin) ?? '';

    if (_entered != savedPin) {
      setState(() { _entered = ''; _error = 'Galat PIN — dobara try karo'; _loading = false; });
      return;
    }

    // PIN correct — auto-login with saved credentials
    final email = prefs.getString(_kEmail) ?? '';
    final pass  = prefs.getString(_kPass)  ?? '';

    final success = await ref.read(authProvider.notifier).login(
      email:    email,
      password: pass,
    );

    if (!mounted) return;
    if (success) {
      context.go('/admin/dashboard');
    } else {
      setState(() { _entered = ''; _error = 'Login fail hua — Full login karo'; _loading = false; });
    }
  }

  Future<void> _goFullLogin() async {
    // Clear only the PIN so login screen doesn't redirect back here.
    // Credentials stay so fields are pre-filled; PIN setup dialog shows again after login.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPin);
    if (mounted) context.go('/admin/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 60),

            // Icon
            Container(
              width: 88, height: 88,
              decoration: BoxDecoration(
                color: AppTheme.accentLight,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.accent.withValues(alpha: 0.25), width: 2),
              ),
              child: const Icon(Icons.lock_rounded, color: AppTheme.accent, size: 44),
            ),
            const SizedBox(height: 20),

            const Text('Admin PIN', style: TextStyle(
              color: AppTheme.textPrimary, fontSize: 26, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('6-digit PIN daalo', style: TextStyle(
              color: AppTheme.textSecondary, fontSize: 14)),
            const SizedBox(height: 40),

            // PIN dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (i) {
                final filled = i < _entered.length;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  width: 18, height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled ? AppTheme.accent : Colors.transparent,
                    border: Border.all(
                      color: filled ? AppTheme.accent : AppTheme.textSecondary,
                      width: 2,
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 16),

            // Error
            SizedBox(
              height: 20,
              child: Text(_error, style: const TextStyle(color: AppTheme.error, fontSize: 13)),
            ),
            const SizedBox(height: 24),

            // Keypad
            if (_loading)
              const CircularProgressIndicator(color: AppTheme.accent)
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: Column(
                  children: [
                    _keyRow(['1', '2', '3']),
                    const SizedBox(height: 16),
                    _keyRow(['4', '5', '6']),
                    const SizedBox(height: 16),
                    _keyRow(['7', '8', '9']),
                    const SizedBox(height: 16),
                    Row(children: [
                      const Expanded(child: SizedBox()),
                      Expanded(child: _keyButton('0')),
                      Expanded(
                        child: GestureDetector(
                          onTap: _onDelete,
                          child: const Icon(Icons.backspace_outlined,
                              color: AppTheme.textPrimary, size: 28),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),

            const Spacer(),
            TextButton(
              onPressed: _goFullLogin,
              child: const Text('Full login karo',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _keyRow(List<String> digits) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: digits.map((d) => Expanded(child: _keyButton(d))).toList(),
    );
  }

  Widget _keyButton(String digit) {
    return GestureDetector(
      onTap: () => _onKey(digit),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        height: 64,
        decoration: BoxDecoration(
          color: AppTheme.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.divider),
        ),
        alignment: Alignment.center,
        child: Text(digit, style: const TextStyle(
          color: AppTheme.textPrimary, fontSize: 24, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
