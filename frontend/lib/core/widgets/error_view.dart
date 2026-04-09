import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A friendly full-area error state with a retry button.
/// Replaces the raw Dio exception text shown by default Riverpod error widgets.
class ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  final String? message;

  const ErrorView({
    super.key,
    required this.error,
    required this.onRetry,
    this.message,
  });

  String get _friendlyMessage {
    if (message != null) return message!;
    final s = error.toString().toLowerCase();
    if (s.contains('connection') || s.contains('socket') || s.contains('network')) {
      return 'No internet connection.\nPlease check your network and try again.';
    }
    if (s.contains('timeout')) {
      return 'The request timed out.\nPlease try again.';
    }
    if (s.contains('401') || s.contains('unauthorized')) {
      return 'Session expired. Please log in again.';
    }
    if (s.contains('500') || s.contains('server')) {
      return 'Server error. Please try again in a moment.';
    }
    return 'Something went wrong.\nPlease try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 52, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text(
              _friendlyMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try Again'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
