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
  bool  _obscure     = true;

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
    if (success && mounted) context.go('/admin/dashboard');
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: AppTheme.primary,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove(AppConstants.keyMode);
            if (context.mounted) context.go('/mode-select');
          },
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),
              // Logo
              Center(
                child: Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: AppTheme.accent.withValues(alpha: 0.35), width: 2),
                  ),
                  child: const Icon(Icons.garage_rounded,
                      color: AppTheme.accent, size: 56),
                ),
              ),
              const SizedBox(height: 28),
              const Center(
                child: Text('Admin Login',
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 26,
                        fontWeight: FontWeight.bold)),
              ),
              const Center(
                child: Text('Garage Attendance System',
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 14)),
              ),
              const SizedBox(height: 44),

              // Form
              Form(
                key: _formKey,
                child: Column(children: [
                  TextFormField(
                    controller: _companyCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Company Code',
                      hintText: 'e.g. GARAGE2024',
                      prefixIcon: Icon(Icons.business),
                    ),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Enter company code' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
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
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passCtrl,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure
                            ? Icons.visibility_off
                            : Icons.visibility),
                        onPressed: () =>
                            setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Enter password' : null,
                  ),
                ]),
              ),

              if (auth.error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppTheme.error.withValues(alpha: 0.4)),
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

              const SizedBox(height: 28),
              ElevatedButton(
                onPressed: auth.isLoading ? null : _login,
                child: auth.isLoading
                    ? const SizedBox(
                        height: 20, width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Login'),
              ),

              const SizedBox(height: 32),
              TextButton(
                onPressed: () => context.go('/mode-select'),
                child: const Text('← Back to Mode Select',
                    style: TextStyle(color: AppTheme.textSecondary)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
