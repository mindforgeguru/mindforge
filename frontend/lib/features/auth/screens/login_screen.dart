import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/api/api_client.dart';
import '../../../core/utils/constants.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/school_logo.dart';
import '../providers/auth_provider.dart';

// ─── Whiteprint tokens ─────────────────────────────────────────────────────────
//
// The sign-in screen is the detail sheet of the Whiteprint drawing set the
// marketing front door opens with: a near-white drafting ground carrying a
// construction grid, every structure drawn with a 1.5px hairline, square
// corners, no shadow anywhere, and one warm accent that does annotation work.
//
// These are deliberately PRIVATE to this screen rather than added to
// `AppColors`. Sign-in happens before authentication, so it always runs on the
// default palette — but `AppColors` is swapped at runtime by the student XP
// theme-unlock system, and pushing this world in there would repaint the whole
// app. Nothing outside this file reads `_Wp`.
class _Wp {
  _Wp._();

  // Ground and sheet
  static const print_ = Color(0xFFE4EBF3); // drafting blue ground
  static const printDeep = Color(0xFFD6E0EB); // recessed field
  static const sheet = Color(0xFFF2F6FA); // the lifted drawing sheet
  static const white = Color(0xFFFBFDFF); // innermost plate

  // Line work
  static const navy = Color(0xFF112A4A); // logo navy — display, structure
  static const navyMid = Color(0xFF22436B);
  static const line = Color(0x4D112A4A); // .30 — structure hairline
  static const lineSoft = Color(0x26112A4A); // .15 — list hairline
  static const onPlate = Color(0xFFBFD2E6); // mono label on the navy plate

  // Heat — the one accent, used as annotation ink
  static const heat = Color(0xFFF55C1E); // marks, active cell, arrows
  static const heatRead = Color(0xFFAE3607); // the cut that reads as text
  static const heatWash = Color(0xFFFDF3EC); // the lightest heat tint
  static const scale = Color(0xFFF7D9A6); // heat label on the navy plate

  // Text
  static const body = Color(0xFF1B3355);
  static const mute = Color(0xFF4A5F7E);
  static const ok = Color(0xFF146B3F);
  static const alarm = Color(0xFFA32014);

  static const rule = 1.5; // the one hairline weight
  static const ctrlRadius = Radius.circular(3); // the single softening

  // ── Three voices: Rajdhani states, Karla explains, Spline Sans Mono labels ──

  /// Display — very large condensed caps.
  static TextStyle disp(double size,
          {Color color = navy, FontWeight weight = FontWeight.w700}) =>
      GoogleFonts.rajdhani(
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: 0.96,
        letterSpacing: -0.012 * size,
      );

  /// Title — Rajdhani at a readable size, still caps.
  static TextStyle title(double size,
          {Color color = navy, FontWeight weight = FontWeight.w600}) =>
      GoogleFonts.rajdhani(
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: 1.06,
        letterSpacing: 0.02 * size,
      );

  /// Running copy.
  static TextStyle text(double size, {Color color = body, FontWeight? weight}) =>
      GoogleFonts.karla(
        fontSize: size,
        fontWeight: weight ?? FontWeight.w400,
        color: color,
        height: 1.5,
      );

  /// Mono field key / dimension label. Never sets running prose.
  static TextStyle dim(double size,
          {Color color = navyMid, FontWeight weight = FontWeight.w500}) =>
      GoogleFonts.splineSansMono(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: size * 0.075,
        height: 1.35,
      );
}

/// The construction grid. A committed material in its own right, not a
/// backdrop: the form's cells are laid out on the same 16px module the fine
/// lines draw, so the armature the ground shows is the armature in use.
class _GridPainter extends CustomPainter {
  const _GridPainter();

  static const double fine = 16;
  static const double coarse = 96;

  @override
  void paint(Canvas canvas, Size size) {
    final finePaint = Paint()
      ..color = const Color(0x0E112A4A)
      ..strokeWidth = 1;
    final coarsePaint = Paint()
      ..color = const Color(0x1D112A4A)
      ..strokeWidth = 1;

    for (double x = 0; x <= size.width; x += fine) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), finePaint);
    }
    for (double y = 0; y <= size.height; y += fine) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), finePaint);
    }
    for (double x = 0; x <= size.width; x += coarse) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), coarsePaint);
    }
    for (double y = 0; y <= size.height; y += coarse) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), coarsePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => false;
}

