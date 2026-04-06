import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/admin_provider.dart';

class AdminTimetableScreen extends ConsumerStatefulWidget {
  const AdminTimetableScreen({super.key});

  @override
  ConsumerState<AdminTimetableScreen> createState() =>
      _AdminTimetableScreenState();
}

class _AdminTimetableScreenState extends ConsumerState<AdminTimetableScreen> {
  int _periodsPerDay = 6;
  bool _enableWeekends = false;
  // List of {start: TimeOfDay, end: TimeOfDay} for each period
  List<_PeriodTime> _periodTimes = [];
  bool _initialized = false;
  bool _saving = false;

  void _initFromConfig(dynamic config) {
    if (_initialized) return;
    if (config != null) {
      _periodsPerDay = config.periodsPerDay;
      _enableWeekends = config.enableWeekends;
      if (config.periodTimes != null && config.periodTimes.isNotEmpty) {
        _periodTimes = (config.periodTimes as List).map((e) {
          return _PeriodTime(
            start: _parseTime(e['start'] ?? '09:00'),
            end: _parseTime(e['end'] ?? '09:45'),
          );
        }).toList();
      }
    }
    _syncPeriodTimes();
    _initialized = true;
  }

  void _syncPeriodTimes() {
    while (_periodTimes.length < _periodsPerDay) {
      final prev = _periodTimes.isNotEmpty ? _periodTimes.last : null;
      final startHour = prev != null
          ? (prev.end.hour + (prev.end.minute >= 45 ? 1 : 0))
          : 9;
      final startMin = prev != null ? ((prev.end.minute + 0) % 60) : 0;
      _periodTimes.add(_PeriodTime(
        start: TimeOfDay(hour: startHour % 24, minute: startMin),
        end: TimeOfDay(
            hour: (startHour + (startMin + 45 >= 60 ? 1 : 0)) % 24,
            minute: (startMin + 45) % 60),
      ));
    }
    while (_periodTimes.length > _periodsPerDay) {
      _periodTimes.removeLast();
    }
  }

  TimeOfDay _parseTime(String s) {
    final parts = s.split(':');
    return TimeOfDay(
        hour: int.tryParse(parts[0]) ?? 9,
        minute: int.tryParse(parts[1]) ?? 0);
  }

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickTime(int periodIndex, bool isStart) async {
    final current = isStart
        ? _periodTimes[periodIndex].start
        : _periodTimes[periodIndex].end;
    final picked = await showTimePicker(
      context: context,
      initialTime: current,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _periodTimes[periodIndex] =
            _PeriodTime(start: picked, end: _periodTimes[periodIndex].end);
      } else {
        _periodTimes[periodIndex] =
            _PeriodTime(start: _periodTimes[periodIndex].start, end: picked);
      }
    });
  }

  Future<void> _clearAllSlots({int? grade}) async {
    final label = grade != null ? 'Grade $grade timetable slots' : 'ALL timetable slots';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: Text('This will permanently delete $label. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final api = ref.read(apiClientProvider);
      await api.clearTimetableSlots(grade: grade);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$label cleared successfully.'),
          backgroundColor: AppColors.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  Future<void> _save() async {
    // Validate: each period end must be after start
    for (int i = 0; i < _periodTimes.length; i++) {
      final pt = _periodTimes[i];
      final startMins = pt.start.hour * 60 + pt.start.minute;
      final endMins = pt.end.hour * 60 + pt.end.minute;
      if (endMins <= startMins) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Period ${i + 1}: end time must be after start time.'),
          backgroundColor: AppColors.error,
        ));
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.updateTimetableConfig({
        'periods_per_day': _periodsPerDay,
        'enable_weekends': _enableWeekends,
        'period_times': _periodTimes
            .asMap()
            .entries
            .map((e) => {
                  'period': e.key + 1,
                  'start': _formatTime(e.value.start),
                  'end': _formatTime(e.value.end),
                })
            .toList(),
      });
      ref.invalidate(timetableConfigProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Timetable configuration saved!'),
          backgroundColor: AppColors.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Save failed: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final configAsync = ref.watch(timetableConfigProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Timetable Configuration'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear All Slots',
            onPressed: () => _clearAllSlots(),
          ),
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
      ),
      body: configAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 8),
            const Text('Failed to load configuration'),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              onPressed: () => ref.invalidate(timetableConfigProvider),
            ),
          ]),
        ),
        data: (config) {
          _initFromConfig(config);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Periods per day ────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: mindForgeCardDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Basic Settings',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Expanded(
                              child: Text('Periods Per Day',
                                  style: TextStyle(fontSize: 14))),
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            child: Text(
                              '$_periodsPerDay',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20,
                                  color: AppColors.primary),
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: _periodsPerDay.toDouble(),
                        min: 2,
                        max: 12,
                        divisions: 10,
                        label: '$_periodsPerDay periods',
                        activeColor: AppColors.primary,
                        onChanged: (v) => setState(() {
                          _periodsPerDay = v.round();
                          _syncPeriodTimes();
                        }),
                      ),
                      const Divider(),
                      SwitchListTile(
                        value: _enableWeekends,
                        title: const Text('Enable Weekend Classes'),
                        subtitle:
                            const Text('Allow Saturday & Sunday scheduling'),
                        contentPadding: EdgeInsets.zero,
                        onChanged: (v) => setState(() => _enableWeekends = v),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Period times ───────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: mindForgeCardDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text('Period Timings',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 15)),
                          ),
                          Text('$_periodsPerDay periods',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Set start and end time for each period.',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 16),
                      ...List.generate(_periodsPerDay, (i) {
                        final pt = _periodTimes[i];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.primary
                                .withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: AppColors.primary
                                    .withValues(alpha: 0.15)),
                          ),
                          child: Row(
                            children: [
                              // Period label
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: Text(
                                    '${i + 1}',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),

                              // Start time
                              Expanded(
                                child: _TimeButton(
                                  label: 'Start',
                                  time: pt.start,
                                  onTap: () => _pickTime(i, true),
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6),
                                child: Text('→',
                                    style: TextStyle(
                                        fontSize: 16,
                                        color: AppColors.textSecondary)),
                              ),

                              // End time
                              Expanded(
                                child: _TimeButton(
                                  label: 'End',
                                  time: pt.end,
                                  onTap: () => _pickTime(i, false),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ── Save ───────────────────────────────────────────────
                SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save),
                    label: Text(_saving ? 'Saving...' : 'Save Configuration'),
                    onPressed: _saving ? null : _save,
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PeriodTime {
  final TimeOfDay start;
  final TimeOfDay end;
  const _PeriodTime({required this.start, required this.end});
}

class _TimeButton extends StatelessWidget {
  final String label;
  final TimeOfDay time;
  final VoidCallback onTap;

  const _TimeButton({
    required this.label,
    required this.time,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final formatted =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 10, color: AppColors.textSecondary)),
            const SizedBox(height: 2),
            Row(
              children: [
                const Icon(Icons.access_time,
                    size: 13, color: AppColors.primary),
                const SizedBox(width: 4),
                Text(formatted,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppColors.textPrimary)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
