import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';

/// School-wide list of (teacher, presentation) cards.
final presentationListProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final raw = await api.listPresentations();
  return raw.cast<Map<String, dynamic>>();
});

/// Detailed view for one presentation (deck + progress + period logs).
final presentationDetailProvider =
    FutureProvider.family<Map<String, dynamic>, int>((ref, id) async {
  final api = ref.watch(apiClientProvider);
  return await api.getPresentation(id);
});
