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

/// School-wide chapter database used by the "pick from database" picker.
final availableChaptersProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final raw = await api.listAvailableChapters();
  return raw.cast<Map<String, dynamic>>();
});

/// School-wide PRESENTATION LIBRARY — one row per presentation. Used by the
/// "Presentations" tab in the teacher Database screen. Includes PROCESSING
/// and FAILED rows by default so teachers can see decks still generating
/// (and remove failed ones) without a separate toggle.
final presentationLibraryProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final raw = await api.listPresentationLibrary(includeProcessing: true);
  return raw.cast<Map<String, dynamic>>();
});
