import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/models/homework.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/shimmer_list.dart';
import '../providers/parent_provider.dart';
import '../widgets/parent_scaffold.dart';

// Responsive scale helper — base ref width 390 px
double _s(BuildContext ctx, double base, {double min = 0, double max = double.infinity}) {
  final w = MediaQuery.of(ctx).size.width;
  final scaled = base * (w / 390.0);
  return scaled.clamp(min == 0 ? base * 0.75 : min, max == double.infinity ? base * 1.4 : max);
}

double _fs(BuildContext ctx, double base, {double min = 10, double max = 22}) =>
    _s(ctx, base, min: min, max: max);

// ─── Screen ───────────────────────────────────────────────────────────────────

class ParentHomeworkScreen extends ConsumerStatefulWidget {
  final int initialTab;
  const ParentHomeworkScreen({super.key, this.initialTab = 0});

  @override
  ConsumerState<ParentHomeworkScreen> createState() =>
      _ParentHomeworkScreenState();
}

class _ParentHomeworkScreenState
    extends ConsumerState<ParentHomeworkScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
        length: 2, vsync: this, initialIndex: widget.initialTab);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, _) {
      return ParentScaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              "Child's Homework & Announcements",
              style: GoogleFonts.poppins(
                fontSize: _fs(context, 15, min: 13, max: 19),
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          backgroundColor: AppColors.primary,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Container(
                width: 32, height: 32,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
                padding: const EdgeInsets.all(3),
                child: Image.asset('assets/images/logo.png', fit: BoxFit.contain),
              ),
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: AppColors.accent,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            labelStyle: GoogleFonts.poppins(
                fontSize: _fs(context, 13, min: 11, max: 15),
                fontWeight: FontWeight.w600),
            unselectedLabelStyle: GoogleFonts.poppins(
                fontSize: _fs(context, 13, min: 11, max: 15),
                fontWeight: FontWeight.w500),
            tabs: const [
              Tab(text: 'Homework'),
              Tab(text: 'Announcements'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _HomeworkList(
              asyncProvider: parentHomeworkProvider,
              onRefresh: () =>
                  ref.refresh(parentHomeworkProvider.future),
            ),
            _AnnouncementsList(
              asyncProvider: parentBroadcastsProvider,
              onRefresh: () =>
                  ref.refresh(parentBroadcastsProvider.future),
            ),
          ],
        ),
      );
    });
  }
}

// ─── Homework List ────────────────────────────────────────────────────────────

class _HomeworkList extends ConsumerWidget {
  final ProviderListenable<AsyncValue<List<HomeworkModel>>> asyncProvider;
  final Future<void> Function() onRefresh;

  const _HomeworkList({required this.asyncProvider, required this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hPad = _s(context, 14, min: 10, max: 20);
    final hwAsync = ref.watch(asyncProvider);

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: hwAsync.when(
        loading: () => const ShimmerList(showAvatar: false),
        error: (e, _) => ErrorView(error: e, onRetry: () => onRefresh()),
        data: (list) => list.isEmpty
            ? _scrollableEmpty(context,
                icon: Icons.assignment_outlined,
                message: 'No homework assigned')
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(hPad,
                    _s(context, 12, min: 8, max: 16),
                    hPad, _s(context, 24, min: 16, max: 32)),
                itemCount: list.length,
                separatorBuilder: (_, __) =>
                    SizedBox(height: _s(context, 8, min: 6, max: 12)),
                itemBuilder: (ctx, i) {
                  final hw = list[i];
                  final completionsAsync = ref.watch(
                      parentChildHomeworkCompletionsProvider);
                  final completion = completionsAsync.maybeWhen(
                    data: (m) => m[hw.id],
                    orElse: () => null,
                  );
                  return _HomeworkCard(hw: hw, completion: completion);
                },
              ),
      ),
    );
  }
}

// ─── Announcements List ───────────────────────────────────────────────────────

class _AnnouncementsList extends ConsumerWidget {
  final ProviderListenable<AsyncValue<List<BroadcastModel>>> asyncProvider;
  final Future<void> Function() onRefresh;

