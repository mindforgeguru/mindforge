import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Friendly error widget for parent screens.
/// Shows a "no child linked" message for 404s, generic message otherwise.
Widget parentErrorWidget(Object error, {String? context}) {
  final is404 = error is DioException && error.response?.statusCode == 404;

  if (is404) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.link_off, size: 64, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            const Text(
              'No Child Account Linked',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
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
      child: Text(
        isConnection
            ? 'Unable to connect. Please check your internet connection.'
            : 'Something went wrong. Please try again.',
        style: const TextStyle(color: AppColors.textSecondary),
        textAlign: TextAlign.center,
      ),
    ),
  );
}
