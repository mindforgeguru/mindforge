import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/constants.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/mindforge_logo.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _usernameController = TextEditingController();
  final _parentUsernameController = TextEditingController();
  final List<String> _pin = ['', '', '', '', '', ''];
  int _pinIndex = 0;
  bool _isRegister = false;
  String _selectedRole = 'student';
  int _selectedGrade = 8;
  final Set<String> _selectedSubjects = {};
  final Set<String> _selectedTeacherSubjects = {};

  static const _subjectOptions = [
    _Subject('economics', 'Economics', Icons.bar_chart_outlined),
    _Subject('computer', 'Computer', Icons.computer_outlined),
    _Subject('ai', 'AI', Icons.psychology_outlined),
  ];

  @override
  void dispose() {
    _usernameController.dispose();
    _parentUsernameController.dispose();
    super.dispose();
  }

  String get _enteredPin => _pin.join();

  void _tapDigit(String d) {
    if (_pinIndex >= 6) return;
    setState(() {
      _pin[_pinIndex] = d;
      _pinIndex++;
    });
  }

  void _tapDelete() {
    if (_pinIndex == 0) return;
    setState(() {
      _pinIndex--;
      _pin[_pinIndex] = '';
    });
  }

  void _clearPin() {
    setState(() {
      for (int i = 0; i < 6; i++) {
        _pin[i] = '';
      }
      _pinIndex = 0;
    });
  }

  Future<void> _submit() async {
    final username = _usernameController.text.trim();
    if (username.isEmpty) {
      _showSnack('Please enter your username.');
      return;
    }
    if (_enteredPin.length < 6) {
      _showSnack('Please enter your 6-digit MPIN.');
      return;
    }
    final notifier = ref.read(authProvider.notifier);
    if (_isRegister) {
      final isStudent = _selectedRole == 'student';
      final isTeacher = _selectedRole == 'teacher';
      final ok = await notifier.register(
        username,
        _enteredPin,
        _selectedRole,
        parentUsername:
            isStudent ? _parentUsernameController.text.trim() : null,
        grade: isStudent ? _selectedGrade : null,
        additionalSubjects: isStudent ? _selectedSubjects.toList() : null,
        teachableSubjects:
            isTeacher ? _selectedTeacherSubjects.toList() : null,
      );
      if (ok && mounted) {
        _showSnack('Registration submitted! Await admin approval.',
            color: AppColors.success);
        setState(() {
          _isRegister = false;
          _clearPin();
          _usernameController.clear();
          _parentUsernameController.clear();
          _selectedGrade = 8;
          _selectedSubjects.clear();
        });
      }
    } else {
      await notifier.login(username, _enteredPin);
    }
  }

  void _showSnack(String msg, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color ?? AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    ref.listen<AuthState>(authProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        _showSnack(next.error!);
        _clearPin();
      }
    });

    final sh = MediaQuery.of(context).size.height;
    final compact = sh < 700;
    // viewPadding.bottom covers BOTH 3-button nav (48dp) and gesture nav (30dp).
    // Clamp to a minimum of 32 so the Login button always clears the nav bar.
    final safeBottom = MediaQuery.of(context).viewPadding.bottom.clamp(32.0, 80.0);

    // Fluid header height — scales with viewport height (CSS vh equivalent)
    // 19 vh ≈ 148px on 780px screen; 27 vh ≈ 224px on 830px screen
    final hPad = R.vh(context, compact ? 2.8 : 4.5);   // vertical padding inside header
    final logoScale = R.fluid(context, compact ? 1.05 : 1.25, min: 0.9, max: 1.4);

    return Scaffold(
      backgroundColor: AppColors.primary,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        bottom: false, // card extends beneath home indicator
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Header height is driven by content + fluid padding — no hardcoded px
            final headerH = R.vh(context, compact ? 19.0 : 27.0);
            // Card fills at minimum the rest of the screen.
            // When register fields push it taller, SingleChildScrollView kicks in.
            final cardMinH = constraints.maxHeight - headerH;
            // Fluid horizontal padding — scales with screen width
            final hzPad = R.sp(context, 24);

            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Logo header ──────────────────────────────────────
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                        hzPad, hPad, hzPad, hPad),
                    child: MindForgeLogo(
                      size: logoScale,
                      dark: true,
                      showTagline: true,
                    ),
                  ),

                  // ── Form card ────────────────────────────────────────
                  Container(
                    width: double.infinity,
                    constraints: BoxConstraints(minHeight: cardMinH),
                    decoration: const BoxDecoration(
                      color: AppColors.background,
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(32)),
                    ),
                    padding: EdgeInsets.fromLTRB(
                        hzPad, compact ? 16 : 20, hzPad, safeBottom),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── Tabs — Expanded fills available width (Flexbox) ──
                        Container(
                          decoration: BoxDecoration(
                            color:
                                AppColors.divider.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.all(4),
                          child: Row(
                            children: [
                              _Tab(
                                label: 'Login',
                                active: !_isRegister,
                                onTap: () => setState(() {
                                  _isRegister = false;
                                  _clearPin();
                                  _parentUsernameController.clear();
                                }),
                              ),
                              _Tab(
                                label: 'Request Access',
                                active: _isRegister,
                                onTap: () => setState(() {
                                  _isRegister = true;
                                  _clearPin();
                                }),
                              ),
                            ],
                          ),
                        ),

                        SizedBox(height: R.sp(context, compact ? 12 : 16)),

                        // ── Username ────────────────────────────────────
                        TextField(
                          controller: _usernameController,
                          decoration: const InputDecoration(
                            labelText: 'Username',
                            prefixIcon: Icon(Icons.person_outline),
                            isDense: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.deny(
                                RegExp(r'\s')),
                          ],
                          textInputAction: TextInputAction.done,
                        ),

                        // ── Register-only fields ────────────────────────
                        if (_isRegister) ...[
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            initialValue: _selectedRole,
                            decoration: const InputDecoration(
                              labelText: 'Register as',
                              prefixIcon: Icon(Icons.badge_outlined),
                              isDense: true,
                            ),
                            items: ['student', 'teacher', 'parent']
                                .map((r) => DropdownMenuItem(
                                      value: r,
                                      child: Text(r[0].toUpperCase() +
                                          r.substring(1)),
                                    ))
                                .toList(),
                            onChanged: (v) => setState(() {
                              _selectedRole = v ?? 'student';
                              _parentUsernameController.clear();
                              _selectedSubjects.clear();
                              _selectedTeacherSubjects.clear();
                              _selectedGrade = 8;
                            }),
                          ),

                          // ── Teacher-only fields ───────────────────────
                          if (_selectedRole == 'teacher') ...[
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Text(
                                  'Subjects you can teach',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '(max 4)',
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: AppConstants.subjects.map((s) {
                                final sel = _selectedTeacherSubjects.contains(s);
                                final maxReached =
                                    _selectedTeacherSubjects.length >= 4 && !sel;
                                return GestureDetector(
                                  onTap: maxReached
                                      ? null
                                      : () => setState(() => sel
                                          ? _selectedTeacherSubjects.remove(s)
                                          : _selectedTeacherSubjects.add(s)),
                                  child: AnimatedContainer(
                                    duration:
                                        const Duration(milliseconds: 150),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: sel
                                          ? AppColors.primary
                                          : maxReached
                                              ? AppColors.surface
                                                  .withOpacity(0.5)
                                              : AppColors.surface,
                                      border: Border.all(
                                        color: sel
                                            ? AppColors.primary
                                            : AppColors.divider,
                                        width: sel ? 2 : 1,
                                      ),
                                      borderRadius:
                                          BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      s,
                                      style: GoogleFonts.poppins(
                                        fontSize: 11,
                                        fontWeight: sel
                                            ? FontWeight.w700
                                            : FontWeight.normal,
                                        color: sel
                                            ? Colors.white
                                            : maxReached
                                                ? AppColors.textMuted
                                                : AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],

                          // ── Student-only fields ───────────────────────
                          if (_selectedRole == 'student') ...[
                            const SizedBox(height: 10),
                            DropdownButtonFormField<int>(
                              initialValue: _selectedGrade,
                              decoration: const InputDecoration(
                                labelText: 'Grade',
                                prefixIcon: Icon(Icons.school_outlined),
                                isDense: true,
                              ),
                              items: [8, 9, 10]
                                  .map((g) => DropdownMenuItem(
                                        value: g,
                                        child: Text('Grade $g'),
                                      ))
                                  .toList(),
                              onChanged: (v) => setState(
                                  () => _selectedGrade = v ?? 8),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Additional Subjects',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: _subjectOptions.map((s) {
                                final sel =
                                    _selectedSubjects.contains(s.key);
                                return GestureDetector(
                                  onTap: () => setState(() => sel
                                      ? _selectedSubjects.remove(s.key)
                                      : _selectedSubjects.add(s.key)),
                                  child: AnimatedContainer(
                                    duration: const Duration(
                                        milliseconds: 150),
                                    padding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: sel
                                          ? AppColors.primary
                                          : AppColors.surface,
                                      border: Border.all(
                                        color: sel
                                            ? AppColors.primary
                                            : AppColors.divider,
                                        width: sel ? 2 : 1,
                                      ),
                                      borderRadius:
                                          BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(s.icon,
                                            size: 15,
                                            color: sel
                                                ? Colors.white
                                                : AppColors
                                                    .textSecondary),
                                        const SizedBox(width: 5),
                                        Text(
                                          s.label,
                                          style:
                                              GoogleFonts.poppins(
                                            fontSize: 12,
                                            fontWeight: sel
                                                ? FontWeight.w700
                                                : FontWeight.normal,
                                            color: sel
                                                ? Colors.white
                                                : AppColors
                                                    .textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _parentUsernameController,
                              decoration: const InputDecoration(
                                labelText:
                                    "Parent's Username (optional)",
                                prefixIcon:
                                    Icon(Icons.family_restroom),
                                isDense: true,
                                helperText:
                                    'Link to parent account if registered.',
                                helperMaxLines: 2,
                              ),
                              inputFormatters: [
                                FilteringTextInputFormatter.deny(
                                    RegExp(r'\s')),
                              ],
                              textInputAction: TextInputAction.done,
                            ),
                          ],
                        ],

                        SizedBox(height: R.sp(context, compact ? 14 : 18)),

                        // ── MPIN label ──────────────────────────────────
                        Text(
                          _isRegister
                              ? 'Set a 6-digit MPIN'
                              : 'Enter your 6-digit MPIN',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: R.fs(context, 13, min: 11, max: 15),
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),

                        SizedBox(height: R.sp(context, 10)),

                        // ── PIN dots — FractionallySizedBox keeps them
                        //   proportional; height ≥ 48 for accessibility ──
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(6, (i) {
                            final filled = _pin[i].isNotEmpty;
                            final active = i == _pinIndex;
                            final dotW = R.fluid(context, 38, min: 32, max: 46);
                            final dotH = R.fluid(context, 50, min: 48, max: 58);
                            return Container(
                              margin: EdgeInsets.symmetric(
                                  horizontal: R.sp(context, 4)),
                              width: dotW,
                              height: dotH,
                              decoration: BoxDecoration(
                                color: filled
                                    ? AppColors.primary
                                        .withValues(alpha: 0.12)
                                    : AppColors.surface,
                                border: Border.all(
                                  color: active
                                      ? AppColors.primary
                                      : AppColors.divider,
                                  width: active ? 2 : 1,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(
                                child: filled
                                    ? Container(
                                        width: R.fluid(context, 10, min: 8, max: 12),
                                        height: R.fluid(context, 10, min: 8, max: 12),
                                        decoration: const BoxDecoration(
                                          color: AppColors.primary,
                                          shape: BoxShape.circle,
                                        ),
                                      )
                                    : null,
                              ),
                            );
                          }),
                        ),

                        SizedBox(height: R.sp(context, 14)),

                        // ── Number pad ──────────────────────────────────
                        _buildPad(context),

                        SizedBox(height: R.sp(context, 12)),

                        // ── Submit — FractionallySizedBox (100% width),
                        //   height ≥ 48 logical px for accessibility ─────
                        SizedBox(
                          width: double.infinity,
                          height: R.fluid(context, 52, min: 48, max: 60),
                          child: ElevatedButton(
                            onPressed: auth.isLoading ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: auth.isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: AppColors.textOnDark),
                                  )
                                : FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      _isRegister
                                          ? 'Submit Registration'
                                          : 'Login',
                                      style: GoogleFonts.poppins(
                                        fontSize: R.fs(context, 15,
                                            min: 13, max: 17),
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textOnDark,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // PIN pad — keys use Expanded (like CSS flex: 1) so they fill available
  // width on any screen size. Height ≥ 48 logical px for accessibility.
  Widget _buildPad(BuildContext context) {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', '⌫'],
    ];
    final keyH = R.fluid(context, 44, min: 40, max: 54);
    final numFs = R.fs(context, 17, min: 14, max: 21);
    final delFs = R.fs(context, 14, min: 11, max: 17);
    final rowGap = R.sp(context, 5);
    final keyGap = R.sp(context, 4);

    return Column(
      children: rows.map((row) {
        return Padding(
          padding: EdgeInsets.only(bottom: rowGap),
          child: Row(
            children: row.map((key) {
              if (key.isEmpty) {
                // Invisible spacer — same flex weight as a real key
                return Expanded(child: SizedBox(height: keyH));
              }
              final isDel = key == '⌫';
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    isDel ? _tapDelete() : _tapDigit(key);
                  },
                  child: Container(
                    height: keyH,
                    margin: EdgeInsets.symmetric(horizontal: keyGap),
                    decoration: BoxDecoration(
                      color: isDel
                          ? AppColors.error.withValues(alpha: 0.08)
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          key,
                          style: GoogleFonts.poppins(
                            fontSize: isDel ? delFs : numFs,
                            fontWeight: FontWeight.w700,
                            color: isDel
                                ? AppColors.error
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }
}

// ─── Subject chip data ─────────────────────────────────────────────────────────

class _Subject {
  final String key;
  final String label;
  final IconData icon;
  const _Subject(this.key, this.label, this.icon);
}

// ─── Tab widget ────────────────────────────────────────────────────────────────

class _Tab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _Tab(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          // Vertical padding ensures tap target ≥ 48 logical px (accessibility)
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: active ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight:
                    active ? FontWeight.w700 : FontWeight.normal,
                color: active
                    ? AppColors.textOnDark
                    : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
