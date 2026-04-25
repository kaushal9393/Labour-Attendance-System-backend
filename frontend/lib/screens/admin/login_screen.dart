import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme.dart';
import '../../core/constants.dart';
import '../../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey     = GlobalKey<FormState>();
  final _companyCtrl = TextEditingController();
  final _emailCtrl   = TextEditingController();
  final _passCtrl    = TextEditingController();
  bool  _obscure             = true;
  bool  _rememberMe          = false;
  bool  _hasSavedCredentials = false;

  static const String _kCompany = 'saved_company_code';
  static const String _kEmail   = 'saved_email';
  static const String _kPass    = 'saved_password';

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final prefs   = await SharedPreferences.getInstance();
    final company = prefs.getString(_kCompany);
    final email   = prefs.getString(_kEmail);
    final pass    = prefs.getString(_kPass);
    if (company != null && email != null && pass != null) {
      setState(() {
        _companyCtrl.text     = company;
        _emailCtrl.text       = email;
        _passCtrl.text        = pass;
        _rememberMe           = true;
        _hasSavedCredentials  = true;
      });
    }
  }

  Future<void> _clearSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCompany);
    await prefs.remove(_kEmail);
    await prefs.remove(_kPass);
    setState(() {
      _companyCtrl.clear();
      _emailCtrl.clear();
      _passCtrl.clear();
      _rememberMe          = false;
      _hasSavedCredentials = false;
    });
  }

  @override
  void dispose() {
    _companyCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    final success = await ref.read(authProvider.notifier).login(
          companyCode: _companyCtrl.text.trim(),
          email:       _emailCtrl.text.trim(),
          password:    _passCtrl.text,
        );
    if (!mounted) return;
    if (success) {
      final prefs = await SharedPreferences.getInstance();
      if (_rememberMe) {
        await prefs.setString(_kCompany, _companyCtrl.text.trim());
        await prefs.setString(_kEmail,   _emailCtrl.text.trim());
        await prefs.setString(_kPass,    _passCtrl.text);
      } else {
        await prefs.remove(_kCompany);
        await prefs.remove(_kEmail);
        await prefs.remove(_kPass);
      }
      if (mounted) context.go('/admin/dashboard');
    }
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
          icon: const Icon(Icons.arrow_back_ios_new, color: AppTheme.textPrimary, size: 20),
          onPressed: () async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove(AppConstants.keyMode);
            if (context.mounted) context.go('/mode-select');
          },
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),

              // Logo circle
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: AppTheme.accentLight,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.accent.withValues(alpha: 0.25), width: 2),
                  ),
                  child: const Icon(Icons.garage_rounded, color: AppTheme.accent, size: 44),
                ),
              ),
              const SizedBox(height: 20),

              const Center(
                child: Text('Welcome Back',
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5)),
              ),
              const SizedBox(height: 6),
              const Center(
                child: Text('Sign in to your admin account',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
              ),
              const SizedBox(height: 36),

              // Card form
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.cardBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.divider),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(children: [
                    TextFormField(
                      controller: _companyCtrl,
                      textCapitalization: TextCapitalization.characters,
                      style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w500),
                      decoration: const InputDecoration(
                        labelText: 'Company Code',
                        hintText: 'e.g. GARAGE2024',
                        prefixIcon: Icon(Icons.business_outlined),
                      ),
                      validator: (v) => v == null || v.isEmpty ? 'Enter company code' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Enter email';
                        if (!v.contains('@')) return 'Enter valid email';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _passCtrl,
                      obscureText: _obscure,
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            color: AppTheme.textSecondary,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) => v == null || v.isEmpty ? 'Enter password' : null,
                    ),
                    const SizedBox(height: 8),

                    // Remember me
                    Row(children: [
                      Transform.scale(
                        scale: 0.9,
                        child: Checkbox(
                          value: _rememberMe,
                          activeColor: AppTheme.accent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          onChanged: (v) => setState(() => _rememberMe = v ?? false),
                        ),
                      ),
                      const Text('Remember me',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                      if (_hasSavedCredentials) ...[
                        const Spacer(),
                        TextButton(
                          onPressed: _clearSavedCredentials,
                          style: TextButton.styleFrom(
                              padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
                          child: const Text('Clear saved',
                              style: TextStyle(color: AppTheme.error, fontSize: 12)),
                        ),
                      ],
                    ]),
                  ]),
                ),
              ),

              // Error
              if (auth.error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.errorLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline, color: AppTheme.error, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(auth.error!,
                          style: const TextStyle(color: AppTheme.error, fontSize: 13)),
                    ),
                  ]),
                ),
              ],

              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: auth.isLoading ? null : _login,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 54),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: auth.isLoading
                    ? const SizedBox(
                        height: 22, width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : const Text('Sign In', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),

              const SizedBox(height: 20),
              Center(
                child: TextButton(
                  onPressed: () => context.go('/mode-select'),
                  child: const Text('← Back to Mode Select',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
