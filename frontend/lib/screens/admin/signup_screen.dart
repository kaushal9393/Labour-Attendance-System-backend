import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';

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

  bool   _obscure      = true;
  bool   _codeEdited   = false; // user manually edited code → stop auto-gen
  Timer? _codeDebounce;
  String? _codeStatus; // 'available' | 'taken' | 'checking' | null

  @override
  void initState() {
    super.initState();
    _businessCtrl.addListener(_onBusinessChanged);
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

  // Auto-generate company code from business name
  void _onBusinessChanged() {
    if (_codeEdited) return;
    final raw = _businessCtrl.text.trim().toUpperCase();
    final generated = raw
        .replaceAll(RegExp(r'[^A-Z0-9 ]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '-');
    final clipped = generated.length > 20
        ? generated.substring(0, 20)
        : generated;
    _codeCtrl.removeListener(_onCodeChanged);
    _codeCtrl.text = clipped;
    _codeCtrl.selection =
        TextSelection.collapsed(offset: clipped.length);
    _codeCtrl.addListener(_onCodeChanged);
    _scheduleCodeCheck(clipped);
  }

  void _onCodeChanged() {
    // If user typed something different from auto-gen, lock it
    final businessGen = _businessCtrl.text.trim().toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9 ]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '-');
    if (_codeCtrl.text != businessGen) _codeEdited = true;
    _scheduleCodeCheck(_codeCtrl.text.trim());
  }

  void _scheduleCodeCheck(String code) {
    _codeDebounce?.cancel();
    if (code.length < 4) {
      setState(() => _codeStatus = null);
      return;
    }
    setState(() => _codeStatus = 'checking');
    _codeDebounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final resp = await ApiService().checkCompanyCode(code.toUpperCase());
        if (!mounted) return;
        final data = resp.data as Map<String, dynamic>;
        setState(() =>
            _codeStatus = (data['available'] == true) ? 'available' : 'taken');
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
          onPressed: () => context.go('/welcome'),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          final isTablet = constraints.maxWidth >= 600;
          final hPad = isTablet
              ? ((constraints.maxWidth - 500) / 2).clamp(32.0, 120.0)
              : 24.0;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: AppTheme.accentLight,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: AppTheme.accent.withValues(alpha: 0.3), width: 2),
                  ),
                  child: const Icon(Icons.add_business_rounded,
                      color: AppTheme.accent, size: 38),
                ),
              ),
              const SizedBox(height: 16),
              const Center(
                child: Text('Create your account',
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5)),
              ),
              const SizedBox(height: 4),
              const Center(
                child: Text('Set up your garage in under a minute',
                    style:
                        TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              ),
              const SizedBox(height: 28),

              // ── Business section ──────────────────────────────
              _SectionLabel(icon: Icons.storefront_outlined, label: 'Business'),
              const SizedBox(height: 10),

              Form(
                key: _formKey,
                child: Column(
                  children: [
                    _Field(
                      controller: _businessCtrl,
                      label: 'Business name',
                      hint: 'Mehta Auto Garage',
                      icon: Icons.storefront_outlined,
                      caps: TextCapitalization.words,
                      validator: (v) => (v == null || v.trim().length < 2)
                          ? 'Business name required'
                          : null,
                    ),
                    const SizedBox(height: 12),

                    // Company code with availability badge
                    TextFormField(
                      controller: _codeCtrl,
                      textCapitalization: TextCapitalization.characters,
                      style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1),
                      inputFormatters: [
                        UpperCaseTextFormatter(),
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[A-Z0-9_-]')),
                        LengthLimitingTextInputFormatter(20),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Company code',
                        hintText: 'MEHTA-AUTO',
                        prefixIcon: const Icon(Icons.tag_rounded),
                        suffixIcon: _codeSuffixIcon(),
                        helperText: 'Auto-generated · tap to edit',
                        helperStyle: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 11),
                        filled: true,
                        fillColor: AppTheme.cardBg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide:
                              const BorderSide(color: AppTheme.divider),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide:
                              const BorderSide(color: AppTheme.divider),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                              color: AppTheme.accent, width: 1.5),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide:
                              const BorderSide(color: AppTheme.error),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                              color: AppTheme.error, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                      ),
                      validator: (v) {
                        if (v == null || v.length < 4) {
                          return 'Min 4 characters';
                        }
                        if (_codeStatus == 'taken') return 'Already taken — try another';
                        return null;
                      },
                    ),

                    const SizedBox(height: 24),
                    _SectionLabel(
                        icon: Icons.person_outline, label: 'Owner details'),
                    const SizedBox(height: 10),

                    _Field(
                      controller: _ownerCtrl,
                      label: 'Your name',
                      hint: 'Ramesh Mehta',
                      icon: Icons.person_outline,
                      caps: TextCapitalization.words,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Name required' : null,
                    ),
                    const SizedBox(height: 12),
                    _Field(
                      controller: _emailCtrl,
                      label: 'Email address',
                      hint: 'ramesh@example.com',
                      icon: Icons.email_outlined,
                      keyboard: TextInputType.emailAddress,
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Email required';
                        if (!v.contains('@') || !v.contains('.')) {
                          return 'Enter a valid email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    _Field(
                      controller: _phoneCtrl,
                      label: 'Phone number',
                      hint: '9876543210',
                      icon: Icons.phone_outlined,
                      keyboard: TextInputType.phone,
                      formatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(15),
                      ],
                      validator: (v) => (v == null || v.trim().length < 7)
                          ? 'Enter a valid number'
                          : null,
                    ),
                    const SizedBox(height: 12),

                    // Password
                    TextFormField(
                      controller: _passCtrl,
                      obscureText: _obscure,
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        hintText: 'Min 8 characters',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: AppTheme.textSecondary,
                            size: 20,
                          ),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                        ),
                        filled: true,
                        fillColor: AppTheme.cardBg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide:
                              const BorderSide(color: AppTheme.divider),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide:
                              const BorderSide(color: AppTheme.divider),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                              color: AppTheme.accent, width: 1.5),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide:
                              const BorderSide(color: AppTheme.error),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                              color: AppTheme.error, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                      ),
                      validator: (v) => (v == null || v.length < 8)
                          ? 'Min 8 characters'
                          : null,
                    ),
                  ],
                ),
              ),

              // Error banner
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

              const SizedBox(height: 24),

              // Submit button
              SizedBox(
                height: 54,
                child: ElevatedButton(
                  onPressed: auth.isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: auth.isLoading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white))
                      : const Text('Create Account',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                ),
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
            ],
            ),
          );
        }),
      ),
    );
  }

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
        return const Icon(Icons.check_circle_rounded,
            color: AppTheme.accent, size: 22);
      case 'taken':
        return const Icon(Icons.cancel_rounded,
            color: AppTheme.error, size: 22);
    }
    return null;
  }
}

// ── Reusable field ───────────────────────────────────────────────
class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType keyboard;
  final TextCapitalization caps;
  final List<TextInputFormatter> formatters;
  final String? Function(String?)? validator;

  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboard = TextInputType.text,
    this.caps = TextCapitalization.none,
    this.formatters = const [],
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboard,
      textCapitalization: caps,
      inputFormatters: formatters,
      style: const TextStyle(color: AppTheme.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle:
            const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        prefixIcon: Icon(icon, size: 20),
        filled: true,
        fillColor: AppTheme.cardBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppTheme.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppTheme.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppTheme.accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppTheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: AppTheme.error, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      validator: validator,
    );
  }
}

// ── Section label ────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 15, color: AppTheme.accent),
      const SizedBox(width: 6),
      Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: AppTheme.accent,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    ]);
  }
}

// ── Formatters ───────────────────────────────────────────────────
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
          TextEditingValue o, TextEditingValue n) =>
      n.copyWith(text: n.text.toUpperCase());
}
