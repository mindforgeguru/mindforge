import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/models/xp.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/xp_provider.dart';

/// One row on the leaderboard. Highlights the viewer's own row when
/// [isMe] is true. Highlight + avatar tint use the active brand palette.
class LeaderboardTile extends ConsumerWidget {
  final LeaderboardEntry entry;
  final bool isMe;

  const LeaderboardTile({
    super.key,
    required this.entry,
    this.isMe = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(currentPaletteProvider);
    final rankColor = _rankColor(entry.rank);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isMe
            ? palette.accent.withOpacity(0.10)
            : AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isMe ? palette.accent : AppColors.divider,
          width: isMe ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          // Rank
          SizedBox(
            width: 36,
            child: Text(
              '#${entry.rank}',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: rankColor,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Avatar
          _Avatar(
            url: entry.profilePicUrl,
            initial: entry.username.isNotEmpty
                ? entry.username[0].toUpperCase()
                : '?',
            tint: palette.primary,
          ),
          const SizedBox(width: 12),
          // Name + grade
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.username + (isMe ? ' (You)' : ''),
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: palette.primary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Grade ${entry.grade} • Level ${entry.currentLevel}',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // XP
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: palette.iconContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${entry.totalXp} XP',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: palette.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _rankColor(int rank) {
    switch (rank) {
      case 1:
        return const Color(0xFFB8860B); // gold
      case 2:
        return const Color(0xFF7D7D7D); // silver
      case 3:
        return const Color(0xFFB87333); // bronze
      default:
        return AppColors.textSecondary;
    }
  }
}

class _Avatar extends StatelessWidget {
  final String? url;
  final String initial;
  final Color tint;
  const _Avatar({required this.url, required this.initial, required this.tint});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: tint,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: GoogleFonts.poppins(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
    );

    final url = this.url;
    if (url == null || url.isEmpty) return placeholder;
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url,
        width: 36,
        height: 36,
        fit: BoxFit.cover,
        placeholder: (_, __) => placeholder,
        errorWidget: (_, __, ___) => placeholder,
      ),
    );
  }
}
