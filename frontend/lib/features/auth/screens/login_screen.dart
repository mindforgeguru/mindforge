import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/school_grades_provider.dart';
import '../../../core/utils/constants.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/school_logo.dart';
import '../providers/auth_provider.dart';

// ─── Sign-in palette & type ─────────────────────────────────────────────────────
//
// The COLOURS here are unchanged from the screen's prior build — the drafting
// blue ground, the logo navy, the one warm heat accent. Only the LAYOUT and the
// TYPE voices are new: the construction-grid drawing set is replaced by a solid
// navy brand panel beside a soft, rounded form card, and the three condensed /
// mono voices are replaced by two — a warm Fraunces serif for display and a
// humanist Instrument Sans for everything that is read or tapped.
//
// These tokens stay PRIVATE to this screen. Sign-in runs before authentication,
// so it always draws on the default palette — but `AppColors` is swapped at
// runtime by the student XP theme-unlock system, and pushing this world in
// there would repaint the whole app. Nothing outside this file reads `_Wp`.
class _Wp {
  _Wp._();

  // Ground and sheet (unchanged)
  static const print_ = Color(0xFFE4EBF3); // page ground
  static const printDeep = Color(0xFFD6E0EB); // recessed field
  static const sheet = Color(0xFFF2F6FA); // lifted card on mobile
  static const white = Color(0xFFFBFDFF); // card / field fill

  // Navy — now a filled brand field, not only line work (unchanged values)
  static const navy = Color(0xFF112A4A);
  static const navyMid = Color(0xFF22436B);
  static const line = Color(0x4D112A4A); // .30 — field hairline
  static const lineSoft = Color(0x26112A4A); // .15 — list hairline
  static const onPlate = Color(0xFFBFD2E6); // text on the navy panel

  // Heat — the one accent (unchanged)
  static const heat = Color(0xFFF55C1E); // active cell, focus, caret
  static const heatRead = Color(0xFFAE3607); // heat that reads as text
  static const heatWash = Color(0xFFFDF3EC); // lightest heat tint
  static const scale = Color(0xFFF7D9A6); // heat label on the navy panel

  // Text (unchanged)
  static const body = Color(0xFF1B3355);
  static const mute = Color(0xFF4A5F7E);
  static const ok = Color(0xFF146B3F);
  static const alarm = Color(0xFFA32014);

  static const rule = 1.5; // hairline weight

  // New soft geometry — the layout's depth system (colours unchanged).
  static const rField = 11.0;
  static const rCard = 20.0;
  static const rKey = 14.0;
  static const rPill = 100.0;

  /// A real shadow: offset + soft blur, tinted from the navy, never a flat halo.
  static const List<BoxShadow> lift = [
    BoxShadow(color: Color(0x1A112A4A), blurRadius: 30, offset: Offset(0, 16)),
    BoxShadow(color: Color(0x0F112A4A), blurRadius: 4, offset: Offset(0, 2)),
  ];
  static const List<BoxShadow> liftKey = [
    BoxShadow(color: Color(0x26112A4A), blurRadius: 14, offset: Offset(0, 7)),
  ];

  // ── Two voices: Fraunces carries the display, Instrument Sans everything read ──

  /// Display — warm serif, mixed case, tight.
  static TextStyle disp(double size,
          {Color color = navy, FontWeight weight = FontWeight.w600}) =>
      GoogleFonts.fraunces(
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: 1.0,
        letterSpacing: -0.02 * size,
      );

  /// Running copy and field values.
  static TextStyle text(double size, {Color color = body, FontWeight? weight}) =>
      GoogleFonts.instrumentSans(
        fontSize: size,
        fontWeight: weight ?? FontWeight.w400,
        color: color,
        height: 1.5,
      );

  /// A small tracked label naming the group of controls it sits over. Uppercase
  /// comes from the call site; the tracking and weight come from here.
  static TextStyle dim(double size,
          {Color color = navyMid, FontWeight weight = FontWeight.w600}) =>
      GoogleFonts.instrumentSans(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: size * 0.09,
        height: 1.4,
      );
}

/// Stable handles for tests. The visible copy on this screen is restyled
/// freely, so tests find controls by these keys rather than by their text.
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