  const _AnnouncementsList(
      {required this.asyncProvider, required this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hPad = _s(context, 14, min: 10, max: 20);
    final bcAsync = ref.watch(asyncProvider);

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: bcAsync.when(
        loading: () => const ShimmerList(showAvatar: false),
        error: (e, _) => ErrorView(error: e, onRetry: () => onRefresh()),
        data: (list) => list.isEmpty
            ? _scrollableEmpty(context,
                icon: Icons.campaign_outlined,
                message: 'No announcements yet')
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(hPad,
                    _s(context, 12, min: 8, max: 16),
                    hPad, _s(context, 24, min: 16, max: 32)),
                itemCount: list.length,
                separatorBuilder: (_, __) =>
                    SizedBox(height: _s(context, 8, min: 6, max: 12)),
                itemBuilder: (ctx, i) =>
                    _BroadcastCard(broadcast: list[i]),
              ),
      ),
    );
  }
}

// scrollable empty — keeps pull-to-refresh working
Widget _scrollableEmpty(BuildContext ctx,
    {required IconData icon, required String message}) {
  return LayoutBuilder(builder: (ctx, constraints) {
    final iconSize = (constraints.maxWidth * 0.16).clamp(40.0, 64.0);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: constraints.maxHeight * 0.28),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: iconSize,
                  color: AppColors.textMuted.withOpacity(0.4)),
              SizedBox(height: _s(ctx, 14, min: 10, max: 20)),
              Text(
                message,
                style: GoogleFonts.poppins(
                  fontSize: _fs(ctx, 14, min: 12, max: 16),
                  color: AppColors.textMuted,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  });
}

// ─── Homework Card ────────────────────────────────────────────────────────────

class _HomeworkCard extends StatelessWidget {
  final HomeworkModel hw;
  // null = teacher hasn't recorded a status yet → render as "Pending".
  final StudentHomeworkCompletion? completion;

  const _HomeworkCard({required this.hw, this.completion});

