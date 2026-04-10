import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Friendly error widget for parent screens.
/// Shows a "no child linked" message for 404s, generic message + retry otherwise.
Widget parentErrorWidget(Object error, {String? context, VoidCallback? onRetry}) {
  final is404 = error is DioException && error.response?.statusCode == 404;

  if (is404) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.link_off, size: 64, color: AppColors.textSecondary),
            SizedBox(height: 16),
            Text(
              'No Child Account Linked',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Text(
              'Your account is not linked to a child account.\n'
              'Ask your child to enter your username when registering.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  final isConnection = error is DioException &&
      (error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.unknown);

  return Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_rounded, size: 52, color: AppColors.textMuted),
          const SizedBox(height: 16),
          Text(
            isConnection
                ? 'No internet connection.\nPlease check your network and try again.'
                : 'Something went wrong.\nPlease try again.',
            style: const TextStyle(
              fontSize: 15,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          if (onRetry != null) ...[
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
        ],
      ),
    ),
  );
}
