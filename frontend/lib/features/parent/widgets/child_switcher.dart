import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/parent_provider.dart';

/// True when the parent has several children, so the switcher is on screen.
/// Screens that draw under the status bar read this to leave the inset to it.
bool showsChildSwitcher(WidgetRef ref) =>
    (ref.watch(parentChildrenProvider).valueOrNull?.length ?? 0) > 1;

/// Which child the parent screens are showing.
///
/// Nothing at all for a parent with one child. With two or more, a row of chips
/// — name and grade — at the top of every parent screen; choosing one sets
/// [selectedChildIdProvider], which every parent provider watches.
class ChildSwitcher extends ConsumerWidget {
  const ChildSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!showsChildSwitcher(ref)) return const SizedBox.shrink();
    final children = ref.watch(parentChildrenProvider).valueOrNull!;

    final selected = ref.watch(selectedChildIdProvider) ??
        children.first['student_id'] as int;
    return Material(
      color: AppColors.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            for (final child in children) ...[
              ChoiceChip(
                label: Text('${child['username']} · Grade ${child['grade']}'),
                selected: child['student_id'] == selected,
                onSelected: (_) => ref
                    .read(selectedChildIdProvider.notifier)
                    .state = child['student_id'] as int,
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}