/// Stable handles for tests. The visible copy on this screen is restyled
/// freely (labels are uppercased, the delete key is an icon), so tests find
/// controls by these keys rather than by their text.
abstract final class LoginKeys {
  static const loginTab = ValueKey('login.tab.login');
  static const registerTab = ValueKey('login.tab.register');
  static const school = ValueKey('login.school');
  static const username = ValueKey('login.username');
  static const role = ValueKey('login.role');
  static const phone = ValueKey('login.phone');
  static const email = ValueKey('login.email');
  static const modeToggle = ValueKey('login.modeToggle');
  static const submit = ValueKey('login.submit');
  static const pinDelete = ValueKey('login.pin.delete');
  static ValueKey<String> pinDigit(String d) => ValueKey('login.pin.$d');
}

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

  // School picker — usernames are per-school, so both login and registration
  // must be scoped to a school. Loaded once from the public /schools endpoint.
  List<Map<String, dynamic>> _schools = [];
  bool _schoolsLoading = true;
  int? _selectedSchoolId;

  // The platform owner has school_id NULL and is only found by the backend when
  // `school_id` is omitted entirely (see auth.py `_resolve_school`). The picker
  // still has to distinguish "owner chose the school-less option" from "nothing
  // chosen yet", so owner selection carries this sentinel and is mapped back to
  // null on the wire. Login only — you cannot register as owner.
  static const int _ownerSchoolSentinel = -1;

  int? get _schoolIdForRequest =>
      _selectedSchoolId == _ownerSchoolSentinel ? null : _selectedSchoolId;

  /// The picked school's uploaded logo (null when none / owner / unpicked).
  /// Drives the login header logo so it reflects the chosen school before the
  /// user is authenticated — where the app-wide school-logo provider can't
  /// yet know which school it is.
  String? get _pickedSchoolLogoUrl {
    final id = _selectedSchoolId;
    if (id == null || id == _ownerSchoolSentinel) return null;
    for (final s in _schools) {
      if (s['id'] == id) {
        final url = s['logo_url'] as String?;
        return (url != null && url.isNotEmpty) ? url : null;
      }
    }
    return null;
  }

  /// The picked school's name, shown in place of the "MIND FORGE" wordmark on
  /// the login header once a school is chosen. Null → "MIND FORGE".
  String? get _pickedSchoolName {
    final id = _selectedSchoolId;
    if (id == null || id == _ownerSchoolSentinel) return null;
    for (final s in _schools) {
      if (s['id'] == id) {
        final name = s['name'] as String?;
        return (name != null && name.isNotEmpty) ? name : null;
      }
    }
    return null;
  }

  // Register mode drops the owner entry, so a lingering sentinel would leave
  // the dropdown with a value matching no item — which trips an assertion.
  void _clearOwnerSelection() {
    if (_selectedSchoolId == _ownerSchoolSentinel) _selectedSchoolId = null;
  }

  static const _subjectOptions = [
    _Subject('economics', 'Economics', Icons.bar_chart_outlined),
    _Subject('computer', 'Computer', Icons.computer_outlined),
    _Subject('ai', 'AI', Icons.psychology_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _loadSchools();
  }

  Future<void> _loadSchools() async {
    try {
      final schools = await ref.read(apiClientProvider).getSchools();
      if (!mounted) return;
      setState(() {
        _schools = schools;
        // Auto-select when there's only one school so the field is pre-filled.
        if (schools.length == 1) {
          _selectedSchoolId = schools.first['id'] as int;
        }
        _schoolsLoading = false;
      });
    } catch (_) {
      // Network/endpoint failure — leave the picker empty. The backend still
      // resolves the sole school automatically for single-school deployments.
      if (!mounted) return;
      setState(() => _schoolsLoading = false);
    }
  }

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
    // A school must be chosen whenever the picker has options (usernames are
    // unique per school). Skipped only if the list failed to load, where the
    // backend falls back to the sole school. Signing in as the platform owner
    // counts as a choice — it deliberately sends no school at all.
    if (_schools.isNotEmpty && _selectedSchoolId == null) {
      _showSnack('Please select your school.');
      return;
    }
    // Belt and braces: the owner option is never rendered in register mode, so
    // a sentinel here means stale state rather than a real choice.
    if (_isRegister && _selectedSchoolId == _ownerSchoolSentinel) {
      _showSnack('Please select your school.');
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
        schoolId: _selectedSchoolId,
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
            color: _Wp.ok);
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
      try {
        await notifier.login(username, _enteredPin,
            schoolId: _schoolIdForRequest);
      } on MfaRequiredException {
        // Password was correct; this account has a second factor. Prompt for it
        // rather than surfacing an error — nothing has gone wrong.
        if (!mounted) return;
        await _promptForSecondFactor(username);
      }
    }
  }

  /// Collects a 6-digit authenticator code, or a recovery code if the phone is
  /// gone, and retries the sign-in with it.
  Future<void> _promptForSecondFactor(String username) async {
    final codeController = TextEditingController();
    var useRecovery = false;

    final submitted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: _Wp.navy.withValues(alpha: 0.42),
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: _Wp.sheet,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
            side: BorderSide(color: _Wp.navy, width: _Wp.rule),
          ),
          titlePadding: EdgeInsets.zero,
          title: _plateHeader('Two-factor authentication', 'Step 2 of 2'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                useRecovery
                    ? 'Enter one of the recovery codes you saved when you set '
                        'this up. Each code works once.'
                    : 'Enter the 6-digit code from your authenticator app.',
                style: _Wp.text(14.5),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: codeController,
                autofocus: true,
                style: _Wp.text(16, color: _Wp.navy),
                keyboardType:
                    useRecovery ? TextInputType.text : TextInputType.number,
                textCapitalization: useRecovery
                    ? TextCapitalization.characters
                    : TextCapitalization.none,
                decoration: _dec(
                  useRecovery ? 'Recovery code' : '6-digit code',
                  hint: useRecovery ? 'ABCD-EFGH-JKMN' : '123456',
                ),
                onSubmitted: (_) => Navigator.of(dialogContext).pop(true),
              ),
              const SizedBox(height: 4),
              TextButton(
                style: _linkStyle,
                onPressed: () => setDialogState(() {
                  useRecovery = !useRecovery;
                  codeController.clear();
                }),
                child: Text(
                  useRecovery
                      ? 'Use my authenticator app instead'
                      : "I don't have my phone",
                  style: _Wp.text(14, color: _Wp.heatRead,
                      weight: FontWeight.w700),
                ),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
          actions: [
            _OutlineKey(
              label: 'Cancel',
              onTap: () => Navigator.of(dialogContext).pop(false),
            ),
            const SizedBox(width: 10),
            _FilledKey(
              label: 'Verify',
              onTap: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        ),
      ),
    );

    final entered = codeController.text.trim();
    codeController.dispose();
    if (submitted != true || entered.isEmpty || !mounted) return;

    await ref.read(authProvider.notifier).login(
          username,
          _enteredPin,
          schoolId: _schoolIdForRequest,
          mfaCode: useRecovery ? null : entered,
          recoveryCode: useRecovery ? entered : null,
        );
  }

  void _showSnack(String msg, {Color? color}) {
    final ground = color ?? _Wp.alarm;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: _Wp.text(14.5, color: Colors.white)),
        backgroundColor: ground,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: ground, width: _Wp.rule),
        ),
      ),
    );
  }

  /// There is no self-service MPIN reset — recovery is admin-mediated (an admin
  /// sets a new MPIN from the Users screen). This just tells the user where to
  /// go; a parent can act for a student.
  void _showForgotMpinHelp() {
    showDialog<void>(
      context: context,
      barrierColor: _Wp.navy.withValues(alpha: 0.42),
      builder: (_) => AlertDialog(
        backgroundColor: _Wp.sheet,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: _Wp.navy, width: _Wp.rule),
        ),
        titlePadding: EdgeInsets.zero,
        title: _plateHeader('Forgot your MPIN?', 'Recovery'),
        content: Text(
          "For your security, your MPIN can't be recovered on your own.\n\n"
          "Ask your school's admin to reset it — they can set a new MPIN for "
          "you from their dashboard. A student can also ask their parent.",
          style: _Wp.text(14.5),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
        actions: [
          _FilledKey(
            label: 'Got it',
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  // ─── Shared Whiteprint parts ────────────────────────────────────────────────

  /// The navy plate header that caps a sheet or a dialog. The one place
  /// Plate Navy carries a filled area.
  static Widget _plateHeader(String label, String right) {
    return Container(
      width: double.infinity,
      color: _Wp.navy,
      padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: _Wp.dim(12.5, color: _Wp.onPlate, weight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          Text(right.toUpperCase(),
              style: _Wp.dim(12.5, color: _Wp.scale, weight: FontWeight.w600)),
        ],
      ),
    );
  }

  static final ButtonStyle _linkStyle = TextButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    minimumSize: const Size(0, 48),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  /// One field decoration for every input on the screen: square, hairline,
  /// white plate, heat focus. Mono label so the field reads as a title-block
  /// cell key rather than a floating placeholder.
  static InputDecoration _dec(
    String label, {
    IconData? icon,
    String? helper,
    String? hint,
    Widget? suffix,
  }) {
    OutlineInputBorder b(Color c, double w) => OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: c, width: w),
        );
    return InputDecoration(
      labelText: label.toUpperCase(),
      hintText: hint,
      helperText: helper,
      helperMaxLines: 3,
      helperStyle: _Wp.text(12.5, color: _Wp.mute),
      hintStyle: _Wp.text(15, color: _Wp.mute),
      labelStyle: _Wp.dim(12.5, color: _Wp.navyMid, weight: FontWeight.w600),
      floatingLabelStyle:
          _Wp.dim(12.5, color: _Wp.heatRead, weight: FontWeight.w600),
      prefixIcon: icon == null
          ? null
          : Icon(icon, size: 19, color: _Wp.navyMid),
      suffixIcon: suffix,
      filled: true,
      fillColor: _Wp.white,
      isDense: true,
      contentPadding: const EdgeInsets.fromLTRB(14, 15, 14, 15),
      border: b(_Wp.line, _Wp.rule),
      enabledBorder: b(_Wp.line, _Wp.rule),
      focusedBorder: b(_Wp.heat, 2),
      counterText: '',
    );
  }

  /// A selectable chip — square, hairline, filled navy when on. Used for
  /// teachable subjects and a student's additional subjects.
  Widget _chip({
    required String label,
    IconData? icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? _Wp.navy : _Wp.white,
          border: Border.all(
              color: selected ? _Wp.navy : _Wp.line, width: _Wp.rule),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 15, color: selected ? _Wp.scale : _Wp.navyMid),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: _Wp.text(13.5,
                  color: selected ? Colors.white : _Wp.body,
                  weight: selected ? FontWeight.w700 : FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  /// A mono caption naming the group of controls beneath it. This is a field
  /// label over a value, not a kicker over a heading.
  Widget _groupLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text.toUpperCase(),
            style: _Wp.dim(12.5, weight: FontWeight.w600)),
      );

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    ref.listen<AuthState>(authProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        _showSnack(next.error!);
        _clearPin();
      }
    });

    // Caret, selection and scrollbars ship with framework defaults that belong
    // to no design system; theme them from the palette like everything else.
    final themed = Theme.of(context).copyWith(
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: _Wp.heat,
        selectionColor: Color(0x33F55C1E),
        selectionHandleColor: _Wp.heat,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(_Wp.line),
        trackColor: WidgetStateProperty.all(_Wp.printDeep),
        radius: Radius.zero,
        thickness: WidgetStateProperty.all(9),
      ),
      iconTheme: const IconThemeData(color: _Wp.navyMid),
      splashColor: const Color(0x14F55C1E),
      highlightColor: const Color(0x0DF55C1E),
    );

    // Use wide web layout on screens >= 900px
    if (MediaQuery.of(context).size.width >= 900) {
      return Theme(data: themed, child: _buildWebScaffold(context, auth));
    }
    return Theme(data: themed, child: _buildMobileScaffold(context, auth));
  }

  // ─── Mobile layout — Sheet 2 alone ──────────────────────────────────────────

  Widget _buildMobileScaffold(BuildContext context, AuthState auth) {
    final sh = MediaQuery.of(context).size.height;
    final compact = sh < 700;
    // viewPadding.bottom covers BOTH 3-button nav (48dp) and gesture nav (30dp).
    // Clamp to a minimum of 32 so the Login button always clears the nav bar.
    final safeBottom =
        MediaQuery.of(context).viewPadding.bottom.clamp(32.0, 80.0);
    final hzPad = R.sp(context, 16);

    return Scaffold(
      backgroundColor: _Wp.print_,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // The construction ground, behind everything.
          const Positioned.fill(
            child: CustomPaint(painter: _GridPainter()),
          ),
          SafeArea(
            bottom: false, // sheet extends beneath the home indicator
            child: Column(
              children: [
                _mobileRail(context),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                        hzPad, compact ? 12 : 16, hzPad, safeBottom),
                    child: _formSheet(context, auth, compact: compact),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The hairline rail: school (or MindForge) mark, wordmark, tagline.
  Widget _mobileRail(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _Wp.navy, width: _Wp.rule)),
      ),
      padding: EdgeInsets.fromLTRB(R.sp(context, 16), 10, R.sp(context, 16), 10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _Wp.white,
              border: Border.all(color: _Wp.line, width: _Wp.rule),
            ),
            padding: const EdgeInsets.all(3),
            child: SchoolLogo(
                fit: BoxFit.contain, logoUrl: _pickedSchoolLogoUrl),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _pickedSchoolName ?? 'MIND FORGE',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.rajdhani(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: _Wp.navy,
                    letterSpacing: 2.6,
                    height: 1.1,
                  ),
                ),
                Text('AI assisted learning',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _Wp.text(12.5, color: _Wp.mute)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Web layout — a two-sheet drawing set ───────────────────────────────────

  Widget _buildWebScaffold(BuildContext context, AuthState auth) {
    return Scaffold(
      backgroundColor: _Wp.print_,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Sheet 1: the general arrangement ──────────────────────────
          Expanded(flex: 48, child: _buildWebLeftPanel(context)),
          // ── Sheet 2: the detail — the form ────────────────────────────
          Expanded(flex: 52, child: _buildWebRightPanel(context, auth)),
        ],
      ),
    );
  }

  Widget _buildWebLeftPanel(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _Wp.print_,
        border: Border(right: BorderSide(color: _Wp.navy, width: _Wp.rule)),
      ),
      child: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: _GridPainter())),
          // The sheet's drawn matter sits at the head; the approval stamp is
          // anchored at the foot the way a drawing's title block is, rather
          // than floating wherever the content happens to end.
          LayoutBuilder(
            builder: (context, viewport) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: viewport.maxHeight),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(48, 40, 44, 36),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                  // ── Brand plates ────────────────────────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _plate(
                        // 3.6MB source decoded down to the box it is drawn in.
                        child: Image.asset(
                          'assets/images/hansal_logo.png',
                          fit: BoxFit.contain,
                          cacheWidth: 160,
                          filterQuality: FilterQuality.medium,
                        ),
                      ),
                      Container(
                          width: _Wp.rule,
                          height: 54,
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          color: _Wp.line),
                      _plate(
                        child: SchoolLogo(
                            fit: BoxFit.contain,
                            logoUrl: _pickedSchoolLogoUrl),
                      ),
                      const SizedBox(width: 14),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _pickedSchoolName ?? 'MIND FORGE',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.rajdhani(
                                fontSize: 21,
                                fontWeight: FontWeight.w700,
                                color: _Wp.navy,
                                letterSpacing: 2.8,
                                height: 1.15,
                              ),
                            ),
                            Text('AI assisted learning',
                                style: _Wp.text(13, color: _Wp.mute)),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 44),

                  // ── Headline ────────────────────────────────────────
                  Text('Smart Learning\nStarts Here.'.toUpperCase(),
                      style: _Wp.disp(58)),
                  const SizedBox(height: 14),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 380),
                    child: Text(
                        'A complete platform for teachers, students, and '
                        'parents.',
                        style: _Wp.text(16)),
                  ),

                  const SizedBox(height: 34),

                  // ── Capability schedule ─────────────────────────────
                  Container(
                    decoration: const BoxDecoration(
                      border:
                          Border(top: BorderSide(color: _Wp.navy, width: _Wp.rule)),
                    ),
                    child: Column(
                      children: [
                        for (final f in const [
                          ('01', 'AI-Generated Tests & Answer Keys'),
                          ('02', 'Real-Time Attendance Tracking'),
                          ('03', 'Smart Grade Analytics'),
                          ('04', 'Fee Management & Receipts'),
                        ])
                          Container(
                            decoration: const BoxDecoration(
                              border: Border(
                                  bottom: BorderSide(
                                      color: _Wp.lineSoft, width: 1)),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 42,
                                  child: Text(f.$1,
                                      style: _Wp.dim(12.5,
                                          color: _Wp.heatRead,
                                          weight: FontWeight.w600)),
                                ),
                                Expanded(
                                  child: Text(f.$2,
                                      style: _Wp.title(21)),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                          ],
                        ),

                        // ── Approval stamp. Pre-existing owner claim,
                        //    restyled, not re-authored. See the surface
                        //    brief. ─────────────────────────────────────
                        Padding(
                          padding: const EdgeInsets.only(top: 40),
                          child: Container(
                            decoration: BoxDecoration(
                              color: _Wp.white,
                              border:
                                  Border.all(color: _Wp.line, width: _Wp.rule),
                            ),
                            padding: const EdgeInsets.fromLTRB(16, 12, 18, 13),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 3,
                                  height: 38,
                                  color: _Wp.heat,
                                  margin: const EdgeInsets.only(right: 14),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('25+ YEARS OF EXCELLENCE',
                                        style: _Wp.dim(12.5,
                                            color: _Wp.heatRead,
                                            weight: FontWeight.w600)),
                                    const SizedBox(height: 3),
                                    Text('Trusted education since 1997',
                                        style: _Wp.text(14)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A square white plate holding a logo. Depth is plate overlap, never shadow.
  Widget _plate({required Widget child}) => Container(
        width: 74,
        height: 74,
        decoration: BoxDecoration(
          color: _Wp.white,
          border: Border.all(color: _Wp.line, width: _Wp.rule),
        ),
        padding: const EdgeInsets.all(8),
        child: child,
      );

  Widget _buildWebRightPanel(BuildContext context, AuthState auth) {
    return Container(
      color: _Wp.print_,
      child: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: _GridPainter())),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 40),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 452),
                child: _formSheet(context, auth, compact: false),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Sheet 2: the form, built as a title block ──────────────────────────────

  Widget _formSheet(BuildContext context, AuthState auth,
      {required bool compact}) {
    final gap = compact ? 12.0 : 14.0;

    return Container(
      decoration: BoxDecoration(
        color: _Wp.sheet,
        border: Border.all(color: _Wp.navy, width: _Wp.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _plateHeader(
            _isRegister ? 'Request access' : 'Sign in',
            _isRegister ? 'Await approval' : 'Your school',
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, compact ? 14 : 18, 16, compact ? 16 : 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Tabs ────────────────────────────────────────────
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: _Wp.line, width: _Wp.rule),
                  ),
                  child: Row(
                    children: [
                      _Tab(
                        key: LoginKeys.loginTab,
                        label: 'Login',
                        active: !_isRegister,
                        onTap: () => setState(() {
                          _isRegister = false;
                          _clearPin();
                          _parentUsernameController.clear();
                          _parentMpinController.clear();
                        }),
                      ),
                      Container(width: _Wp.rule, height: 46, color: _Wp.line),
                      _Tab(
                        key: LoginKeys.registerTab,
                        label: 'Request Access',
                        active: _isRegister,
                        onTap: () => setState(() {
                          _isRegister = true;
                          _clearPin();
                          _clearOwnerSelection();
                        }),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: gap + 4),

                // ── School ──────────────────────────────────────────
                _schoolField(),
                if (!_schoolsLoading && _schools.isNotEmpty)
                  SizedBox(height: gap),

                // ── Username ────────────────────────────────────────
                TextField(
                  key: LoginKeys.username,
                  controller: _usernameController,
                  style: _Wp.text(16, color: _Wp.navy),
                  decoration: _dec('Username', icon: Icons.person_outline),
                  inputFormatters: [
                    FilteringTextInputFormatter.deny(RegExp(r'\s')),
                  ],
                  textInputAction: TextInputAction.done,
                ),

                // ── Register-only fields ────────────────────────────
                if (_isRegister) ...[
                  SizedBox(height: gap),
                  DropdownButtonFormField<String>(
                    key: LoginKeys.role,
                    initialValue: _selectedRole,
                    isExpanded: true,
                    style: _Wp.text(16, color: _Wp.navy),
                    decoration:
                        _dec('Register as', icon: Icons.badge_outlined),
                    dropdownColor: _Wp.white,
                    borderRadius: BorderRadius.zero,
                    items: ['student', 'teacher', 'parent']
                        .map((r) => DropdownMenuItem(
                              value: r,
                              child: Text(r[0].toUpperCase() + r.substring(1),
                                  style: _Wp.text(15.5, color: _Wp.navy)),
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

                  // ── Phone & Email ─────────────────────────────────
                  // Required for teacher/student (validated on submit),
                  // optional for parent.
                  SizedBox(height: gap),
                  TextField(
                    key: LoginKeys.phone,
                    controller: _phoneController,
                    style: _Wp.text(16, color: _Wp.navy),
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    decoration: _dec(
                      _selectedRole == 'parent'
                          ? 'Phone number (optional)'
                          : 'Phone number',
                      icon: Icons.phone_outlined,
                      helper: _selectedRole == 'student'
                          ? "You can use your parent's number."
                          : null,
                    ),
                  ),
                  SizedBox(height: gap),
                  TextField(
                    key: LoginKeys.email,
                    controller: _emailController,
                    style: _Wp.text(16, color: _Wp.navy),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: _dec(
                      'Email (optional)',
                      icon: Icons.email_outlined,
                      helper: _selectedRole == 'student'
                          ? "You can use your parent's email."
                          : null,
                    ),
                  ),

                  // ── Teacher-only ──────────────────────────────────
                  if (_selectedRole == 'teacher') ...[
                    SizedBox(height: gap + 2),
                    _groupLabel('Subjects you can teach'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: AppConstants.subjects
                          .map((s) => _chip(
                                label: s,
                                selected: _selectedTeacherSubjects.contains(s),
                                onTap: () => setState(() =>
                                    _selectedTeacherSubjects.contains(s)
                                        ? _selectedTeacherSubjects.remove(s)
                                        : _selectedTeacherSubjects.add(s)),
                              ))
                          .toList(),
                    ),
                  ],

                  // ── Student-only ──────────────────────────────────
                  if (_selectedRole == 'student') ...[
                    SizedBox(height: gap),
                    DropdownButtonFormField<int>(
                      initialValue: _selectedGrade,
                      isExpanded: true,
                      style: _Wp.text(16, color: _Wp.navy),
                      decoration: _dec('Grade', icon: Icons.school_outlined),
                      dropdownColor: _Wp.white,
                      borderRadius: BorderRadius.zero,
                      items: [8, 9, 10]
                          .map((g) => DropdownMenuItem(
                                value: g,
                                child: Text('Grade $g',
                                    style: _Wp.text(15.5, color: _Wp.navy)),
                              ))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _selectedGrade = v ?? 8),
                    ),
                    SizedBox(height: gap + 2),
                    _groupLabel('Additional subjects'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _subjectOptions
                          .map((s) => _chip(
                                label: s.label,
                                icon: s.icon,
                                selected: _selectedSubjects.contains(s.key),
                                onTap: () => setState(() =>
                                    _selectedSubjects.contains(s.key)
                                        ? _selectedSubjects.remove(s.key)
                                        : _selectedSubjects.add(s.key)),
                              ))
                          .toList(),
                    ),
                    SizedBox(height: gap + 2),
                    TextField(
                      controller: _parentUsernameController,
                      style: _Wp.text(16, color: _Wp.navy),
                      decoration: _dec(
                        "Parent's username *",
                        icon: Icons.family_restroom,
                        helper: 'Required. If the parent does not have an '
                            'account yet, one will be created with the '
                            "Parent's MPIN you enter below.",
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.deny(RegExp(r'\s')),
                      ],
                      textInputAction: TextInputAction.next,
                    ),
                    SizedBox(height: gap),
                    TextField(
                      controller: _parentMpinController,
                      obscureText: _obscureParentMpin,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      style: _Wp.text(16, color: _Wp.navy),
                      decoration: _dec(
                        "Parent's 6-digit MPIN *",
                        icon: Icons.lock_outline,
                        helper: 'If the parent already has an account this '
                            "must match their MPIN. Don't reuse the "
                            "student's MPIN.",
                        suffix: IconButton(
                          tooltip: _obscureParentMpin ? 'Show' : 'Hide',
                          icon: Icon(
                              _obscureParentMpin
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 19,
                              color: _Wp.navyMid),
                          onPressed: () => setState(
                              () => _obscureParentMpin = !_obscureParentMpin),
                        ),
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      textInputAction: TextInputAction.done,
                    ),
                  ],
                ],

                SizedBox(height: compact ? 16 : 20),

                // ── MPIN cells ──────────────────────────────────────
                Container(
                  decoration: const BoxDecoration(
                    border: Border(
                        top: BorderSide(color: _Wp.navy, width: _Wp.rule)),
                  ),
                  padding: EdgeInsets.only(top: compact ? 12 : 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              (_isRegister
                                      ? 'Set a 6-digit MPIN'
                                      : 'Enter your 6-digit MPIN')
                                  .toUpperCase(),
                              style: _Wp.dim(12.5, weight: FontWeight.w600),
                            ),
                          ),
                          Text('$_pinIndex / 6',
                              style: _Wp.dim(12.5,
                                  color: _pinIndex == 6
                                      ? _Wp.ok
                                      : _Wp.heatRead,
                                  weight: FontWeight.w600)),
                        ],
                      ),
                      SizedBox(height: compact ? 9 : 11),
                      _pinCells(context, compact: compact),
                      SizedBox(height: compact ? 12 : 14),
                      _buildPad(context),
                    ],
                  ),
                ),

                SizedBox(height: compact ? 14 : 16),

                // ── Submit ──────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: R.fluid(context, 52, min: 50, max: 58),
                  child: _FilledKey(
                    key: LoginKeys.submit,
                    label: _isRegister ? 'Submit registration' : 'Sign in',
                    loading: auth.isLoading,
                    expand: true,
                    onTap: auth.isLoading ? null : _submit,
                  ),
                ),

                // No self-service MPIN reset — point users to their admin
                // rather than leave them stuck at login.
                if (!_isRegister)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: TextButton(
                      style: _linkStyle,
                      onPressed: _showForgotMpinHelp,
                      child: Text('Forgot your MPIN?',
                          style: _Wp.text(14.5,
                              color: _Wp.heatRead, weight: FontWeight.w700)),
                    ),
                  ),

                // ── Mode toggle ─────────────────────────────────────
                Padding(
                  padding: EdgeInsets.only(top: _isRegister ? 8 : 0),
                  child: TextButton(
                    key: LoginKeys.modeToggle,
                    style: _linkStyle,
                    onPressed: () => setState(() {
                      _isRegister = !_isRegister;
                      _clearPin();
                      _clearOwnerSelection();
                      _usernameController.clear();
                      _parentUsernameController.clear();
                      _parentMpinController.clear();
                      _selectedGrade = 8;
                      _selectedSubjects.clear();
                      _selectedTeacherSubjects.clear();
                    }),
                    child: Text(
                      _isRegister
                          ? 'Already have an account? Sign in'
                          : "Don't have an account? Request access",
                      textAlign: TextAlign.center,
                      style: _Wp.text(14, color: _Wp.navyMid,
                          weight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Six square cells with their position number set in mono beneath — a
  /// dimensioned row rather than a string of dots. The cell being filled
  /// carries the heat border; filled cells carry a solid navy mark.
  Widget _pinCells(BuildContext context, {required bool compact}) {
    return LayoutBuilder(
      builder: (context, c) {
        const gap = 7.0;
        final cellW = ((c.maxWidth - gap * 5) / 6).clamp(34.0, 60.0);
        final cellH = compact ? 50.0 : 54.0;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(6, (i) {
            final filled = _pin[i].isNotEmpty;
            final active = i == _pinIndex;
            return Padding(
              padding: EdgeInsets.only(right: i == 5 ? 0 : gap),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    width: cellW,
                    height: cellH,
                    decoration: BoxDecoration(
                      color: filled ? _Wp.heatWash : _Wp.white,
                      border: Border.all(
                        color: active
                            ? _Wp.heat
                            : filled
                                ? _Wp.navy
                                : _Wp.line,
                        width: active ? 2 : _Wp.rule,
                      ),
                    ),
                    child: Center(
                      child: filled
                          ? Container(
                              width: 11,
                              height: 11,
                              color: _Wp.navy,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text('${i + 1}',
                      style: _Wp.dim(11.5,
                          color: active ? _Wp.heatRead : _Wp.mute,
                          weight: FontWeight.w600)),
                ],
              ),
            );
          }),
        );
      },
    );
  }

  // ── School picker ──────────────────────────────────────────────────────────
  // Shown on both Login and Request Access (usernames are unique per school).
  // Renders a spinner while loading and nothing at all if the list is empty or
  // failed to load — in which case the backend resolves a single-school
  // deployment on its own.
  Widget _schoolField() {
    if (_schoolsLoading) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            const SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: _Wp.heat),
            ),
            const SizedBox(width: 10),
            Text('LOADING SCHOOLS…', style: _Wp.dim(12.5)),
          ],
        ),
      );
    }
    if (_schools.isEmpty) return const SizedBox.shrink();

    return DropdownButtonFormField<int>(
      key: LoginKeys.school,
      initialValue: _selectedSchoolId,
      isExpanded: true,
      style: _Wp.text(16, color: _Wp.navy),
      dropdownColor: _Wp.white,
      borderRadius: BorderRadius.zero,
      decoration: _dec('School', icon: Icons.account_balance_outlined),
      hint: Text('Select your school', style: _Wp.text(15.5, color: _Wp.mute)),
      items: [
        ..._schools.map((s) => DropdownMenuItem<int>(
              value: s['id'] as int,
              child: Text(s['name'] as String,
                  overflow: TextOverflow.ellipsis,
                  style: _Wp.text(15.5, color: _Wp.navy)),
            )),
        // Platform owner belongs to no school; sending a school_id would make
        // the backend miss the account entirely (401). Sign-in only.
        if (!_isRegister)
          DropdownMenuItem<int>(
            value: _ownerSchoolSentinel,
            child: Text('Platform owner (no school)',
                overflow: TextOverflow.ellipsis,
                style: _Wp.text(15.5,
                    color: _Wp.mute)
                    .copyWith(fontStyle: FontStyle.italic)),
          ),
      ],
      onChanged: (v) => setState(() => _selectedSchoolId = v),
    );
  }

  /// The keypad — a square hairline key grid. Keys fill the available width
  /// (flex: 1) and never fall below a 48 logical-px tap target.
  Widget _buildPad(BuildContext context) {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', '⌫'],
    ];
    final keyH = R.fluid(context, 50, min: 48, max: 58);
    const gap = 7.0;

    return Column(
      children: rows.map((row) {
        return Padding(
          padding: const EdgeInsets.only(bottom: gap),
          child: Row(
            children: [
              for (int i = 0; i < row.length; i++) ...[
                if (i > 0) const SizedBox(width: gap),
                Expanded(
                  child: row[i].isEmpty
                      // Invisible spacer — same flex weight as a real key.
                      ? SizedBox(height: keyH)
                      : _PadKey(
                          key: row[i] == '⌫'
                              ? LoginKeys.pinDelete
                              : LoginKeys.pinDigit(row[i]),
                          label: row[i],
                          height: keyH,
                          isDelete: row[i] == '⌫',
                          onTap: () {
                            HapticFeedback.lightImpact();
                            row[i] == '⌫' ? _tapDelete() : _tapDigit(row[i]);
                          },
                        ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ─── Controls ──────────────────────────────────────────────────────────────────

/// A single keypad key. Square, hairline, Rajdhani numeral; the ground inverts
/// to navy while pressed rather than glowing.
class _PadKey extends StatefulWidget {
  final String label;
  final double height;
  final bool isDelete;
  final VoidCallback onTap;
  const _PadKey({
    super.key,
    required this.label,
    required this.height,
    required this.isDelete,
    required this.onTap,
  });

  @override
  State<_PadKey> createState() => _PadKeyState();
}

class _PadKeyState extends State<_PadKey> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final fg = _down
        ? Colors.white
        : widget.isDelete
            ? _Wp.heatRead
            : _Wp.navy;
    return Semantics(
      button: true,
      label: widget.isDelete ? 'Delete last digit' : widget.label,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          height: widget.height,
          decoration: BoxDecoration(
            color: _down
                ? (widget.isDelete ? _Wp.heatRead : _Wp.navy)
                : _Wp.white,
            border: Border.all(
                color: _down
                    ? (widget.isDelete ? _Wp.heatRead : _Wp.navy)
                    : _Wp.line,
                width: _Wp.rule),
          ),
          child: Center(
            child: widget.isDelete
                ? Icon(Icons.backspace_outlined, size: 19, color: fg)
                : Text(widget.label,
                    style: GoogleFonts.rajdhani(
                      fontSize: 25,
                      fontWeight: FontWeight.w600,
                      color: fg,
                      height: 1,
                    )),
          ),
        ),
      ),
    );
  }
}

/// The page's one filled control: ink ground, paper text, heat on hover.
class _FilledKey extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  final bool expand;
  const _FilledKey({
    super.key,
    required this.label,
    required this.onTap,
    this.loading = false,
    this.expand = false,
  });

  @override
  State<_FilledKey> createState() => _FilledKeyState();
}

class _FilledKeyState extends State<_FilledKey> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onTap == null;
    final ground = disabled
        ? _Wp.navy.withValues(alpha: 0.45)
        : _hover
            ? _Wp.heatRead
            : _Wp.navy;
    return Semantics(
      button: true,
      enabled: !disabled,
      label: widget.label,
      child: InkWell(
        onTap: widget.onTap,
        onHover: (h) => setState(() => _hover = h),
        focusColor: const Color(0x33F55C1E),
        borderRadius: const BorderRadius.all(_Wp.ctrlRadius),
        mouseCursor:
            disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          constraints: const BoxConstraints(minHeight: 48),
          width: widget.expand ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          decoration: BoxDecoration(
            color: ground,
            border: Border.all(color: ground, width: _Wp.rule),
            borderRadius: const BorderRadius.all(_Wp.ctrlRadius),
          ),
          child: Center(
            child: widget.loading
                ? const SizedBox(
                    width: 21,
                    height: 21,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: Colors.white),
                  )
                : Text(
                    widget.label.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.rajdhani(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 1.6,
                      height: 1.1,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// The outlined secondary control. Hover inverts ground and text.
class _OutlineKey extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _OutlineKey({required this.label, required this.onTap});

  @override
  State<_OutlineKey> createState() => _OutlineKeyState();
}

class _OutlineKeyState extends State<_OutlineKey> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      child: InkWell(
        onTap: widget.onTap,
        onHover: (h) => setState(() => _hover = h),
        focusColor: const Color(0x33F55C1E),
        borderRadius: const BorderRadius.all(_Wp.ctrlRadius),
        mouseCursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          decoration: BoxDecoration(
            color: _hover ? _Wp.navy : Colors.transparent,
            border: Border.all(color: _Wp.navy, width: _Wp.rule),
            borderRadius: const BorderRadius.all(_Wp.ctrlRadius),
          ),
          child: Center(
            child: Text(
              widget.label.toUpperCase(),
              style: GoogleFonts.rajdhani(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _hover ? Colors.white : _Wp.navy,
                letterSpacing: 1.6,
                height: 1.1,
              ),
            ),
          ),
        ),
      ),
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

// ─── Tab ───────────────────────────────────────────────────────────────────────

class _Tab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _Tab(
      {super.key,
      required this.label,
      required this.active,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        selected: active,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            // Vertical padding keeps the tap target >= 48 logical px.
            constraints: const BoxConstraints(minHeight: 46),
            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 8),
            color: active ? _Wp.navy : Colors.transparent,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.rajdhani(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: active ? Colors.white : _Wp.navyMid,
                    letterSpacing: 1.3,
                    height: 1.1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
