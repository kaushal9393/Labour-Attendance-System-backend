import 'package:flutter/material.dart';
import '../../core/theme.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Terms of Service'),
        backgroundColor: AppTheme.surface,
        elevation: 0,
        foregroundColor: AppTheme.textPrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: const [
          _Section(
            title: 'Last updated: May 2025',
            body: 'By using Garage Attendance you agree to these Terms of '
                'Service. Please read them carefully.',
          ),
          _Section(
            title: '1. Acceptance of Terms',
            body: 'Using the app means you accept these terms. If you do not '
                'agree, please uninstall the app and discontinue use.',
          ),
          _Section(
            title: '2. Account Responsibilities',
            body: '• You are responsible for keeping your admin password and '
                'PIN secure.\n'
                '• You must not share your login credentials with '
                'unauthorised persons.\n'
                '• You are responsible for all activity that occurs under '
                'your account.',
          ),
          _Section(
            title: '3. Permitted Use',
            body: 'Garage Attendance is licensed for legitimate employee '
                'attendance tracking at your garage or workshop. You may not '
                'use the app to:\n'
                '• Track individuals without their knowledge or consent\n'
                '• Circumvent biometric consent laws in your jurisdiction\n'
                '• Resell or redistribute the service',
          ),
          _Section(
            title: '4. Biometric Data',
            body: 'Employee face data is collected and processed with the '
                'employee\'s knowledge for attendance purposes only. As the '
                'account owner, you are responsible for obtaining appropriate '
                'consent from your employees in accordance with local laws.',
          ),
          _Section(
            title: '5. Service Availability',
            body: 'We aim for high availability but do not guarantee '
                'uninterrupted service. We are not liable for any losses '
                'caused by downtime or data unavailability.',
          ),
          _Section(
            title: '6. Termination',
            body: 'We reserve the right to suspend or terminate accounts that '
                'violate these terms. You may delete your account at any time '
                'from the Settings screen.',
          ),
          _Section(
            title: '7. Limitation of Liability',
            body: 'To the fullest extent permitted by law, Garage Attendance '
                'shall not be liable for indirect, incidental, or '
                'consequential damages arising from your use of the app.',
          ),
          _Section(
            title: '8. Governing Law',
            body: 'These terms are governed by the laws of India. Disputes '
                'shall be resolved in courts of competent jurisdiction.',
          ),
          _Section(
            title: '9. Contact',
            body: 'Questions about these terms? Email us at '
                'support@garageattendance.app',
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String body;
  const _Section({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
