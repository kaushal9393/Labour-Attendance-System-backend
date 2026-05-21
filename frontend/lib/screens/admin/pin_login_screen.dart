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
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPin);
    if (mounted) context.go('/admin/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final h = constraints.maxHeight;
            final w = constraints.maxWidth;
            final compact = h < 700;
            final hPad = w >= 600 ? ((w - 360) / 2).clamp(48.0, 160.0) : 48.0;

            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: hPad),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: h),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      SizedBox(height: compact ? 32 : 56),

                      Container(
                        width: compact ? 72 : 88,
                        height: compact ? 72 : 88,
                        decoration: BoxDecoration(
                          color: AppTheme.accentLight,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: AppTheme.accent.withValues(alpha: 0.25), width: 2),
                        ),
                        child: Icon(Icons.lock_rounded,
                            color: AppTheme.accent, size: compact ? 36 : 44),
                      ),
                      SizedBox(height: compact ? 12 : 20),

                      Text('Admin PIN', style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: compact ? 22 : 26,
                          fontWeight: FontWeight.w800)),
                      SizedBox(height: compact ? 4 : 8),
                      const Text('6-digit PIN daalo', style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 14)),
                      SizedBox(height: compact ? 24 : 40),

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
                      SizedBox(height: compact ? 8 : 16),

                      SizedBox(
                        height: 20,
                        child: Text(_error,
                            style: const TextStyle(color: AppTheme.error, fontSize: 13)),
                      ),
                      SizedBox(height: compact ? 12 : 24),

                      // Keypad
                      if (_loading)
                        const CircularProgressIndicator(color: AppTheme.accent)
                      else
                        Column(
                          children: [
                            _keyRow(['1', '2', '3'], compact),
                            SizedBox(height: compact ? 8 : 16),
                            _keyRow(['4', '5', '6'], compact),
                            SizedBox(height: compact ? 8 : 16),
                            _keyRow(['7', '8', '9'], compact),
                            SizedBox(height: compact ? 8 : 16),
                            Row(children: [
                              const Expanded(child: SizedBox()),
                              Expanded(child: _keyButton('0', compact)),
                              Expanded(
                                child: GestureDetector(
                                  onTap: _onDelete,
                                  child: SizedBox(
                                    height: compact ? 48 : 64,
                                    child: const Icon(Icons.backspace_outlined,
                                        color: AppTheme.textPrimary, size: 28),
                                  ),
                                ),
                              ),
                            ]),
                          ],
                        ),

                      const Spacer(),
                      TextButton(
                        onPressed: _goFullLogin,
                        child: const Text('Full login karo',
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                      ),
                      SizedBox(height: compact ? 12 : 24),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _keyRow(List<String> digits, bool compact) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: digits.map((d) => Expanded(child: _keyButton(d, compact))).toList(),
    );
  }

  Widget _keyButton(String digit, bool compact) {
    return GestureDetector(
      onTap: () => _onKey(digit),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        height: compact ? 48 : 64,
        decoration: BoxDecoration(
          color: AppTheme.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.divider),
        ),
        alignment: Alignment.center,
        child: Text(digit, style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: compact ? 20 : 24,
            fontWeight: FontWeight.w600)),
      ),
    );
  }
}
