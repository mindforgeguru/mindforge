import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/models/homework.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/shimmer_list.dart';
import '../providers/student_provider.dart';
import '../widgets/student_scaffold.dart';

// Responsive scale helpers
double _s(BuildContext ctx, double base, {double min = 0, double max = double.infinity}) {
  final w = MediaQuery.of(ctx).size.width;
  final scaled = base * (w / 390.0);
  return scaled.clamp(min == 0 ? base * 0.75 : min, max == double.infinity ? base * 1.4 : max);
}

double _fs(BuildContext ctx, double base, {double min = 10, double max = 22}) =>
    _s(ctx, base, min: min, max: max);

class StudentBroadcastsScreen extends ConsumerWidget {
  const StudentBroadcastsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWide = MediaQuery.of(context).size.width >= 900;
    final bcAsync = ref.watch(studentBroadcastsProvider);
    final hPad = _s(context, 14, min: 10, max: 20);

    Widget buildList() => RefreshIndicator(
          onRefresh: () => ref.refresh(studentBroadcastsProvider.future),
          child: bcAsync.when(
            loading: () => const ShimmerList(showAvatar: false),
            error: (e, _) => ErrorView(
                error: e,
                onRetry: () => ref.invalidate(studentBroadcastsProvider)),
            data: (list) => list.isEmpty
                ? _scrollableEmpty(context,
                    icon: Icons.campaign_outlined,
                    message: 'No announcements yet')
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                        hPad,
                        _s(context, 12, min: 8, max: 16),
                        hPad,
                        _s(context, 24, min: 16, max: 32)),
                    itemCount: list.length,
                    separatorBuilder: (_, __) =>
                        SizedBox(height: _s(context, 8, min: 6, max: 12)),
                    itemBuilder: (ctx, i) => _BroadcastCard(broadcast: list[i]),
                  ),
          ),
        );

    return StudentScaffold(
      wideContent: isWide,
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'Announcements',
            style: GoogleFonts.poppins(
              fontSize: _fs(context, 16, min: 14, max: 20),
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
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6)),
              padding: const EdgeInsets.all(3),
              child: Image.asset('assets/images/logo.png', fit: BoxFit.contain),
            ),
          ),
        ],
      ),
      body: isWide
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: SizedBox(
                  width: MediaQuery.of(context).size.width * 0.5,
                  child: Container(
                    decoration: mindForgeCardDecoration(),
                    clipBehavior: Clip.antiAlias,
                    child: buildList(),
                  ),
                ),
              ),
            )
          : buildList(),
    );
  }
}

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
                  color: AppColors.textMuted.withValues(alpha: 0.4)),
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
                  DateFormat('dd MMM, hh:mm a').format(broadcast.createdAt),
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
