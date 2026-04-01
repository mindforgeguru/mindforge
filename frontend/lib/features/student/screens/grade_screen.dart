import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/websocket_client.dart';
import '../../../core/models/grade.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/constants.dart';
import '../../../core/utils/responsive.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/student_provider.dart';
import '../widgets/student_bottom_nav.dart';

class StudentGradeScreen extends StatelessWidget {
  const StudentGradeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Grades'),
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
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            indicatorColor: AppColors.accent,
            tabs: [
              Tab(text: 'Online Tests'),
              Tab(text: 'Offline Tests'),
              Tab(text: 'Analysis'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _OnlineGradesTab(),
            _OfflineGradesTab(),
            _AnalysisTab(),
          ],
        ),
        bottomNavigationBar: const StudentBottomNav(),
      ),
    );
  }
}

// ─── Online Grades Tab ────────────────────────────────────────────────────────

class _OnlineGradesTab extends ConsumerStatefulWidget {
  const _OnlineGradesTab();

  @override
  ConsumerState<_OnlineGradesTab> createState() => _OnlineGradesTabState();
}

class _OnlineGradesTabState extends ConsumerState<_OnlineGradesTab> {
  String? _filterSubject;

  @override
  Widget build(BuildContext context) {
    final gradesAsync = ref.watch(studentOnlineGradesProvider(_filterSubject));
    return _GradesTabBody(
      gradesAsync: gradesAsync,
      filterSubject: _filterSubject,
      onSubjectChanged: (v) => setState(() => _filterSubject = v),
      onRefresh: () =>
          ref.refresh(studentOnlineGradesProvider(_filterSubject).future),
      buildCard: (g, high, low) => _GradeCard(
        grade: g,
        classHigh: high,
        classLow: low,
        onTap: g.testId != null
            ? () => context
                .go('${RouteNames.studentDashboard}/tests/${g.testId}/review')
            : null,
      ),
    );
  }
}

// ─── Offline Grades Tab ───────────────────────────────────────────────────────

class _OfflineGradesTab extends ConsumerStatefulWidget {
  const _OfflineGradesTab();

  @override
  ConsumerState<_OfflineGradesTab> createState() => _OfflineGradesTabState();
}

class _OfflineGradesTabState extends ConsumerState<_OfflineGradesTab> {
  String? _filterSubject;
  StreamSubscription<Map<String, dynamic>>? _wsSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _connectWebSocket());
  }

  void _connectWebSocket() {
    final userId = ref.read(authProvider).userId;
    if (userId == null) return;
    final ws = ref.read(webSocketClientProvider);
    final stream = ws.connect(userId);
    _wsSub = stream.listen((event) {
      final eventType = event['event'] as String?;
      if (eventType == 'grade_added' || eventType == 'offline_grade_added') {
        ref.invalidate(studentOfflineGradesProvider);
      }
    });
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gradesAsync =
        ref.watch(studentOfflineGradesProvider(_filterSubject));
    return _GradesTabBody(
      gradesAsync: gradesAsync,
      filterSubject: _filterSubject,
      onSubjectChanged: (v) => setState(() => _filterSubject = v),
      onRefresh: () =>
          ref.refresh(studentOfflineGradesProvider(_filterSubject).future),
      emptyMessage: 'No offline test grades yet.',
      emptySubMessage: 'Grades entered by your teacher will appear here.',
      buildCard: (g, high, low) =>
          _GradeCard(grade: g, classHigh: high, classLow: low),
    );
  }
}

// ─── Analysis Tab ─────────────────────────────────────────────────────────────

class _AnalysisTab extends ConsumerStatefulWidget {
  const _AnalysisTab();

  @override
  ConsumerState<_AnalysisTab> createState() => _AnalysisTabState();
}

class _AnalysisTabState extends ConsumerState<_AnalysisTab> {
  String _testType = 'online'; // 'online' | 'offline'
  String? _subject;

