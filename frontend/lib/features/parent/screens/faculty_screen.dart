import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/error_view.dart';
import '../providers/parent_provider.dart';
import '../widgets/parent_scaffold.dart';

class ParentFacultyScreen extends ConsumerWidget {
  const ParentFacultyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final facultyAsync = ref.watch(parentFacultyProvider);
    final isWide = MediaQuery.of(context).size.width >= 900;

    return ParentScaffold(
      wideContent: isWide,
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: Text(
          'Our Faculty',
          style: GoogleFonts.poppins(
              fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6)),
              padding: const EdgeInsets.all(3),
              child: Image.asset('assets/images/logo.png',
                  fit: BoxFit.contain),
            ),
          ),
        ],
      ),
      body: facultyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(parentFacultyProvider),
        ),
        data: (faculty) {
          if (faculty.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.people_outline,
                      size: 64,
                      color: AppColors.textMuted.withValues(alpha: 0.4)),
                  const SizedBox(height: 16),
                  Text('No faculty members yet.',
                      style: GoogleFonts.poppins(
                          fontSize: 15, color: AppColors.textMuted)),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => ref.refresh(parentFacultyProvider.future),
            child: isWide
                ? _WideGrid(faculty: faculty)
                : _MobileList(faculty: faculty),
          );
        },
      ),
    );
  }
}

class _WideGrid extends StatelessWidget {
  final List<Map<String, dynamic>> faculty;
  const _WideGrid({required this.faculty});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final crossCount = width >= 1400 ? 4 : width >= 1100 ? 3 : 2;

    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 28, 48, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Meet Our Teachers',
            style: GoogleFonts.poppins(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.primary),
          ),
          const SizedBox(height: 4),
          Text(
            '${faculty.length} faculty member${faculty.length == 1 ? '' : 's'}',
            style: GoogleFonts.poppins(
                fontSize: 13, color: AppColors.textMuted),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossCount,
                crossAxisSpacing: 20,
                mainAxisSpacing: 20,
                childAspectRatio: 0.82,
              ),
              itemCount: faculty.length,
              itemBuilder: (_, i) => _FacultyCard(teacher: faculty[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileList extends StatelessWidget {
  final List<Map<String, dynamic>> faculty;
  const _MobileList({required this.faculty});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: faculty.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _FacultyCardMobile(teacher: faculty[i]),
    );
  }
}

class _FacultyCard extends StatelessWidget {
  final Map<String, dynamic> teacher;
  const _FacultyCard({required this.teacher});

  @override
  Widget build(BuildContext context) {
    final name = teacher['username'] as String? ?? '';
    final picUrl = teacher['profile_pic_url'] as String?;
    final bio = teacher['bio'] as String?;
    final subjects = (teacher['subjects'] as List?)?.cast<String>() ?? [];

    return Container(
      decoration: mindForgeCardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 5,
            child: Stack(
              fit: StackFit.expand,
              children: [
                picUrl != null
                    ? CachedNetworkImage(
                        imageUrl: picUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          color: AppColors.primary.withValues(alpha: 0.08),
                          child: const Center(
                              child: CircularProgressIndicator(strokeWidth: 2)),
                        ),
                        errorWidget: (_, __, ___) =>
                            _AvatarPlaceholder(name: name),
                      )
                    : _AvatarPlaceholder(name: name),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          AppColors.primary.withValues(alpha: 0.6),
                        ],
                        stops: const [0.5, 1.0],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 10,
                  left: 12,
                  right: 12,
                  child: Text(
                    name,
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (subjects.isNotEmpty) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: subjects
                          .take(3)
                          .map((s) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.accent.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(s,
                                    style: GoogleFonts.poppins(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.accent)),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Expanded(
                    child: Text(
                      bio?.isNotEmpty == true
                          ? bio!
                          : 'Dedicated educator committed to student excellence.',
                      style: GoogleFonts.poppins(
                          fontSize: 11.5,
                          color: AppColors.textSecondary,
                          height: 1.45),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FacultyCardMobile extends StatelessWidget {
  final Map<String, dynamic> teacher;
  const _FacultyCardMobile({required this.teacher});

  @override
  Widget build(BuildContext context) {
    final name = teacher['username'] as String? ?? '';
    final picUrl = teacher['profile_pic_url'] as String?;
    final bio = teacher['bio'] as String?;
    final subjects = (teacher['subjects'] as List?)?.cast<String>() ?? [];

    return Container(
      decoration: mindForgeCardDecoration(),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 72,
              height: 72,
              child: picUrl != null
                  ? CachedNetworkImage(
                      imageUrl: picUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: AppColors.primary.withValues(alpha: 0.08),
                      ),
                      errorWidget: (_, __, ___) =>
                          _AvatarPlaceholder(name: name),
                    )
                  : _AvatarPlaceholder(name: name),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
                if (subjects.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    children: subjects
                        .take(3)
                        .map((s) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(s,
                                  style: GoogleFonts.poppins(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.accent)),
                            ))
                        .toList(),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  bio?.isNotEmpty == true
                      ? bio!
                      : 'Dedicated educator committed to student excellence.',
                  style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      height: 1.4),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarPlaceholder extends StatelessWidget {
  final String name;
  const _AvatarPlaceholder({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primary.withValues(alpha: 0.1),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : 'T',
          style: GoogleFonts.poppins(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: AppColors.primary.withValues(alpha: 0.5)),
        ),
      ),
    );
  }
}
