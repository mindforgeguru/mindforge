import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/xp.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/brand_palette.dart';
import '../providers/xp_provider.dart';

/// Theme picker section for the XP dashboard. Pulls the catalogue from the
/// backend (which knows lock state) and pairs each row with the local
/// `BrandPalettes` palette so previews show actual colours.
class ThemePicker extends ConsumerWidget {
  const ThemePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themesAsync = ref.watch(themesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Themes',
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 8),
        themesAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Could not load themes: $e',
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: AppColors.textMuted,
              ),
            ),
          ),
          data: (catalogue) => Column(
            children: [
              for (final t in catalogue.themes) _ThemeRow(info: t),
            ],
          ),
        ),
      ],
    );
  }
}

class _ThemeRow extends ConsumerStatefulWidget {
  final ThemeInfo info;
  const _ThemeRow({required this.info});

  @override
  ConsumerState<_ThemeRow> createState() => _ThemeRowState();
}

class _ThemeRowState extends ConsumerState<_ThemeRow> {
  bool _busy = false;

  Future<void> _select() async {
    if (_busy || !widget.info.unlocked || widget.info.selected) return;
    setState(() => _busy = true);
    try {
      // Default theme is selected by sending null (server stores NULL).
      final id = widget.info.themeId == 'mind_forge' ? null : widget.info.themeId;
      await ref.read(apiClientProvider).selectTheme(id);
      ref.invalidate(themesProvider);
      ref.invalidate(studentXpProvider); // refresh selected_theme everywhere
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not select theme: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final palette = BrandPalettes.byId(info.themeId);
    final locked = !info.unlocked;
    final selected = info.selected;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: locked ? null : _select,
          child: Opacity(
            opacity: locked ? 0.55 : 1.0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? palette.accent : AppColors.divider,
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  _PaletteSwatch(palette: palette, locked: locked),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Text(
                              palette.name,
                              style: GoogleFonts.poppins(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                            if (selected) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: palette.accent,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  'ACTIVE',
                                  style: GoogleFonts.poppins(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          locked
                              ? 'Reach Level ${info.unlockLevel} to unlock'
                              : palette.description,
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_busy)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (locked)
                    const Icon(Icons.lock_rounded,
                        size: 18, color: AppColors.textMuted)
                  else if (!selected)
                    const Icon(Icons.chevron_right_rounded,
                        size: 22, color: AppColors.textMuted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PaletteSwatch extends StatelessWidget {
  final BrandPalette palette;
  final bool locked;
  const _PaletteSwatch({required this.palette, required this.locked});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(child: Container(color: palette.primary)),
          Expanded(child: Container(color: palette.secondary)),
          Expanded(child: Container(color: palette.accent)),
        ],
      ),
    );
  }
}
