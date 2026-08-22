import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/security/screen_security.dart';
import '../../../core/widgets/qr_view.dart';

/// Turn two-factor authentication on or off.
///
/// Available to admin and owner accounts only — the backend rejects everyone
/// else. Reached from the admin profile screen and the owner console; one
/// screen, two entry points.
///
/// Wrapped in [SecureScreenMixin] because it displays the TOTP secret and the
/// recovery codes. Everywhere else that is a nicety; here a screenshot *is* the
/// second factor.
class MfaSetupScreen extends ConsumerStatefulWidget {
  const MfaSetupScreen({super.key});

  @override
  ConsumerState<MfaSetupScreen> createState() => _MfaSetupScreenState();
}

enum _Stage { loading, off, enrolling, showingCodes, on, unavailable }

class _MfaSetupScreenState extends ConsumerState<MfaSetupScreen>
    with SecureScreenMixin {
  _Stage _stage = _Stage.loading;
  String? _error;
  bool _busy = false;

  String? _secret;
  String? _uri;
  List<String> _recoveryCodes = [];
  int _codesRemaining = 0;

  final _codeController = TextEditingController();

  ApiClient get _api => ref.read(apiClientProvider);

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    setState(() { _stage = _Stage.loading; _error = null; });
    try {
      // Bounded, because an expired session sends this through the token-refresh
      // path and the await can sit there — leaving the screen on its spinner
      // with nothing to act on. Observed while testing against a stale login.
      final s = await _api.mfaStatus().timeout(const Duration(seconds: 10));
      if (!mounted) return;
      setState(() {
        _codesRemaining = (s['recovery_codes_remaining'] as int?) ?? 0;
        _stage = (s['enabled'] as bool? ?? false) ? _Stage.on : _Stage.off;
      });
    } catch (e) {
      if (!mounted) return;
      // Deliberately NOT falling back to the "off" screen. If the call failed we
      // do not know the state, and showing "set up two-factor" to someone who
      // already has it on invites them to enrol twice and invalidate the
      // authenticator entry they are relying on.
      setState(() {
        _stage = _Stage.unavailable;
        _error = null;
      });
    }
  }

  Future<void> _startSetup() async {
    setState(() { _busy = true; _error = null; });
    try {
      final r = await _api.mfaSetup();
      if (!mounted) return;
      setState(() {
        _secret = r['secret'] as String?;
        _uri = r['provisioning_uri'] as String?;
        _stage = _Stage.enrolling;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not start setup. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code from your app.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final r = await _api.mfaConfirm(code);
      if (!mounted) return;
      setState(() {
        _recoveryCodes = List<String>.from(r['recovery_codes'] as List? ?? []);
        _codesRemaining = _recoveryCodes.length;
        _stage = _Stage.showingCodes;
        _codeController.clear();
      });
    } catch (e) {
      if (!mounted) return;
      // The backend distinguishes a wrong code from a broken setup; either way
      // the useful advice is the same, and the code may simply have rolled over.
      setState(() => _error =
          "That code didn't match. Codes change every 30 seconds — try the "
          'current one.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disable() async {
    // The dialog owns its own text controllers (see _DisableTwoFactorDialog).
    // Creating them here and disposing them right after `showDialog` returned
    // crashed the close animation: the dialog rebuilds its TextFields while
    // animating out, and by then the controllers were already disposed
    // ("TextEditingController used after being disposed", then a huge overflow
    // where the broken field should be). A StatefulWidget dialog disposes them
    // only when the route is fully gone.
    final result = await showDialog<({String mpin, String code})>(
      context: context,
      builder: (_) => const _DisableTwoFactorDialog(),
    );
    if (result == null || !mounted) return;
    final mpin = result.mpin;
    final code = result.code;

    setState(() { _busy = true; _error = null; });
    try {
      // A recovery code carries a dash; a TOTP code is six digits. Sending the
      // right field means someone falling back to a printed code still works.
      final isRecovery = code.contains('-');
      await _api.mfaDisable(
        mpin: mpin,
        code: isRecovery ? null : code,
        recoveryCode: isRecovery ? code : null,
      );
      if (!mounted) return;
      setState(() { _stage = _Stage.off; _secret = null; _uri = null; });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'That MPIN or code was not accepted.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Two-factor authentication')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_error != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_error!),
                ),
                const SizedBox(height: 16),
              ],
              ..._stageContent(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _stageContent() {
    switch (_stage) {
      case _Stage.loading:
        return [const Center(child: Padding(
          padding: EdgeInsets.only(top: 60), child: CircularProgressIndicator()))];

      case _Stage.off:
        return [
          const Text('Add a second step to your sign-in',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text(
            'After your MPIN, you will be asked for a 6-digit code from an '
            'authenticator app on your phone. An admin account can see every '
            'student record in the school, so a shared or guessed MPIN is worth '
            'more here than anywhere else in the app.',
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _startSetup,
            child: Text(_busy ? 'Working…' : 'Set up two-factor'),
          ),
        ];

      case _Stage.enrolling:
        return [
          const Text('1. Scan this with your authenticator app',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('Google Authenticator, Authy, 1Password — any of them.',
              style: TextStyle(fontSize: 13)),
          const SizedBox(height: 16),
          if (_uri != null) Center(child: QrView(data: _uri!, size: 220)),
          const SizedBox(height: 16),
          const Text("Can't scan? Enter this key by hand:",
              style: TextStyle(fontSize: 13)),
          const SizedBox(height: 6),
          if (_secret != null)
            _CopyableSecret(secret: _secret!),
          const SizedBox(height: 24),
          const Text('2. Enter the code it shows',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          TextField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(
              labelText: '6-digit code',
              border: OutlineInputBorder(),
              counterText: '',
            ),
            onSubmitted: (_) => _confirm(),
          ),
          const SizedBox(height: 12),
          Row(children: [
            FilledButton(
              onPressed: _busy ? null : _confirm,
              child: Text(_busy ? 'Checking…' : 'Turn on'),
            ),
            const SizedBox(width: 12),
            TextButton(
              // Nothing to undo on the server: setup issues a secret but leaves
              // MFA off until a code is confirmed, so walking away here is safe.
              onPressed: _busy ? null : () => setState(() => _stage = _Stage.off),
              child: const Text('Cancel'),
            ),
          ]),
        ];

      case _Stage.showingCodes:
        return [
          const Text('Save your recovery codes',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text(
            'These are shown once and cannot be shown again — only a scrambled '
            'copy is stored. Print them or put them somewhere safe. Each one '
            'works a single time, and they are how you get back in if you lose '
            'your phone.',
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              _recoveryCodes.join('\n'),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 15, height: 1.6),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _recoveryCodes.join('\n')));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Recovery codes copied')));
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy all'),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => setState(() {
              _recoveryCodes = [];
              _stage = _Stage.on;
            }),
            child: const Text("I've saved them"),
          ),
        ];

      case _Stage.unavailable:
        return [
          const Text("Couldn't load your two-factor settings",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text(
            'This is usually a connection problem, or a sign-in that has since '
            'expired. Your existing settings have not changed.',
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _refreshStatus, child: const Text('Try again')),
        ];

      case _Stage.on:
        return [
          Row(children: [
            Icon(Icons.verified_user,
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            const Text('Two-factor is on',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 8),
          Text(
            'You will be asked for a code from your authenticator app each time '
            'you sign in. $_codesRemaining recovery '
            '${_codesRemaining == 1 ? "code" : "codes"} remaining.',
            style: const TextStyle(fontSize: 14),
          ),
          if (_codesRemaining <= 2) ...[
            const SizedBox(height: 12),
            const Text(
              'You are running low on recovery codes. Turning two-factor off and '
              'back on issues a fresh set.',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: _busy ? null : _disable,
            child: const Text('Turn off two-factor'),
          ),
        ];
    }
  }
}

/// The base32 secret, grouped so it can be typed without losing your place.
class _CopyableSecret extends StatelessWidget {
  final String secret;
  const _CopyableSecret({required this.secret});

  @override
  Widget build(BuildContext context) {
    // Four-character groups: a 32-character unbroken string is genuinely hard to
    // transcribe onto a phone without skipping a character.
    final grouped = <String>[];
    for (var i = 0; i < secret.length; i += 4) {
      grouped.add(secret.substring(i, (i + 4).clamp(0, secret.length)));
    }
    return Row(children: [
      Expanded(
        child: SelectableText(
          grouped.join(' '),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
        ),
      ),
      IconButton(
        tooltip: 'Copy key',
        icon: const Icon(Icons.copy, size: 18),
        onPressed: () {
          Clipboard.setData(ClipboardData(text: secret));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Key copied')));
        },
      ),
    ]);
  }
}


/// Confirmation dialog for turning two-factor off. It owns the MPIN + code
/// controllers so their lifetime matches the dialog's own — disposed only when
/// the route is fully removed, not the instant `showDialog` returns, which used
/// to crash the close animation. Returns `(mpin, code)` on confirm, null on
/// cancel/dismiss.
class _DisableTwoFactorDialog extends StatefulWidget {
  const _DisableTwoFactorDialog();

  @override
  State<_DisableTwoFactorDialog> createState() =>
      _DisableTwoFactorDialogState();
}

class _DisableTwoFactorDialogState extends State<_DisableTwoFactorDialog> {
  final _mpin = TextEditingController();
  final _code = TextEditingController();

  @override
  void dispose() {
    _mpin.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Turn off two-factor?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Your account will be protected by your MPIN alone. Confirm with '
            'your MPIN and a current code.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _mpin,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Your MPIN', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '6-digit code (or a recovery code)',
              border: OutlineInputBorder()),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(
            (mpin: _mpin.text.trim(), code: _code.text.trim()),
          ),
          child: const Text('Turn off'),
        ),
      ],
    );
  }
}
