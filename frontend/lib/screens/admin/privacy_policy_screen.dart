import 'package:flutter/material.dart';
import '../../core/theme.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Privacy Policy'),
        backgroundColor: AppTheme.surface,
        elevation: 0,
        foregroundColor: AppTheme.textPrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: const [
          _Section(
            title: 'Last updated: May 2025',
            body: 'Garage Attendance ("we", "our", or "us") is committed to '
                'protecting your privacy. This policy explains what data we '
                'collect and how we use it.',
          ),
          _Section(
            title: '1. Data We Collect',
            body: '• Employee face images (used only for attendance verification)\n'
                '• Employee name, phone number, and role\n'
                '• Attendance timestamps (check-in / check-out)\n'
                '• Admin email address and encrypted password\n'
                '• Company name and unique company code',
          ),
          _Section(
            title: '2. How We Use Your Data',
            body: '• Face images are processed by AWS Rekognition to verify '
                'employee identity. Images are stored securely in AWS and '
                'are never sold or shared with third parties.\n'
                '• Attendance records are used to generate salary and '
                'monthly reports for your garage.\n'
                '• Admin credentials are used only for authentication.',
          ),
          _Section(
            title: '3. Data Storage & Security',
            body: '• All data is stored in encrypted databases (Neon PostgreSQL '
                'hosted on Railway).\n'
                '• Face collections are stored in AWS Rekognition (ap-south-1 '
                'region) and are isolated per company.\n'
                '• We use HTTPS for all data in transit.',
          ),
          _Section(
            title: '4. Data Retention',
            body: '• Attendance records are kept for as long as your account '
                'is active.\n'
                '• You can delete an employee\'s face data at any time from '
                'the Employees screen.\n'
                '• Deleting your account removes all associated company data.',
          ),
          _Section(
            title: '5. Third-Party Services',
            body: '• AWS Rekognition — face detection and liveness verification\n'
                '• Firebase — push notifications\n'
                '• Railway / Neon — cloud hosting and database\n\n'
                'These services have their own privacy policies.',
          ),
          _Section(
            title: '6. Your Rights',
            body: 'You may request access to, correction of, or deletion of '
                'any personal data we hold about you by contacting us at '
                'support@garageattendance.app.',
          ),
          _Section(
            title: '7. Changes to This Policy',
            body: 'We may update this policy from time to time. The latest '
                'version will always be available in the app.',
          ),
          _Section(
            title: '8. Contact',
            body: 'Questions? Reach us at support@garageattendance.app',
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