class _LoginScreenState extends ConsumerState<LoginScreen>
    with WidgetsBindingObserver {
  final _usernameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _parentUsernameController = TextEditingController();
  final _parentMpinController = TextEditingController();
  bool _obscureParentMpin = true;
  final List<String> _pin = ['', '', '', '', '', ''];
  int _pinIndex = 0;
  // The MPIN cells as one tab stop, so a keyboard can type the MPIN — the
  // keypad's keys are tap-only.
  final _pinFocus = FocusNode(debugLabel: 'mpin');
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
  // Bumped when a refresh changes the list, so the picker is rebuilt rather
  // than left holding a school that's gone.
  int _schoolsVersion = 0;

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

  /// The picked school's name, shown in place of the "MindForge" wordmark on
  /// the header once a school is chosen. Null → "MindForge".
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

  /// The grades the picked school teaches (#5); every supported grade until a
  /// school is picked.
  List<int> get _pickedSchoolGrades {
    final id = _selectedSchoolId;
    for (final s in _schools) {
      if (s['id'] == id) return gradesOffered(s);
    }
    return gradesOffered(null);
  }

  /// The student's grade, moved to the picked school's first grade when the
  /// school doesn't teach the one chosen earlier.
  int get _effectiveGrade {
    final grades = _pickedSchoolGrades;
    return grades.contains(_selectedGrade) ? _selectedGrade : grades.first;
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
    WidgetsBinding.instance.addObserver(this);
    _loadSchools();
  }

  // The list was loaded once, so a school suspended or restored while this
  // screen sat open only showed up after an app restart (#27). Reload it each
  // time the app (or browser tab) comes back to the foreground.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_schoolsLoading) _loadSchools();
  }

  Future<void> _loadSchools() async {
    try {
      final schools = await ref.read(apiClientProvider).getSchools();
      if (!mounted) return;
      String ids(List<Map<String, dynamic>> l) =>
          l.map((s) => '${s['id']}:${s['grades_offered']}').join(',');
      if (!_schoolsLoading && ids(schools) == ids(_schools)) return;
      setState(() {
        _schoolsVersion++;
        _schools = schools;
        final picked = _selectedSchoolId;
        if (picked != null &&
            picked != _ownerSchoolSentinel &&
            !schools.any((s) => s['id'] == picked)) {
          _selectedSchoolId = null;
        }
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
    WidgetsBinding.instance.removeObserver(this);
    _usernameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _parentUsernameController.dispose();
    _parentMpinController.dispose();
    _pinFocus.dispose();
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

  static final _digitKeys = {
    for (var d = 0; d <= 9; d++) ...{
      LogicalKeyboardKey(LogicalKeyboardKey.digit0.keyId + d): '$d',
      LogicalKeyboardKey(LogicalKeyboardKey.numpad0.keyId + d): '$d',
    },
  };

  /// Typed digits, Backspace and Enter while the MPIN cells have focus.
  KeyEventResult _onPinKey(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final digit = _digitKeys[key];
    if (digit != null) {
      _tapDigit(digit);
    } else if (key == LogicalKeyboardKey.backspace) {
      _tapDelete();
    } else if (event is KeyDownEvent &&
        (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter)) {
      if (!ref.read(authProvider).isLoading) _submit();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
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
      // The server now requires it too; say so here instead of after a round trip.
      if (isTeacher && _selectedTeacherSubjects.isEmpty) {
        _showSnack('Choose at least one subject you teach.');
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
        grade: isStudent ? _effectiveGrade : null,
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
    final result = await showDialog<_SecondFactorEntry>(
      context: context,
      barrierDismissible: false,
      barrierColor: _Wp.navy.withValues(alpha: 0.42),
      builder: (_) => const _SecondFactorDialog(),
    );

    if (result == null || result.code.isEmpty || !mounted) return;

    await ref.read(authProvider.notifier).login(
          username,
          _enteredPin,
          schoolId: _schoolIdForRequest,
          mfaCode: result.recovery ? null : result.code,
          recoveryCode: result.recovery ? result.code : null,
        );
  }

  void _showSnack(String msg, {Color? color}) {
    final ground = color ?? _Wp.alarm;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: _Wp.text(14.5, color: Colors.white)),
        backgroundColor: ground,
        behavior: SnackBarBehavior.floating,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_Wp.rField),
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
        backgroundColor: _Wp.white,
        surfaceTintColor: Colors.transparent,
        elevation: 10,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_Wp.rCard),
        ),
        titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
        title: _plateHeader('Forgot your MPIN?', 'Recovery'),
        contentPadding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
        content: Text(
          "For your security, your MPIN can't be recovered on your own.\n\n"
          "Ask your school's admin to reset it — they can set a new MPIN for "
          "you from their dashboard. A student can also ask their parent.",
          style: _Wp.text(14.5),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(22, 10, 22, 18),
        actions: [
          _FilledKey(
            label: 'Got it',
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  // ─── Shared parts ───────────────────────────────────────────────────────────

  /// A card / dialog header: a serif title with a small tracked label beneath,
  /// closed by a hairline. Replaces the old filled navy plate bar.
  static Widget _plateHeader(String label, String right) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(right.toUpperCase(),
            style: _Wp.dim(11.5, color: _Wp.heatRead, weight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(label, style: _Wp.disp(26)),
        const SizedBox(height: 14),
        Container(height: _Wp.rule, color: _Wp.lineSoft),
      ],
    );
  }

  static final ButtonStyle _linkStyle = TextButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_Wp.rField)),
    minimumSize: const Size(0, 48),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  /// One field decoration for every input on the screen: a soft rounded white
  /// field with a hairline border and a heat focus ring.
  static InputDecoration _dec(
    String label, {
    IconData? icon,
    String? helper,
    String? hint,
    Widget? suffix,
  }) {
    OutlineInputBorder b(Color c, double w) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(_Wp.rField),
          borderSide: BorderSide(color: c, width: w),
        );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      helperMaxLines: 3,
      helperStyle: _Wp.text(12.5, color: _Wp.mute),
      hintStyle: _Wp.text(15, color: _Wp.mute),
      labelStyle: _Wp.text(15, color: _Wp.navyMid),
      floatingLabelStyle:
          _Wp.dim(12.5, color: _Wp.heatRead, weight: FontWeight.w700),
      prefixIcon: icon == null
          ? null
          : Icon(icon, size: 19, color: _Wp.navyMid),
      suffixIcon: suffix,
      filled: true,
      fillColor: _Wp.white,
      isDense: true,
      contentPadding: const EdgeInsets.fromLTRB(16, 17, 16, 17),
      border: b(_Wp.line, _Wp.rule),
      enabledBorder: b(_Wp.line, _Wp.rule),
      focusedBorder: b(_Wp.heat, 2),
      counterText: '',
    );
  }

  /// A selectable pill — hairline when off, filled navy when on. Used for
  /// teachable subjects and a student's additional subjects.
  Widget _chip({
    required String label,
    IconData? icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_Wp.rPill),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          constraints: const BoxConstraints(minHeight: 42),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? _Wp.navy : _Wp.white,
            borderRadius: BorderRadius.circular(_Wp.rPill),
            border: Border.all(
                color: selected ? _Wp.navy : _Wp.line, width: _Wp.rule),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon,
                    size: 16, color: selected ? _Wp.scale : _Wp.navyMid),
                const SizedBox(width: 7),
              ],
              Text(
                label,
                style: _Wp.text(13.5,
                    color: selected ? Colors.white : _Wp.body,
                    weight: selected ? FontWeight.w600 : FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A small tracked caption naming the group of controls beneath it.
  Widget _groupLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Text(text.toUpperCase(),
            style: _Wp.dim(12, weight: FontWeight.w700)),
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
        trackColor: WidgetStateProperty.all(Colors.transparent),
        radius: const Radius.circular(8),
        thickness: WidgetStateProperty.all(8),
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

  // ─── Mobile layout — navy header band over the form card ─────────────────────

  Widget _buildMobileScaffold(BuildContext context, AuthState auth) {
    final sh = MediaQuery.of(context).size.height;
    // Every iPhone below the Max/Plus sizes (874 pt on a 17 Pro) needs the
    // tighter layout, or Sign in sits below the fold (run-log #3).
    final compact = sh < 900;
    // viewPadding.bottom covers BOTH 3-button nav (48dp) and gesture nav (30dp).
    // Clamp to a minimum of 32 so the Login button always clears the nav bar.
    final safeBottom =
        MediaQuery.of(context).viewPadding.bottom.clamp(32.0, 80.0);
    final hzPad = R.sp(context, 16);

    // The navy header runs up behind the status bar, whose icons are white:
    // before, the strip behind them was the light page background, so the
    // clock and battery were white on near-white (run-log #3).
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent),
      child: Scaffold(
      backgroundColor: _Wp.print_,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        top: false,
        bottom: false, // card extends beneath the home indicator
        child: Column(
          children: [
            ColoredBox(
              color: _Wp.navy,
              child: SafeArea(
                bottom: false,
                child: _mobileHeader(context, compact: compact),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                    hzPad, compact ? 14 : 18, hzPad, safeBottom),
                child: _Entrance(
                  child: _formCard(context, auth, compact: compact),
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  /// The navy header band: school (or MindForge) mark, wordmark, tagline.
  Widget _mobileHeader(BuildContext context, {required bool compact}) {
    final hz = R.sp(context, 16);
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(color: _Wp.navy),
      padding: EdgeInsets.fromLTRB(hz, compact ? 10 : 22, hz, compact ? 12 : 24),
      child: Row(
        children: [
          _logoTile(compact ? 40 : 44, logoUrl: _pickedSchoolLogoUrl),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _pickedSchoolName ?? 'MindForge',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _Wp.disp(24, color: Colors.white),
                ),
                const SizedBox(height: 2),
                Text('AI assisted learning',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _Wp.text(12.5, color: _Wp.onPlate)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Web layout — navy brand panel beside the form card ──────────────────────

  Widget _buildWebScaffold(BuildContext context, AuthState auth) {
    return Scaffold(
      backgroundColor: _Wp.print_,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 50, child: _buildWebBrandPanel(context)),
          Expanded(flex: 50, child: _buildWebFormPanel(context, auth)),
        ],
      ),
    );
  }

  Widget _buildWebBrandPanel(BuildContext context) {
    return Container(
      color: _Wp.navy,
      child: LayoutBuilder(
        builder: (context, viewport) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: viewport.maxHeight),
            child: IntrinsicHeight(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(56, 52, 52, 44),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ── Brand marks ──────────────────────────────────
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // The picked school's logo, or the MindForge mark
                            // before one is picked. A fixed Hansel & Gretel
                            // tile used to show here for every school.
                            _logoTile(56, logoUrl: _pickedSchoolLogoUrl),
                            const SizedBox(width: 16),
                            Flexible(
                              child: Text(
                                _pickedSchoolName ?? 'MindForge',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: _Wp.disp(24, color: Colors.white),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 56),

                        // ── Headline ─────────────────────────────────────
                        Text('Smart learning\nstarts here.',
                            style: _Wp.disp(60, color: Colors.white)),
                        const SizedBox(height: 18),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 400),
                          child: Text(
                            'A complete platform for teachers, students, and '
                            'parents.',
                            style: _Wp.text(16.5, color: _Wp.onPlate),
                          ),
                        ),

                        const SizedBox(height: 40),

                        // ── Capability list ──────────────────────────────
                        for (final f in const [
                          (Icons.auto_awesome_outlined,
                              'AI-generated tests & answer keys'),
                          (Icons.how_to_reg_outlined,
                              'Real-time attendance tracking'),
                          (Icons.insights_outlined, 'Smart grade analytics'),
                          (Icons.receipt_long_outlined,
                              'Fee management & receipts'),
                        ])
                          Padding(
                            padding: const EdgeInsets.only(bottom: 18),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Icon(f.$1, size: 21, color: _Wp.heat),
                                const SizedBox(width: 15),
                                Expanded(
                                  child: Text(f.$2,
                                      style: _Wp.text(16,
                                          color: Colors.white,
                                          weight: FontWeight.w500)),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),

                    // The "25+ years · since 1997" trust mark was Hansel &
                    // Gretel's claim, shown on every school's login; removed.
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWebFormPanel(BuildContext context, AuthState auth) {
    return Container(
      color: _Wp.print_,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 44),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 452),
            child: _Entrance(child: _formCard(context, auth, compact: false)),
          ),
        ),
      ),
    );
  }

  /// A square-cornered white tile holding a logo, with a soft lift. Used in the
  /// navy header / panel where the logos need a light ground to read on.
  Widget _logoTile(double size, {String? logoUrl, Widget? child}) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: _Wp.white,
          borderRadius: BorderRadius.circular(size * 0.26),
          boxShadow: _Wp.liftKey,
        ),
        padding: EdgeInsets.all(size * 0.16),
        child: child ??
            SchoolLogo(fit: BoxFit.contain, logoUrl: logoUrl),
      );

  // ─── The form card ───────────────────────────────────────────────────────────

  Widget _formCard(BuildContext context, AuthState auth,
      {required bool compact}) {
    final gap = compact ? 12.0 : 14.0;

    return Container(
      decoration: BoxDecoration(
        color: _Wp.white,
        borderRadius: BorderRadius.circular(_Wp.rCard),
        boxShadow: _Wp.lift,
      ),
      padding: EdgeInsets.fromLTRB(
          compact ? 18 : 26, compact ? 16 : 28, compact ? 18 : 26, compact ? 20 : 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header ──────────────────────────────────────────
          Text(
            _isRegister ? 'Request access' : 'Welcome back',
            style: _Wp.disp(compact ? 28 : 32),
          ),
          const SizedBox(height: 5),
          Text(
            _isRegister
                ? 'Create your account — an admin approves it before you sign in.'
                : 'Sign in to your school account.',
            style: _Wp.text(14.5, color: _Wp.mute),
          ),
          SizedBox(height: compact ? 14 : 22),

          // ── Segmented toggle ────────────────────────────────
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: _Wp.printDeep,
              borderRadius: BorderRadius.circular(_Wp.rPill),
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

          SizedBox(height: gap + 6),

          // ── School ──────────────────────────────────────────
          _schoolField(),
          if (!_schoolsLoading && _schools.isNotEmpty) SizedBox(height: gap),

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
              decoration: _dec('Register as', icon: Icons.badge_outlined),
              dropdownColor: _Wp.white,
              borderRadius: BorderRadius.circular(_Wp.rField),
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
                // Rebuilt per school: its grade list can differ.
                key: ValueKey(_selectedSchoolId),
                initialValue: _effectiveGrade,
                isExpanded: true,
                style: _Wp.text(16, color: _Wp.navy),
                decoration: _dec('Grade', icon: Icons.school_outlined),
                dropdownColor: _Wp.white,
                borderRadius: BorderRadius.circular(_Wp.rField),
                items: _pickedSchoolGrades
                    .map((g) => DropdownMenuItem(
                          value: g,
                          child: Text('Grade $g',
                              style: _Wp.text(15.5, color: _Wp.navy)),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _selectedGrade = v ?? 8),
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

          SizedBox(height: compact ? 18 : 22),

          // ── MPIN ────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Text(
                  (_isRegister
                          ? 'Set a 6-digit MPIN'
                          : 'Enter your 6-digit MPIN')
                      .toUpperCase(),
                  style: _Wp.dim(12, weight: FontWeight.w700),
                ),
              ),
              Text('$_pinIndex / 6',
                  style: _Wp.dim(12,
                      color: _pinIndex == 6 ? _Wp.ok : _Wp.heatRead,
                      weight: FontWeight.w700)),
            ],
          ),
          SizedBox(height: compact ? 10 : 12),
          Focus(
            focusNode: _pinFocus,
            onKeyEvent: _onPinKey,
            onFocusChange: (_) => setState(() {}),
            child: Semantics(
              label: 'MPIN, $_pinIndex of 6 digits entered',
              child: GestureDetector(
                onTap: _pinFocus.requestFocus,
                child: _pinCells(context, compact: compact),
              ),
            ),
          ),
          SizedBox(height: compact ? 14 : 16),
          _buildPad(context, compact: compact),

          SizedBox(height: compact ? 16 : 20),

          // ── Submit ──────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: R.fluid(context, 54, min: 52, max: 60),
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
              padding: const EdgeInsets.only(top: 6),
              child: TextButton(
                style: _linkStyle,
                onPressed: _showForgotMpinHelp,
                child: Text('Forgot your MPIN?',
                    style: _Wp.text(14.5,
                        color: _Wp.heatRead, weight: FontWeight.w600)),
              ),
            ),

          // ── Mode toggle ─────────────────────────────────────
          Padding(
            padding: EdgeInsets.only(top: _isRegister ? 10 : 2),
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
                style:
                    _Wp.text(14, color: _Wp.navyMid, weight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Six rounded cells: the one being filled carries the heat ring, filled
  /// cells carry a solid navy dot. A clean indicator row, no dimension numbers.
  Widget _pinCells(BuildContext context, {required bool compact}) {
    return LayoutBuilder(
      builder: (context, c) {
        // No minimum width: a floor forced the row wider than the card on
        // narrow phones. The gap tightens instead so the cells keep width.
        final gap = c.maxWidth < 260 ? 6.0 : 9.0;
        final cellW = ((c.maxWidth - gap * 5) / 6).clamp(0.0, 62.0);
        final cellH = compact ? 50.0 : 54.0;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(6, (i) {
            final filled = _pin[i].isNotEmpty;
            final active = i == _pinIndex && _pinFocus.hasFocus;
            final markFilling = i == _pinIndex && !_pinFocus.hasFocus;
            return Padding(
              padding: EdgeInsets.only(right: i == 5 ? 0 : gap),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: cellW,
                height: cellH,
                decoration: BoxDecoration(
                  color: filled ? _Wp.heatWash : _Wp.sheet,
                  borderRadius: BorderRadius.circular(_Wp.rField),
                  border: Border.all(
                    color: active || markFilling
                        ? _Wp.heat
                        : filled
                            ? _Wp.navy
                            : _Wp.line,
                    width: active || markFilling ? 2 : _Wp.rule,
                  ),
                ),
                child: Center(
                  child: filled
                      ? Container(
                          width: 12,
                          height: 12,
                          decoration: const BoxDecoration(
                            color: _Wp.navy,
                            shape: BoxShape.circle,
                          ),
                        )
                      : null,
                ),
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
              child:
                  CircularProgressIndicator(strokeWidth: 2, color: _Wp.heat),
            ),
            const SizedBox(width: 10),
            Text('LOADING SCHOOLS…', style: _Wp.dim(12)),
          ],
        ),
      );
    }
    if (_schools.isEmpty) return const SizedBox.shrink();

    return KeyedSubtree(
      key: ValueKey(_schoolsVersion),
      child: DropdownButtonFormField<int>(
      key: LoginKeys.school,
      initialValue: _selectedSchoolId,
      isExpanded: true,
      style: _Wp.text(16, color: _Wp.navy),
      dropdownColor: _Wp.white,
      borderRadius: BorderRadius.circular(_Wp.rField),
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
                style: _Wp.text(15.5, color: _Wp.mute)
                    .copyWith(fontStyle: FontStyle.italic)),
          ),
      ],
      onChanged: (v) => setState(() => _selectedSchoolId = v),
      ),
    );
  }

  /// The keypad — rounded keys. Keys fill the available width (flex: 1) and
  /// never fall below a 48 logical-px tap target. The ground inverts to navy
  /// while pressed.
  Widget _buildPad(BuildContext context, {bool compact = false}) {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', '⌫'],
    ];
    final keyH = compact ? 48.0 : R.fluid(context, 52, min: 48, max: 60);
    const gap = 9.0;

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

/// A gentle entrance for the form card: fade and rise from an already-visible
/// default. The screen's one authored moment.
class _Entrance extends StatefulWidget {
  final Widget child;
  const _Entrance({required this.child});

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance> {
  double _t = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _t = 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _t,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: Offset(0, (1 - _t) * 0.04),
        duration: const Duration(milliseconds: 460),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

/// A single keypad key. Rounded, hairline, Instrument Sans numeral; the ground
/// inverts to navy while pressed rather than glowing.
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
            color: _down ? _Wp.navy : _Wp.white,
            borderRadius: BorderRadius.circular(_Wp.rKey),
            border: Border.all(
                color: _down ? _Wp.navy : _Wp.line, width: _Wp.rule),
            boxShadow: _down ? null : _Wp.liftKey,
          ),
          child: Center(
            child: widget.isDelete
                ? Icon(Icons.backspace_outlined, size: 21, color: fg)
                : Text(widget.label,
                    style: _Wp.text(24, color: fg, weight: FontWeight.w600)
                        .copyWith(height: 1)),
          ),
        ),
      ),
    );
  }
}

