import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/constants.dart';

/// Drop-in "About" section for the profile screens of every role. Provides:
///  • An "Open-source licenses" tile that opens Flutter's built-in
///    [showLicensePage] — this aggregates the license text of every bundled
///    package, satisfying the attribution clauses of MIT/BSD/Apache deps.
///  • A copyright + version footer.
///
/// Copyright on the work is automatic, but reproducing the open-source
/// attributions is a real obligation, so this section keeps both visible in
/// one place across the app.
class AppAboutSection extends StatelessWidget {
  const AppAboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            'About',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: const Text('Open-source licenses'),
          trailing: const Icon(Icons.chevron_right, size: 18),
          onTap: () => showLicensePage(
            context: context,
            applicationName: AppConstants.appName,
            applicationVersion: 'Version ${AppConstants.appVersion}',
            applicationLegalese: AppConstants.copyright,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                AppConstants.copyright,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Version ${AppConstants.appVersion}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
