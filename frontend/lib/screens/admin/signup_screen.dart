import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';

/// Self-service signup for new garage owners. Creates the company + first
/// admin user in one call and drops the user straight onto the dashboard.
class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey      = GlobalKey<FormState>();
  final _businessCtrl = TextEditingController();
  final _codeCtrl     = TextEditingController();
  final _ownerCtrl    = TextEditingController();
  final _emailCtrl    = TextEditingController();
  final _phoneCtrl    = TextEditingController();
  final _passCtrl     = TextEditingController();

  bool _obscure = true;
  Timer? _codeDebounce;

  // Code availability state
  String? _codeStatus;       // 'available' | 'taken' | 'checking' | null

  @override
  void initState() {
    super.initState();
    _codeCtrl.addListener(_onCodeChanged);
  }

  @override
  void dispose() {
    _codeDebounce?.cancel();
    _businessCtrl.dispose();
    _codeCtrl.dispose();
    _ownerCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _onCodeChanged() {
    _codeDebounce?.cancel();
    final raw = _codeCtrl.text.trim().toUpperCase();
    if (raw.length < 4) {
      setState(() => _codeStatus = null);
      return;
    }
    setState(() => _codeStatus = 'checking');
    _codeDebounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final resp = await ApiService().checkCompanyCode(raw);
        if (!mounted) return;
        final data = resp.data as Map<String, dynamic>;
        setState(() {
          _codeStatus = (data['available'] == true) ? 'available' : 'taken';
        });
      } catch (_) {
        if (mounted) setState(() => _codeStatus = null);
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_codeStatus == 'taken') return;

    final ok = await ref.read(authProvider.notifier).signup(
      businessName: _businessCtrl.text.trim(),
      companyCode:  _codeCtrl.text.trim().toUpperCase(),
      ownerName:    _ownerCtrl.text.trim(),
      email:        _emailCtrl.text.trim(),
      phone:        _phoneCtrl.text.trim(),
      password:     _passCtrl.text,
    );
    if (!mounted) return;
    if (ok) context.go('/admin/dashboard');
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: AppTheme.textPrimary, size: 20),
          onPressed: () => context.go('/admin/login'),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppTheme.accentLight,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: AppTheme.accent.withValues(alpha: 0.25),
                        width: 2),
                  ),
                  child: const Icon(Icons.add_business_rounded,
                      color: AppTheme.accent, size: 36),
                ),
              ),
              const SizedBox(height: 16),
              const Center(
                  child: Text('Create your account',
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5))),
              const SizedBox(height: 4),
              const Center(
                  child: Text('Set up your garage in under a minute',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 13))),
              const SizedBox(height: 24),

              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.cardBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.divider),
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      _label('Business'),
                      TextFormField(
                        controller: _businessCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Business name',
                          hintText: 'Mehta Auto Garage',
                          prefixIcon: Icon(Icons.storefront_outlined),
                        ),
                        validator: (v) =>
                            (v == null || v.trim().length < 2) ? 'Required' : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _codeCtrl,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [
                          UpperCaseTextFormatter(),
                          FilteringTextInputFormatter.allow(
                              RegExp(r'[A-Z0-9_-]')),
                          LengthLimitingTextInputFormatter(20),
                        ],
                        decoration: InputDecoration(
                          labelText: 'Company code',
                          hintText: 'MEHTA-AUTO',
                          helperText:
                              '4-20 chars · letters, digits, - or _ · used in kiosk URL',
                          prefixIcon: const Icon(Icons.tag),
                          suffixIcon: _codeSuffixIcon(),
                        ),
                        validator: (v) {
                          if (v == null || v.length < 4) return 'Min 4 characters';
                          if (_codeStatus == 'taken') return 'Already taken';
                          return null;
                        },
                      ),

                      const SizedBox(height: 22),
                      _label('Owner'),
                      TextFormField(
                        controller: _ownerCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Your name',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Required'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Required';
                          if (!v.contains('@') || !v.contains('.')) {
                            return 'Enter a valid email';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(15),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Phone',
                          prefixIcon: Icon(Icons.phone_outlined),
                        ),
                        validator: (v) =>
                            (v == null || v.trim().length < 7)
                                ? 'Enter a valid number'
                                : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _passCtrl,
                        obscureText: _obscure,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          helperText: 'At least 8 characters',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(
                                _obscure
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: AppTheme.textSecondary),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (v) =>
                            (v == null || v.length < 8) ? 'Min 8 characters' : null,
                      ),
                    ],
                  ),
                ),
              ),

              if (auth.error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.errorLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppTheme.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline,
                        color: AppTheme.error, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(auth.error!,
                          style: const TextStyle(
                              color: AppTheme.error, fontSize: 13)),
                    ),
                  ]),
                ),
              ],

              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: auth.isLoading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 54),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: auth.isLoading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white))
                    : const Text('Create account',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
              ),

              const SizedBox(height: 18),
              Center(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text('Already have an account? ',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 13)),
                    TextButton(
                      onPressed: () => context.go('/admin/login'),
                      style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 32)),
                      child: const Text('Sign in',
                          style: TextStyle(
                              color: AppTheme.accent,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            text,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ),
      );

  Widget? _codeSuffixIcon() {
    switch (_codeStatus) {
      case 'checking':
        return const Padding(
          padding: EdgeInsets.all(14),
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppTheme.textSecondary),
          ),
        );
      case 'available':
        return const Icon(Icons.check_circle, color: AppTheme.accent);
      case 'taken':
        return const Icon(Icons.cancel, color: AppTheme.error);
    }
    return null;
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) =>
      TextEditingValue(
        text: newValue.text.toUpperCase(),
        selection: newValue.selection,
      );
}
