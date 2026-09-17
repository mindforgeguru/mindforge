import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/constants.dart';

/// Set an old test paper's grade, subject and chapter by hand — for a paper the
/// AI couldn't classify, or got wrong.
///
/// Test generation only picks papers whose grade and subject match exactly, so
/// both are required and only the app's own lists are offered. Pops `true`
/// once [onSave] succeeds; a failure is shown inline and the dialog stays open.
class OldPaperDetailsDialog extends StatefulWidget {
  final String paperName;
  final int? grade;
  final String? subject;
  final String? chapter;
  final Future<void> Function(int grade, String subject, String? chapter) onSave;

  const OldPaperDetailsDialog({
    super.key,
    required this.paperName,
    this.grade,
    this.subject,
    this.chapter,
    required this.onSave,
  });

  @override
  State<OldPaperDetailsDialog> createState() => _OldPaperDetailsDialogState();
}

class _OldPaperDetailsDialogState extends State<OldPaperDetailsDialog> {
  int? _grade;
  String? _subject;
  late final TextEditingController _chapter;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Values an older AI scan stored off-list ("Math", grade 12) can't be
    // pre-selected: the dropdown asserts on a value it has no item for.
    _grade = AppConstants.grades.contains(widget.grade) ? widget.grade : null;
    _subject =
        AppConstants.subjects.contains(widget.subject) ? widget.subject : null;
    _chapter = TextEditingController(text: widget.chapter ?? '');
  }

  @override
  void dispose() {
    _chapter.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final chapter = _chapter.text.trim();
    try {
      await widget.onSave(_grade!, _subject!, chapter.isEmpty ? null : chapter);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = "Couldn't save. Check your connection and try again.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _grade != null && _subject != null && !_saving;
    return AlertDialog(
      title: const Text('Paper details'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.paperName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            const Text(
              'Grade and subject are needed for this paper to be used when generating tests.',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              key: const Key('old-paper-grade'),
              initialValue: _grade,
              decoration: const InputDecoration(labelText: 'Grade', isDense: true),
              items: AppConstants.grades
                  .map((g) => DropdownMenuItem(value: g, child: Text('Grade $g')))
                  .toList(),
              onChanged: _saving ? null : (v) => setState(() => _grade = v),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              key: const Key('old-paper-subject'),
              initialValue: _subject,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Subject', isDense: true),
              items: AppConstants.subjects
                  .map((s) => DropdownMenuItem(
                        value: s,
                        child: Text(s, overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: _saving ? null : (v) => setState(() => _subject = v),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('old-paper-chapter'),
              controller: _chapter,
              enabled: !_saving,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Chapter (optional)',
                isDense: true,
                counterText: '',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(fontSize: 12, color: AppColors.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: canSave ? _save : null,
          child: _saving
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Save'),
        ),
      ],
    );
  }
}
