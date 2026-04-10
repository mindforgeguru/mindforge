import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/app_theme.dart';

/// A shimmer skeleton for list screens — replaces CircularProgressIndicator
/// on the first load of any provider-backed list.
class ShimmerList extends StatelessWidget {
  /// Number of placeholder rows to show (default 6).
  final int itemCount;

  /// Height of each placeholder row (default 72).
  final double itemHeight;

  /// Whether rows have a leading circular avatar (default true).
  final bool showAvatar;

  const ShimmerList({
    super.key,
    this.itemCount = 6,
    this.itemHeight = 72,
    this.showAvatar = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      itemCount: itemCount,
      physics: const NeverScrollableScrollPhysics(),
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, __) => _ShimmerRow(
        height: itemHeight,
        showAvatar: showAvatar,
      ),
    );
  }
}

class _ShimmerRow extends StatelessWidget {
  final double height;
  final bool showAvatar;

  const _ShimmerRow({required this.height, required this.showAvatar});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.divider,
      highlightColor: Colors.white,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            if (showAvatar) ...[
              const _Bone(width: 40, height: 40, radius: 20),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  _Bone(width: double.infinity, height: 14),
                  SizedBox(height: 8),
                  _Bone(width: 160, height: 11),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const _Bone(width: 56, height: 32, radius: 8),
          ],
        ),
      ),
    );
  }
}

/// A single rectangular shimmer bone.
class _Bone extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const _Bone({
    required this.width,
    required this.height,
    this.radius = 4,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width == double.infinity ? null : width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// A shimmer skeleton for card-based screens (dashboard sections, fees, etc.)
class ShimmerCard extends StatelessWidget {
  final double height;

  const ShimmerCard({super.key, this.height = 120});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.divider,
      highlightColor: Colors.white,
      child: Container(
        height: height,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}

/// Shows [count] shimmer cards stacked vertically.
class ShimmerCards extends StatelessWidget {
  final int count;
  final double cardHeight;

  const ShimmerCards({super.key, this.count = 3, this.cardHeight = 120});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        count,
        (_) => ShimmerCard(height: cardHeight),
      ),
    );
  }
}
