import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/error_view.dart';
import '../widgets/admin_scaffold.dart';

final _feedbackListProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, bool>((ref, onlyOpen) async {
  final api = ref.watch(apiClientProvider);
  return api.listFeedback(onlyOpen: onlyOpen);
});

class AdminFeedbackScreen extends ConsumerStatefulWidget {
  const AdminFeedbackScreen({super.key});

  @override
  ConsumerState<AdminFeedbackScreen> createState() => _AdminFeedbackScreenState();
}

class _AdminFeedbackScreenState extends ConsumerState<AdminFeedbackScreen> {
  bool _onlyOpen = true;

  Future<void> _resolve(int id) async {
    final api = ref.read(apiClientProvider);
    try {
      await api.resolveFeedback(id);
      ref.invalidate(_feedbackListProvider(_onlyOpen));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not mark resolved. Try again.')),
      );
    }
  }

  String _formatTime(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day}/${dt.month}/${dt.year} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_feedbackListProvider(_onlyOpen));

    return AdminScaffold(
      appBar: AppBar(
        title: const Text('User Feedback'),
        actions: [
          PopupMenuButton<bool>(
            initialValue: _onlyOpen,
            onSelected: (v) => setState(() => _onlyOpen = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: true, child: Text('Open only')),
              PopupMenuItem(value: false, child: Text('Show all')),
            ],
            icon: const Icon(Icons.filter_list),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(_feedbackListProvider(_onlyOpen)),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorView(
            error: e,
            onRetry: () => ref.invalidate(_feedbackListProvider(_onlyOpen)),
          ),
          data: (reports) {
            if (reports.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('No feedback reports.')),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: reports.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final r = reports[i];
                final resolved = r['resolved'] == true;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${r['username'] ?? 'unknown'} · ${r['role'] ?? '-'}',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                            if (resolved)
                              const Chip(
                                label: Text('Resolved'),
                                visualDensity: VisualDensity.compact,
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_formatTime(r['created_at'] as String)}'
                          '${r['route'] != null ? ' · ${r['route']}' : ''}'
                          '${r['app_version'] != null ? ' · v${r['app_version']}' : ''}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(r['message']?.toString() ?? ''),
                        if (!resolved) ...[
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              icon: const Icon(Icons.check, size: 18),
                              label: const Text('Mark resolved'),
                              onPressed: () => _resolve(r['id'] as int),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
