import 'package:flutter/material.dart';
import '../../core/theme.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Help & About'),
        backgroundColor: AppTheme.surface,
        elevation: 0,
        foregroundColor: AppTheme.textPrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          // App identity card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Row(children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppTheme.accentLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.garage_rounded,
                    color: AppTheme.accent, size: 32),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('FaceScan',
                        style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w800)),
                    SizedBox(height: 2),
                    Text('Version 1.0.0',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 13)),
                    SizedBox(height: 2),
                    Text('Powered by AWS Rekognition',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 11)),
                  ],
                ),
              ),
            ]),
          ),
          const SizedBox(height: 24),

          _faqHeader('Getting Started'),
          const _Faq(
            q: 'How do I add employees?',
            a: 'Go to Employees tab → tap + button → fill in name, phone, role '
                'and salary, then scan their face 3–5 times from different angles.',
          ),
          const _Faq(
            q: 'How does face attendance work?',
            a: 'The kiosk opens a face-scan screen. The employee looks at the '
                'camera, passes a liveness check (to prevent photo spoofing), '
                'and the system matches their face against registered employees.',
          ),
          const _Faq(
            q: 'What is the company code?',
            a: 'Your unique company code (e.g. MEHTA-AUTO) identifies your '
                'garage. It is used to connect the kiosk with your account. '
                'You set it once during signup.',
          ),
          const _Faq(
            q: 'How do I set up kiosk mode?',
            a: '1. Sign up / login as Owner/Admin first.\n'
                '2. Go back to the home screen and tap "Employee Check-In".\n'
                'The kiosk will use your saved company code automatically.',
          ),

          const SizedBox(height: 8),
          _faqHeader('Admin PIN'),
          const _Faq(
            q: 'What is the Admin PIN?',
            a: 'A 6-digit shortcut to log back in quickly without typing your '
                'full email and password. You set it the first time you log in.',
          ),
          const _Faq(
            q: 'I forgot my PIN. What do I do?',
            a: 'On the PIN screen, tap "Full login karo" at the bottom. This '
                'clears the PIN and lets you log in with email + password. '
                'You can set a new PIN after logging in.',
          ),

          const SizedBox(height: 8),
          _faqHeader('Attendance & Reports'),
          const _Faq(
            q: 'What is the attendance window?',
            a: 'Scans outside the check-in or check-out window are rejected. '
                'Configure the window in Settings → Attendance Window.',
          ),
          const _Faq(
            q: 'How is salary calculated?',
            a: 'Monthly salary = (daily rate × days present). Daily rate = '
                'monthly salary ÷ working days in the month. You can override '
                'working days per month in Settings.',
          ),
          const _Faq(
            q: 'Can I manually check out an employee?',
            a: 'Yes. Go to Attendance tab → tap the employee → Manual Checkout. '
                'This is useful if someone forgot to scan their face before leaving.',
          ),

          const SizedBox(height: 8),
          _faqHeader('Troubleshooting'),
          const _Faq(
            q: 'Face not recognised?',
            a: '• Make sure the employee was registered with clear, well-lit photos.\n'
                '• Try registering again with more angle variations.\n'
                '• Ensure the camera is not covered and lighting is adequate.',
          ),
          const _Faq(
            q: 'Liveness check keeps failing?',
            a: '• Hold the phone steady at eye level.\n'
                '• Ensure there is enough light on your face.\n'
                '• Remove glasses if possible for first-time registration.',
          ),
          const _Faq(
            q: 'App is slow or not connecting?',
            a: 'Check your internet connection. The app requires internet '
                'for face scanning and syncing records.',
          ),

          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.accentLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.accent.withValues(alpha: 0.25)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.mail_outline, color: AppTheme.accent, size: 18),
                  SizedBox(width: 8),
                  Text('Contact Support',
                      style: TextStyle(
                          color: AppTheme.accent,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                ]),
                SizedBox(height: 6),
                Text(
                  'support@garageattendance.app',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _faqHeader(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          title,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

class _Faq extends StatefulWidget {
  final String q;
  final String a;
  const _Faq({required this.q, required this.a});

  @override
  State<_Faq> createState() => _FaqState();
}

class _FaqState extends State<_Faq> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _open = !_open),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(
                    widget.q,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  _open ? Icons.expand_less : Icons.expand_more,
                  color: AppTheme.textSecondary,
                  size: 20,
                ),
              ]),
              if (_open) ...[
                const SizedBox(height: 8),
                Text(
                  widget.a,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