  @override
  Widget build(BuildContext context) {
    // Only fetch when subject is selected
    final gradesAsync = _subject == null
        ? null
        : (_testType == 'online'
            ? ref.watch(studentOnlineGradesProvider(_subject))
            : ref.watch(studentOfflineGradesProvider(_subject)));

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(R.sp(context, 16, min: 12, max: 20), R.sp(context, 16, min: 12, max: 20), R.sp(context, 16, min: 12, max: 20), R.sp(context, 24, min: 16, max: 28)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Filters ─────────────────────────────────────────────────
          Container(
            decoration: mindForgeCardDecoration(),
            padding: EdgeInsets.all(R.sp(context, 16, min: 12, max: 20)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Select Filters',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 12),

                // Test type toggle
                Row(
                  children: [
                    const Text('Type:',
                        style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                              value: 'online',
                              label: Text('Online'),
                              icon: Icon(Icons.computer, size: 14)),
                          ButtonSegment(
                              value: 'offline',
                              label: Text('Offline'),
                              icon: Icon(Icons.print_outlined, size: 14)),
                        ],
                        selected: {_testType},
                        onSelectionChanged: (s) =>
                            setState(() => _testType = s.first),
                        style: ButtonStyle(
                          textStyle: WidgetStateProperty.all(
                              const TextStyle(fontSize: 12)),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Subject dropdown
                DropdownButtonFormField<String?>(
                  initialValue: _subject,
                  decoration: const InputDecoration(
                    labelText: 'Subject',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: [
                    const DropdownMenuItem(
                        value: null, child: Text('Select a subject…')),
                    ...AppConstants.subjects.map((s) =>
                        DropdownMenuItem(value: s, child: Text(s))),
                  ],
                  onChanged: (v) => setState(() => _subject = v),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Chart / Prompt ───────────────────────────────────────────
          if (_subject == null)
            Container(
              height: R.vh(context, 33),
              decoration: mindForgeCardDecoration(),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.bar_chart_outlined,
                        size: 56, color: AppColors.textMuted),
                    SizedBox(height: 12),
                    Text('Select a subject to see your progress',
                        style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary)),
                  ],
                ),
              ),
            )
          else if (gradesAsync != null)
            gradesAsync.when(
              loading: () => SizedBox(
                  height: R.vh(context, 33),
                  child: const Center(child: CircularProgressIndicator())),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (grades) {
                // Sort chronologically
                final sorted = [...grades]
                  ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

                if (sorted.isEmpty) {
                  return Container(
                    height: R.vh(context, 33),
                    decoration: mindForgeCardDecoration(),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.search_off,
                              size: 48, color: AppColors.textMuted),
                          const SizedBox(height: 12),
                          Text(
                            'No $_testType test grades for $_subject yet.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return Column(
                  children: [
                    _ProgressChart(
                        grades: sorted, subject: _subject!, type: _testType),
                    const SizedBox(height: 16),
                    _SummaryStats(grades: sorted),
                    const SizedBox(height: 16),
                    _RecentList(grades: sorted.reversed.toList()),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

// ─── Progress Line Chart ──────────────────────────────────────────────────────

class _ProgressChart extends StatelessWidget {
  final List<GradeModel> grades;
  final String subject;
  final String type;

  const _ProgressChart(
      {required this.grades, required this.subject, required this.type});

  @override
  Widget build(BuildContext context) {
    final spots = grades.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value.percentage);
    }).toList();

    final avg =
        grades.fold(0.0, (s, g) => s + g.percentage) / grades.length;
    final lineColor = avg >= 75
        ? AppColors.success
        : avg >= 50
            ? AppColors.warning
            : AppColors.error;

    return Container(
      decoration: mindForgeCardDecoration(),
      padding: EdgeInsets.fromLTRB(R.sp(context, 8, min: 6, max: 12), R.sp(context, 16, min: 12, max: 20), R.sp(context, 12, min: 8, max: 16), R.sp(context, 10, min: 8, max: 14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 12),
            child: Row(
              children: [
                const Icon(Icons.show_chart,
                    color: AppColors.primary, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$subject · ${type == 'online' ? 'Online' : 'Offline'} Tests',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: R.fluid(context, 200, min: 170, max: 240),
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: 100,
                minX: grades.length > 1 ? -0.3 : -0.5,
                maxX: grades.length > 1 ? grades.length - 0.7 : 0.5,
                clipData: const FlClipData.all(),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 25,
                  getDrawingHorizontalLine: (v) => FlLine(
                    color: AppColors.divider,
                    strokeWidth: 1,
                    dashArray: v == 75 ? null : [4, 4],
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 25,
                      reservedSize: R.fluid(context, 36, min: 32, max: 42),
                      getTitlesWidget: (v, _) => Text(
                        '${v.toInt()}%',
                        style: const TextStyle(
                            fontSize: 10, color: AppColors.textMuted),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: math.max(1, (grades.length / 5).ceilToDouble()),
                      reservedSize: R.fluid(context, 26, min: 22, max: 32),
                      getTitlesWidget: (v, _) {
                        final idx = v.toInt();
                        if (idx < 0 || idx >= grades.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            DateFormat('d MMM').format(grades[idx].createdAt),
                            style: const TextStyle(
                                fontSize: 9, color: AppColors.textMuted),
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                // 75% passing threshold line
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: 75,
                      color: AppColors.success.withValues(alpha: 0.5),
                      strokeWidth: 1.5,
                      dashArray: [6, 4],
                      label: HorizontalLineLabel(
                        show: true,
                        alignment: Alignment.topRight,
                        labelResolver: (_) => '75%',
                        style: const TextStyle(
                            fontSize: 9, color: AppColors.success),
                      ),
                    ),
                  ],
                ),
                lineBarsData: [
                  // Main score line
                  LineChartBarData(
                    spots: spots,
                    isCurved: grades.length > 2,
                    curveSmoothness: 0.35,
                    color: lineColor,
                    barWidth: 2.5,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, _, __, ___) =>
                          FlDotCirclePainter(
                        radius: 4,
                        color: lineColor,
                        strokeWidth: 1.5,
                        strokeColor: Colors.white,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: lineColor.withValues(alpha: 0.08),
                    ),
                  ),
                  // Average line
                  LineChartBarData(
                    spots: [
                      FlSpot(0, avg),
                      FlSpot((grades.length - 1).toDouble(), avg),
                    ],
                    isCurved: false,
                    color: AppColors.primary.withValues(alpha: 0.4),
                    barWidth: 1.5,
                    dashArray: [6, 4],
                    dotData: const FlDotData(show: false),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) =>
                        AppColors.cardBackground,
                    getTooltipItems: (spots) => spots.map((s) {
                      if (s.barIndex == 1) return null; // skip avg line
                      final g = grades[s.x.toInt()];
                      return LineTooltipItem(
                        '${g.percentage.toStringAsFixed(1)}%\n',
                        TextStyle(
                            color: lineColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12),
                        children: [
                          TextSpan(
                            text:
                                '${g.marksObtained.toStringAsFixed(0)}/${g.maxMarks.toStringAsFixed(0)} marks\n${DateFormat('d MMM').format(g.createdAt)}',
                            style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 10,
                                fontWeight: FontWeight.normal),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),

          // Legend
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ChartLegend(color: lineColor, label: 'Score'),
              SizedBox(width: R.sp(context, 12, min: 8, max: 16)),
              _ChartLegend(
                  color: AppColors.primary.withValues(alpha: 0.4),
                  label: 'Average',
                  dashed: true),
              SizedBox(width: R.sp(context, 12, min: 8, max: 16)),
              _ChartLegend(
                  color: AppColors.success.withValues(alpha: 0.5),
                  label: '75% pass mark',
                  dashed: true),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChartLegend extends StatelessWidget {
  final Color color;
  final String label;
  final bool dashed;
  const _ChartLegend(
      {required this.color, required this.label, this.dashed = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 2.5,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: R.fs(context, 10, min: 9, max: 12),
                color: AppColors.textMuted)),
      ],
    );
  }
}

// ─── Summary stats ────────────────────────────────────────────────────────────

class _SummaryStats extends StatelessWidget {
  final List<GradeModel> grades;
  const _SummaryStats({required this.grades});

  @override
  Widget build(BuildContext context) {
    final avg =
        grades.fold(0.0, (s, g) => s + g.percentage) / grades.length;
    final best = grades.map((g) => g.percentage).reduce(math.max);
    final lowest = grades.map((g) => g.percentage).reduce(math.min);

    final avgColor = avg >= 75
        ? AppColors.success
        : avg >= 50
            ? AppColors.warning
            : AppColors.error;

    return Container(
      decoration: mindForgeCardDecoration(),
      padding: EdgeInsets.all(R.sp(context, 16, min: 12, max: 20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Summary',
              style:
                  TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          SizedBox(height: R.sp(context, 12, min: 8, max: 16)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _StatBox(
                  label: 'Average',
                  value: '${avg.toStringAsFixed(1)}%',
                  color: avgColor),
              _StatBox(
                  label: 'Best',
                  value: '${best.toStringAsFixed(1)}%',
                  color: AppColors.success),
              _StatBox(
                  label: 'Lowest',
                  value: '${lowest.toStringAsFixed(1)}%',
                  color: AppColors.error),
              _StatBox(
                  label: 'Tests',
                  value: '${grades.length}',
                  color: AppColors.primary),
            ],
          ),
          SizedBox(height: R.sp(context, 12, min: 8, max: 16)),
          // Trend description
          Row(
            children: [
              Icon(
                grades.length >= 2 &&
                        grades.last.percentage >
                            grades.first.percentage
                    ? Icons.trending_up
                    : grades.length >= 2 &&
                            grades.last.percentage <
                                grades.first.percentage
                        ? Icons.trending_down
                        : Icons.trending_flat,
                color: grades.length >= 2 &&
                        grades.last.percentage > grades.first.percentage
                    ? AppColors.success
                    : grades.length >= 2 &&
                            grades.last.percentage <
                                grades.first.percentage
                        ? AppColors.error
                        : AppColors.textMuted,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                grades.length < 2
                    ? 'Only one test recorded'
                    : grades.last.percentage > grades.first.percentage
                        ? 'Improving trend — keep it up!'
                        : grades.last.percentage <
                                grades.first.percentage
                            ? 'Declining trend — needs attention'
                            : 'Stable performance',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatBox(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontSize: R.fs(context, 20, min: 16, max: 24),
                fontWeight: FontWeight.bold,
                color: color)),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(
                fontSize: R.fs(context, 11, min: 9, max: 13),
                color: AppColors.textSecondary)),
      ],
    );
  }
}

// ─── Recent entries list ──────────────────────────────────────────────────────

class _RecentList extends StatelessWidget {
  final List<GradeModel> grades;
  const _RecentList({required this.grades});

  @override
  Widget build(BuildContext context) {
    final shown = grades.take(5).toList();
    return Container(
      decoration: mindForgeCardDecoration(),
      padding: EdgeInsets.all(R.sp(context, 14, min: 10, max: 18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Recent Tests',
              style:
                  TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 12),
          ...shown.map((g) {
            final pctColor = g.percentage >= 75
                ? AppColors.success
                : g.percentage >= 50
                    ? AppColors.warning
                    : AppColors.error;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(g.chapter,
                            style: TextStyle(
                                fontSize: R.fs(context, 13, min: 11, max: 15),
                                fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis),
                        Text(
                          DateFormat('d MMM yyyy').format(g.createdAt),
                          style: TextStyle(
                              fontSize: R.fs(context, 11, min: 9, max: 13),
                              color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${g.marksObtained.toStringAsFixed(0)}/${g.maxMarks.toStringAsFixed(0)}',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: R.fs(context, 13, min: 11, max: 15)),
                      ),
                      Text(
                        '${g.percentage.toStringAsFixed(1)}%',
                        style: TextStyle(
                            fontSize: R.fs(context, 12, min: 10, max: 14),
                            color: pctColor,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ─── Shared tab body ──────────────────────────────────────────────────────────

class _GradesTabBody extends StatelessWidget {
  final AsyncValue<List<GradeModel>> gradesAsync;
  final String? filterSubject;
  final ValueChanged<String?> onSubjectChanged;
  final Future<void> Function() onRefresh;
  final Widget Function(GradeModel g, double high, double low) buildCard;
  final String emptyMessage;
  final String emptySubMessage;

  const _GradesTabBody({
    required this.gradesAsync,
    required this.filterSubject,
    required this.onSubjectChanged,
    required this.onRefresh,
    required this.buildCard,
    this.emptyMessage = 'No grade records yet.',
    this.emptySubMessage = 'Grades will appear here once available.',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: DropdownButtonFormField<String?>(
            initialValue: filterSubject,
            decoration: const InputDecoration(
              labelText: 'Filter by Subject',
              isDense: true,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            items: [
              const DropdownMenuItem(
                  value: null, child: Text('All Subjects')),
              ...AppConstants.subjects.map((s) =>
                  DropdownMenuItem(value: s, child: Text(s))),
            ],
            onChanged: onSubjectChanged,
          ),
        ),
        Expanded(
          child: gradesAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (grades) {
              if (grades.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.grade_outlined,
                          size: 56, color: AppColors.textMuted),
                      const SizedBox(height: 16),
                      Text(emptyMessage,
                          style: const TextStyle(
                              fontSize: 15,
                              color: AppColors.textSecondary)),
                      const SizedBox(height: 6),
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 40),
                        child: Text(emptySubMessage,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textMuted)),
                      ),
                    ],
                  ),
                );
              }

              final Map<String, List<double>> subjectPcts = {};
              for (final g in grades) {
                subjectPcts
                    .putIfAbsent(g.subject, () => [])
                    .add(g.percentage);
              }

              return RefreshIndicator(
                onRefresh: onRefresh,
                child: ListView.separated(
                  padding: EdgeInsets.fromLTRB(R.sp(context, 16, min: 12, max: 20), 8, R.sp(context, 16, min: 12, max: 20), 16),
                  itemCount: grades.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final g = grades[i];
                    final pcts = subjectPcts[g.subject]!;
                    return buildCard(
                      g,
                      pcts.reduce((a, b) => a > b ? a : b),
                      pcts.reduce((a, b) => a < b ? a : b),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─── Grade card ───────────────────────────────────────────────────────────────

class _GradeCard extends StatelessWidget {
  final GradeModel grade;
  final double classHigh;
  final double classLow;
  final VoidCallback? onTap;

  const _GradeCard({
    required this.grade,
    required this.classHigh,
    required this.classLow,
    this.onTap,
  });

  Color get _pctColor {
    if (grade.percentage >= 75) return AppColors.success;
    if (grade.percentage >= 50) return AppColors.warning;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: mindForgeCardDecoration(),
        padding: EdgeInsets.all(R.sp(context, 14, min: 10, max: 18)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(grade.subject,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: R.fs(context, 15, min: 13, max: 17)),
                          overflow: TextOverflow.ellipsis),
                      Text(grade.chapter,
                          style:
                              Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${grade.marksObtained}/${grade.maxMarks}',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: R.fs(context, 15, min: 13, max: 17)),
                    ),
                    Text(
                      '${grade.percentage.toStringAsFixed(1)}%',
                      style: TextStyle(
                          color: _pctColor,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: grade.percentage / 100,
                backgroundColor: AppColors.divider,
                valueColor:
                    AlwaysStoppedAnimation<Color>(_pctColor),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Class High: ${classHigh.toStringAsFixed(1)}%',
                    style: TextStyle(
                        fontSize: R.fs(context, 11, min: 9, max: 13),
                        color: AppColors.success)),
                Text('Class Low: ${classLow.toStringAsFixed(1)}%',
                    style: TextStyle(
                        fontSize: R.fs(context, 11, min: 9, max: 13),
                        color: AppColors.error)),
              ],
            ),
            if (onTap != null) ...[
              const SizedBox(height: 8),
              const Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(Icons.visibility_outlined,
                      size: 13, color: AppColors.primary),
                  SizedBox(width: 4),
                  Text('Tap to review test',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