  @override
  Widget build(BuildContext context) {
    final isOnline = hw.isOnlineTest;
    final isDueSoon = hw.dueDate != null &&
        hw.dueDate!.isAfter(DateTime.now()) &&
        hw.dueDate!.isBefore(
            DateTime.now().add(const Duration(days: 2)));
    final pad = _s(context, 14, min: 10, max: 20);

    return LayoutBuilder(builder: (context, constraints) {
      return Container(
        width: constraints.maxWidth,
        padding: EdgeInsets.all(pad),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: isDueSoon
              ? Border.all(
                  color: AppColors.warning.withOpacity(0.5), width: 1)
              : null,
          boxShadow: const [
            BoxShadow(
                color: Color(0x0C1D3557),
                blurRadius: 10,
                offset: Offset(0, 3)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Badges ────────────────────────────────────────────────────
            Row(
              children: [
                _Badge(
                  label: isOnline ? 'Online Test' : 'Written',
                  color: isOnline ? AppColors.accent : AppColors.primary,
                ),
                SizedBox(width: _s(context, 6, min: 4, max: 10)),
                Flexible(
                  child: _Badge(
                    label: hw.subject,
                    color: AppColors.textSecondary,
                    bg: AppColors.iconContainer,
                    maxLines: 1,
                  ),
                ),
                if (hw.dueDate != null) ...[
                  const Spacer(),
                  Text(
                    'Due ${DateFormat('dd MMM').format(hw.dueDate!)}',
                    style: GoogleFonts.poppins(
                      fontSize: _fs(context, 10, min: 9, max: 12),
                      fontWeight: FontWeight.w600,
                      color: isDueSoon
                          ? AppColors.warning
                          : AppColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),

            SizedBox(height: _s(context, 8, min: 6, max: 12)),

            // ── Title ─────────────────────────────────────────────────────
            Text(
              hw.title,
              style: GoogleFonts.poppins(
                fontSize: _fs(context, 14, min: 12, max: 17),
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),

            // ── Description ───────────────────────────────────────────────
            if (hw.description != null &&
                hw.description!.isNotEmpty) ...[
              SizedBox(height: _s(context, 6, min: 4, max: 10)),
              Text(
                hw.description!,
                style: GoogleFonts.poppins(
                  fontSize: _fs(context, 12, min: 11, max: 14),
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],

            SizedBox(height: _s(context, 8, min: 6, max: 12)),

            // ── Assigned date + completion status ─────────────────────────
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Assigned ${DateFormat('dd MMM yyyy').format(hw.createdAt)}',
                    style: GoogleFonts.poppins(
                      fontSize: _fs(context, 10, min: 9, max: 12),
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                _CompletionPill(completion: completion),
              ],
            ),
          ],
        ),
      );
    });
  }
}

/// Pill-style badge that mirrors the attendance present/absent indicator:
/// green = teacher marked Complete, red = teacher marked Incomplete,
/// grey  = teacher hasn't recorded a status yet.
class _CompletionPill extends StatelessWidget {
  final StudentHomeworkCompletion? completion;
  const _CompletionPill({required this.completion});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final IconData icon;
    final String label;
    if (completion == null) {
      color = AppColors.textMuted;
      icon = Icons.schedule;
      label = 'Pending';
    } else if (completion!.completed) {
      color = AppColors.success;
      icon = Icons.check_circle;
      label = 'Complete';
    } else {
      color = AppColors.error;
      icon = Icons.cancel_outlined;
      label = 'Incomplete';
    }
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _s(context, 8, min: 6, max: 12),
        vertical: _s(context, 3, min: 2, max: 5),
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: _s(context, 12, min: 10, max: 14), color: color),
          SizedBox(width: _s(context, 4, min: 3, max: 6)),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: _fs(context, 10, min: 9, max: 12),
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Broadcast Card ───────────────────────────────────────────────────────────

class _BroadcastCard extends StatelessWidget {
  final BroadcastModel broadcast;

  const _BroadcastCard({required this.broadcast});

  @override
  Widget build(BuildContext context) {
    final pad = _s(context, 14, min: 10, max: 20);

    return LayoutBuilder(builder: (context, constraints) {
      return Container(
        width: constraints.maxWidth,
        padding: EdgeInsets.all(pad),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
                color: Color(0x0C1D3557),
                blurRadius: 10,
                offset: Offset(0, 3)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.campaign_outlined,
                    size: _s(context, 18, min: 16, max: 22),
                    color: AppColors.accent),
                SizedBox(width: _s(context, 6, min: 4, max: 10)),
                Expanded(
                  child: Text(
                    broadcast.title,
                    style: GoogleFonts.poppins(
                      fontSize: _fs(context, 14, min: 12, max: 17),
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: _s(context, 8, min: 6, max: 12)),
            Text(
              broadcast.message,
              style: GoogleFonts.poppins(
                fontSize: _fs(context, 13, min: 11, max: 15),
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            SizedBox(height: _s(context, 8, min: 6, max: 12)),
            // Wrap prevents footer from overflowing on narrow screens
            Wrap(
              spacing: _s(context, 12, min: 8, max: 16),
              runSpacing: 4,
              children: [
                Text(
                  'From ${broadcast.senderUsername}',
                  style: GoogleFonts.poppins(
                    fontSize: _fs(context, 10, min: 9, max: 12),
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
                Text(
                  DateFormat('dd MMM, hh:mm a')
                      .format(broadcast.createdAt),
                  style: GoogleFonts.poppins(
                    fontSize: _fs(context, 10, min: 9, max: 12),
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }
}

// ─── Shared badge ─────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final Color? bg;
  final int maxLines;

  const _Badge({
    required this.label,
    required this.color,
    this.bg,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _s(context, 8, min: 6, max: 12),
        vertical: _s(context, 3, min: 2, max: 5),
      ),
      decoration: BoxDecoration(
        color: bg ?? color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: _fs(context, 10, min: 9, max: 12),
          fontWeight: FontWeight.w600,
          color: color,
        ),
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
