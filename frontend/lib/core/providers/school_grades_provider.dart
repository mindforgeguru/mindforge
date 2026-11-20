import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/constants.dart';
import 'school_logo_provider.dart';

/// The grades the signed-in user's school teaches (#5), falling back to every
/// supported grade until the school list has loaded (or for the owner).
final schoolGradesProvider = Provider<List<int>>((ref) {
  final school = ref.watch(currentSchoolProvider).valueOrNull;
  return gradesOffered(school);
});

/// A school's `grades_offered` from the public school list.
List<int> gradesOffered(Map<String, dynamic>? school) {
  final raw = school?['grades_offered'];
  if (raw is! List || raw.isEmpty) return AppConstants.grades;
  return [for (final g in raw) (g as num).toInt()]..sort();
}

/// The grades a picker lists: the school's, plus [keep] when it's already
/// selected but no longer offered — a dropdown asserts on a value it has no
/// item for, and old records should still show their grade.
List<int> pickableGrades(List<int> offered, {int? keep}) =>
    keep == null || offered.contains(keep)
        ? offered
        : ([...offered, keep]..sort());