/// The page's primary control: navy ground, white text, heat on hover, a soft
/// lift for depth.
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
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onTap == null;
    final ground = disabled
        ? _Wp.navy.withValues(alpha: 0.45)
        : _hover || _focused
            ? _Wp.heatRead
            : _Wp.navy;
    return Semantics(
      button: true,
      enabled: !disabled,
      label: widget.label,
      child: InkWell(
        onTap: widget.onTap,
        onHover: (h) => setState(() => _hover = h),
        onFocusChange: (f) => setState(() => _focused = f),
        focusColor: const Color(0x33F55C1E),
        borderRadius: BorderRadius.circular(_Wp.rField),
        mouseCursor:
            disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          constraints: const BoxConstraints(minHeight: 50),
          width: widget.expand ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: ground,
            borderRadius: BorderRadius.circular(_Wp.rField),
            boxShadow: disabled ? null : _Wp.liftKey,
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
                    widget.label,
                    textAlign: TextAlign.center,
                    style: _Wp.text(16.5,
                            color: Colors.white, weight: FontWeight.w600)
                        .copyWith(height: 1.1),
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
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      child: InkWell(
        onTap: widget.onTap,
        onHover: (h) => setState(() => _hover = h),
        onFocusChange: (f) => setState(() => _focused = f),
        focusColor: const Color(0x33F55C1E),
        borderRadius: BorderRadius.circular(_Wp.rField),
        mouseCursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          constraints: const BoxConstraints(minHeight: 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: _hover || _focused ? _Wp.navy : Colors.transparent,
            borderRadius: BorderRadius.circular(_Wp.rField),
            border: Border.all(color: _Wp.navy, width: _Wp.rule),
          ),
          child: Center(
            child: Text(
              widget.label,
              style: _Wp.text(16.5,
                      color: _hover || _focused ? Colors.white : _Wp.navy,
                      weight: FontWeight.w600)
                  .copyWith(height: 1.1),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Two-factor prompt ─────────────────────────────────────────────────────────

/// What the two-factor prompt hands back: the trimmed code, and whether it is a
/// recovery code rather than an authenticator code. Cancel pops null.
typedef _SecondFactorEntry = ({String code, bool recovery});

class _SecondFactorDialog extends StatefulWidget {
  const _SecondFactorDialog();

  @override
  State<_SecondFactorDialog> createState() => _SecondFactorDialogState();
}

class _SecondFactorDialogState extends State<_SecondFactorDialog> {
  // Owned here, not by the caller: showDialog's future completes while the
  // dialog is still animating out, so a controller disposed at that point is
  // still attached to a live TextField.
  final _codeController = TextEditingController();
  bool _useRecovery = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop<_SecondFactorEntry>(
      (code: _codeController.text.trim(), recovery: _useRecovery));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _Wp.white,
      surfaceTintColor: Colors.transparent,
      elevation: 10,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_Wp.rCard),
      ),
      titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
      title: _LoginScreenState._plateHeader(
          'Two-factor authentication', 'Step 2 of 2'),
      contentPadding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _useRecovery
                ? 'Enter one of the recovery codes you saved when you set '
                    'this up. Each code works once.'
                : 'Enter the 6-digit code from your authenticator app.',
            style: _Wp.text(14.5),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _codeController,
            autofocus: true,
            style: _Wp.text(16, color: _Wp.navy),
            keyboardType:
                _useRecovery ? TextInputType.text : TextInputType.number,
            textCapitalization: _useRecovery
                ? TextCapitalization.characters
                : TextCapitalization.none,
            decoration: _LoginScreenState._dec(
              _useRecovery ? 'Recovery code' : '6-digit code',
              hint: _useRecovery ? 'ABCD-EFGH-JKMN' : '123456',
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 4),
          TextButton(
            style: _LoginScreenState._linkStyle,
            onPressed: () => setState(() {
              _useRecovery = !_useRecovery;
              _codeController.clear();
            }),
            child: Text(
              _useRecovery
                  ? 'Use my authenticator app instead'
                  : "I don't have my phone",
              style: _Wp.text(14,
                  color: _Wp.heatRead, weight: FontWeight.w600),
            ),
          ),
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(22, 10, 22, 18),
      actions: [
        _OutlineKey(
          label: 'Cancel',
          onTap: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 10),
        _FilledKey(
          label: 'Verify',
          onTap: _submit,
        ),
      ],
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

/// A segment of the Login / Request Access control. The active segment is a
/// filled navy pill; the inactive one is quiet on the recessed track.
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
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            // Vertical padding keeps the tap target >= 44 logical px.
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
            decoration: BoxDecoration(
              color: active ? _Wp.navy : Colors.transparent,
              borderRadius: BorderRadius.circular(_Wp.rPill),
              boxShadow: active ? _Wp.liftKey : null,
            ),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: _Wp.text(14.5,
                      color: active ? Colors.white : _Wp.navyMid,
                      weight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
