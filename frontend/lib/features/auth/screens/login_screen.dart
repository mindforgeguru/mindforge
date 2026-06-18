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
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _parentUsernameController = TextEditingController();
  final _parentMpinController = TextEditingController();
  bool _obscureParentMpin = true;
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
    _phoneController.dispose();
    _emailController.dispose();
    _parentUsernameController.dispose();
    _parentMpinController.dispose();
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
      final isParent = _selectedRole == 'parent';
      final phone = _phoneController.text.trim();
      final email = _emailController.text.trim();

      if (!isParent && phone.isEmpty) {
        _showSnack('Phone number is required.');
        return;
      }

      // Every student account must be linked to a parent. Account deletion
      // can only be performed by the parent (or an admin) — without a
      // parent in place the student has no way to be deleted later.
      final parentUsernameTrimmed = _parentUsernameController.text.trim();
      final parentMpinTrimmed = _parentMpinController.text.trim();
      if (isStudent && parentUsernameTrimmed.isEmpty) {
        _showSnack("Parent's username is required to register a student.");
        return;
      }
      // Parent's MPIN is required for student registration. If the parent
      // already has an account, this MPIN must match (server verifies). If
      // the parent doesn't exist yet, this becomes the new parent's MPIN
      // — never reuses the student's MPIN.
      if (isStudent && parentMpinTrimmed.length != 6) {
        _showSnack("Parent's 6-digit MPIN is required to register a student.");
        return;
      }

      final ok = await notifier.register(
        username,
        _enteredPin,
        _selectedRole,
        phone: phone.isNotEmpty ? phone : null,
        email: email.isNotEmpty ? email : null,
        parentUsername: isStudent ? parentUsernameTrimmed : null,
        parentMpin: isStudent ? parentMpinTrimmed : null,
        grade: isStudent ? _selectedGrade : null,
        additionalSubjects: isStudent ? _selectedSubjects.toList() : null,
        teachableSubjects: isTeacher ? _selectedTeacherSubjects.toList() : null,
      );
      if (ok && mounted) {
        _showSnack('Registration submitted! Await admin approval.',
            color: AppColors.success);
        setState(() {
          _isRegister = false;
          _clearPin();
          _usernameController.clear();
          _phoneController.clear();
          _emailController.clear();
          _parentUsernameController.clear();
          _parentMpinController.clear();
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

    // Use wide web layout on screens >= 900px
    if (MediaQuery.of(context).size.width >= 900) {
      return _buildWebScaffold(context, auth);
    }

    final sh = MediaQuery.of(context).size.height;
    final compact = sh < 700;
    // viewPadding.bottom covers BOTH 3-button nav (48dp) and gesture nav (30dp).
    // Clamp to a minimum of 32 so the Login button always clears the nav bar.
    final safeBottom =
        MediaQuery.of(context).viewPadding.bottom.clamp(32.0, 80.0);

    // Fluid header height — scales with viewport height (CSS vh equivalent)
    // 19 vh ≈ 148px on 780px screen; 27 vh ≈ 224px on 830px screen
    final hPad =
        R.vh(context, compact ? 2.8 : 4.5); // vertical padding inside header
    final logoScale =
        R.fluid(context, compact ? 1.05 : 1.25, min: 0.9, max: 1.4);

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
                    padding: EdgeInsets.fromLTRB(hzPad, hPad, hzPad, hPad),
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
                            color: AppColors.divider.withValues(alpha: 0.5),
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
                                  _parentMpinController.clear();
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
                            FilteringTextInputFormatter.deny(RegExp(r'\s')),
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
                                      child: Text(
                                          r[0].toUpperCase() + r.substring(1)),
                                    ))
                                .toList(),
                            onChanged: (v) => setState(() {
                              _selectedRole = v ?? 'student';
                              _parentUsernameController.clear();
                              _parentMpinController.clear();
                              _selectedSubjects.clear();
                              _selectedTeacherSubjects.clear();
                              _selectedGrade = 8;
                            }),
                          ),

                          // ── Phone & Email ─────────────────────────────
                          const SizedBox(height: 10),
                          TextField(
                            controller: _phoneController,
                            decoration: InputDecoration(
                              labelText: _selectedRole == 'parent'
                                  ? 'Phone Number (optional)'
                                  : 'Phone Number',
                              prefixIcon: const Icon(Icons.phone_outlined),
                              isDense: true,
                              helperText: _selectedRole == 'student'
                                  ? "You can use your parent's number."
                                  : null,
                            ),
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _emailController,
                            decoration: InputDecoration(
                              labelText: 'Email (optional)',
                              prefixIcon: const Icon(Icons.email_outlined),
                              isDense: true,
                              helperText: _selectedRole == 'student'
                                  ? "You can use your parent's email."
                                  : null,
                            ),
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
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
                              ],
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: AppConstants.subjects.map((s) {
                                final sel =
                                    _selectedTeacherSubjects.contains(s);
                                return GestureDetector(
                                  onTap: () => setState(() => sel
                                      ? _selectedTeacherSubjects.remove(s)
                                      : _selectedTeacherSubjects.add(s)),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 7),
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
                                      borderRadius: BorderRadius.circular(20),
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
                              onChanged: (v) =>
                                  setState(() => _selectedGrade = v ?? 8),
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
                                final sel = _selectedSubjects.contains(s.key);
                                return GestureDetector(
                                  onTap: () => setState(() => sel
                                      ? _selectedSubjects.remove(s.key)
                                      : _selectedSubjects.add(s.key)),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    padding: const EdgeInsets.symmetric(
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
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(s.icon,
                                            size: 15,
                                            color: sel
                                                ? Colors.white
                                                : AppColors.textSecondary),
                                        const SizedBox(width: 5),
                                        Text(
                                          s.label,
                                          style: GoogleFonts.poppins(
                                            fontSize: 12,
                                            fontWeight: sel
                                                ? FontWeight.w700
                                                : FontWeight.normal,
                                            color: sel
                                                ? Colors.white
                                                : AppColors.textSecondary,
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
                                labelText: "Parent's Username *",
                                prefixIcon: Icon(Icons.family_restroom),
                                isDense: true,
                                helperText:
                                    'Required. If the parent does not have an '
                                    'account yet, one will be created with the '
                                    "Parent's MPIN you enter below.",
                                helperMaxLines: 3,
                              ),
                              inputFormatters: [
                                FilteringTextInputFormatter.deny(RegExp(r'\s')),
                              ],
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _parentMpinController,
                              obscureText: _obscureParentMpin,
                              keyboardType: TextInputType.number,
                              maxLength: 6,
                              decoration: InputDecoration(
                                labelText: "Parent's 6-digit MPIN *",
                                prefixIcon: const Icon(Icons.lock_outline),
                                isDense: true,
                                counterText: '',
                                helperText:
                                    "If the parent already has an account this "
                                    "must match their MPIN. Don't reuse the "
                                    "student's MPIN.",
                                helperMaxLines: 3,
                                suffixIcon: IconButton(
                                  icon: Icon(_obscureParentMpin
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined),
                                  onPressed: () => setState(() =>
                                      _obscureParentMpin = !_obscureParentMpin),
                                ),
                              ),
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
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
                                    ? AppColors.primary.withValues(alpha: 0.12)
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
                                        width: R.fluid(context, 10,
                                            min: 8, max: 12),
                                        height: R.fluid(context, 10,
                                            min: 8, max: 12),
                                        decoration: BoxDecoration(
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
                                        fontSize:
                                            R.fs(context, 15, min: 13, max: 17),
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

  // ─── Web layout ───────────────────────────────────────────────────────────

  Widget _buildWebScaffold(BuildContext context, AuthState auth) {
    return Scaffold(
      backgroundColor: const Color(0xFF060F1E),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Left: branding panel ─────────────────────────────────────
          Expanded(
            flex: 48,
            child: _buildWebLeftPanel(context),
          ),
          // ── Right: clean white form ──────────────────────────────────
          Expanded(
            flex: 52,
            child: _buildWebRightPanel(context, auth),
          ),
        ],
      ),
    );
  }

  Widget _buildWebLeftPanel(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF060F1E), Color(0xFF1D3557), Color(0xFF153A5E)],
          stops: [0.0, 0.6, 1.0],
        ),
      ),
      child: Stack(
        children: [
          // Large soft glow circles
          Positioned(
              top: -100,
              left: -100,
              child: Container(
                  width: 360,
                  height: 360,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.025)))),
          Positioned(
              bottom: -90,
              right: -70,
              child: Container(
                  width: 400,
                  height: 400,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.accent.withValues(alpha: 0.08)))),
          // Accent vertical edge glow
          Positioned(
            left: 0,
            top: 100,
            bottom: 100,
            child: Container(
              width: 3,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    AppColors.accent.withValues(alpha: 0.6),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Content
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(52, 48, 52, 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Logo block — Hansal logo + MindForge logo side by side
                  Row(
                    children: [
                      // Hansal Sir logo
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 6))
                          ],
                        ),
                        padding: const EdgeInsets.all(8),
                        child: Image.asset('assets/images/hansal_logo.png',
                            fit: BoxFit.contain),
                      ),
                      // Vertical divider
                      Container(
                        width: 1,
                        height: 52,
                        margin: const EdgeInsets.symmetric(horizontal: 18),
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                      // MindForge logo + name
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 6))
                          ],
                        ),
                        padding: const EdgeInsets.all(10),
                        child: Image.asset('assets/images/logo.png',
                            fit: BoxFit.contain),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('MIND FORGE',
                              style: GoogleFonts.poppins(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: 1.5)),
                          Text('AI Assisted Learning',
                              style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: Colors.white.withValues(alpha: 0.5))),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 56),

                  // Hero text
                  Text('Smart Learning\nStarts Here.',
                      style: GoogleFonts.poppins(
                          fontSize: 44,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1.1,
                          letterSpacing: -0.5)),
                  const SizedBox(height: 14),
                  Text(
                      'A complete platform for teachers,\nstudents, and parents.',
                      style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: Colors.white.withValues(alpha: 0.55),
                          height: 1.65)),

                  const SizedBox(height: 40),

                  // Feature list
                  ...[
                    (
                      Icons.auto_awesome_rounded,
                      'AI-Generated Tests & Answer Keys'
                    ),
                    (Icons.how_to_reg_rounded, 'Real-Time Attendance Tracking'),
                    (Icons.bar_chart_rounded, 'Smart Grade Analytics'),
                    (
                      Icons.account_balance_wallet_rounded,
                      'Fee Management & Receipts'
                    ),
                  ].map((f) => Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: AppColors.accent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Icon(f.$1,
                                  size: 16, color: AppColors.accentLight),
                            ),
                            const SizedBox(width: 12),
                            Text(f.$2,
                                style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    color: Colors.white.withValues(alpha: 0.8),
                                    fontWeight: FontWeight.w500)),
                          ],
                        ),
                      )),

                  const SizedBox(height: 48),

                  // Capsule — adapted from splash screen for dark background
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.22), width: 1),
                      color: Colors.white.withValues(alpha: 0.07),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.workspace_premium_rounded,
                            size: 18, color: Colors.white.withValues(alpha: 0.85)),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('25+ YEARS OF EXCELLENCE',
                                style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    letterSpacing: 1.4)),
                            Text('Trusted education since 1997',
                                style: GoogleFonts.poppins(
                                    fontSize: 10,
                                    color: Colors.white.withValues(alpha: 0.55),
                                    letterSpacing: 0.2)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebRightPanel(BuildContext context, AuthState auth) {
    return Container(
      color: const Color(0xFFF4F6FA),
      child: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Heading
                Text(_isRegister ? 'Request Access' : 'Welcome back',
                    style: GoogleFonts.poppins(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0D1B2A),
                        letterSpacing: -0.5)),
                const SizedBox(height: 4),
                Text(
                    _isRegister
                        ? 'Fill in your details and await admin approval.'
                        : 'Sign in to your MIND FORGE account.',
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: AppColors.textMuted)),
                const SizedBox(height: 4),
                Container(
                  width: 40,
                  height: 3,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                const SizedBox(height: 20),

                // Username
                TextField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: 'Username',
                    prefixIcon: const Icon(Icons.person_outline),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.divider)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.divider)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            BorderSide(color: AppColors.primary, width: 2)),
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.deny(RegExp(r'\s'))
                  ],
                ),

                // Register fields
                if (_isRegister) ...[
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedRole,
                    decoration: InputDecoration(
                      labelText: 'Register as',
                      prefixIcon: const Icon(Icons.badge_outlined),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: AppColors.divider)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              BorderSide(color: AppColors.primary, width: 2)),
                    ),
                    items: ['student', 'teacher', 'parent']
                        .map((r) => DropdownMenuItem(
                            value: r,
                            child: Text(r[0].toUpperCase() + r.substring(1))))
                        .toList(),
                    onChanged: (v) => setState(() {
                      _selectedRole = v ?? 'student';
                      _parentUsernameController.clear();
                      _parentMpinController.clear();
                      _selectedSubjects.clear();
                      _selectedTeacherSubjects.clear();
                      _selectedGrade = 8;
                    }),
                  ),
                  if (_selectedRole == 'student') ...[
                    const SizedBox(height: 14),
                    DropdownButtonFormField<int>(
                      initialValue: _selectedGrade,
                      decoration: InputDecoration(
                        labelText: 'Grade',
                        prefixIcon: const Icon(Icons.school_outlined),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: AppColors.divider)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                BorderSide(color: AppColors.primary, width: 2)),
                      ),
                      items: [8, 9, 10]
                          .map((g) => DropdownMenuItem(
                              value: g, child: Text('Grade $g')))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedGrade = v ?? 8),
                    ),
                    const SizedBox(height: 14),
                    Text('Additional Subjects',
                        style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: _subjectOptions.map((s) {
                        final sel = _selectedSubjects.contains(s.key);
                        return GestureDetector(
                          onTap: () => setState(() => sel
                              ? _selectedSubjects.remove(s.key)
                              : _selectedSubjects.add(s.key)),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: sel ? AppColors.primary : Colors.white,
                              border: Border.all(
                                  color: sel
                                      ? AppColors.primary
                                      : AppColors.divider),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(s.label,
                                style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    color: sel
                                        ? Colors.white
                                        : AppColors.textSecondary,
                                    fontWeight: sel
                                        ? FontWeight.w700
                                        : FontWeight.normal)),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _parentUsernameController,
                      decoration: InputDecoration(
                        labelText: "Parent's Username *",
                        helperText:
                            'Required. If the parent does not have an account yet, '
                            "one will be created with the Parent's MPIN you enter below.",
                        helperMaxLines: 3,
                        prefixIcon: const Icon(Icons.family_restroom),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: AppColors.divider)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                BorderSide(color: AppColors.primary, width: 2)),
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.deny(RegExp(r'\s'))
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _parentMpinController,
                      obscureText: _obscureParentMpin,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: InputDecoration(
                        labelText: "Parent's 6-digit MPIN *",
                        helperText:
                            "If the parent already has an account this must "
                            "match their MPIN. Don't reuse the student's MPIN.",
                        helperMaxLines: 3,
                        counterText: '',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureParentMpin
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () => setState(
                              () => _obscureParentMpin = !_obscureParentMpin),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: AppColors.divider)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                BorderSide(color: AppColors.primary, width: 2)),
                      ),
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                  ],
                  if (_selectedRole == 'teacher') ...[
                    const SizedBox(height: 14),
                    Text('Subjects you can teach',
                        style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: AppConstants.subjects.map((s) {
                        final sel = _selectedTeacherSubjects.contains(s);
                        return GestureDetector(
                          onTap: () => setState(() => sel
                              ? _selectedTeacherSubjects.remove(s)
                              : _selectedTeacherSubjects.add(s)),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 7),
                            decoration: BoxDecoration(
                              color: sel ? AppColors.primary : Colors.white,
                              border: Border.all(
                                  color: sel
                                      ? AppColors.primary
                                      : AppColors.divider),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(s,
                                style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    color: sel
                                        ? Colors.white
                                        : AppColors.textSecondary,
                                    fontWeight: sel
                                        ? FontWeight.w700
                                        : FontWeight.normal)),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],

                const SizedBox(height: 16),

                // MPIN label
                Text(
                    _isRegister
                        ? 'Set a 6-digit MPIN'
                        : 'Enter your 6-digit MPIN',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary)),
                const SizedBox(height: 10),

                // PIN dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(6, (i) {
                    final filled = _pin[i].isNotEmpty;
                    final active = i == _pinIndex;
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: 40,
                      height: 46,
                      decoration: BoxDecoration(
                        color: filled
                            ? AppColors.primary.withValues(alpha: 0.1)
                            : Colors.white,
                        border: Border.all(
                            color: active
                                ? AppColors.primary
                                : filled
                                    ? AppColors.primary.withValues(alpha: 0.5)
                                    : AppColors.divider,
                            width: active ? 2 : 1),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 4,
                              offset: const Offset(0, 2))
                        ],
                      ),
                      child: Center(
                          child: filled
                              ? Container(
                                  width: 9,
                                  height: 9,
                                  decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      shape: BoxShape.circle))
                              : null),
                    );
                  }),
                ),

                const SizedBox(height: 12),
                _buildPad(context),
                const SizedBox(height: 14),

                // Sign In button
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: auth.isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 3,
                    ),
                    child: auth.isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.white))
                        : Text(_isRegister ? 'Submit Registration' : 'Sign In',
                            style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 0.5)),
                  ),
                ),

                const SizedBox(height: 10),

                // Toggle link
                GestureDetector(
                  onTap: () => setState(() {
                    _isRegister = !_isRegister;
                    _clearPin();
                    _usernameController.clear();
                    _parentUsernameController.clear();
                    _parentMpinController.clear();
                    _selectedGrade = 8;
                    _selectedSubjects.clear();
                    _selectedTeacherSubjects.clear();
                  }),
                  child: Text(
                    _isRegister
                        ? 'Already have an account? Sign In'
                        : "Don't have an account? Request Access",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: AppColors.secondary,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }

  // ── Old brand panel (kept for reference — replaced above) ──────────────────
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
                            color:
                                isDel ? AppColors.error : AppColors.textPrimary,
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
  const _Tab({required this.label, required this.active, required this.onTap});

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
                fontWeight: active ? FontWeight.w700 : FontWeight.normal,
                color: active ? AppColors.textOnDark : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
