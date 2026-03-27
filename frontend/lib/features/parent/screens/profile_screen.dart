import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/responsive.dart';
import '../../auth/providers/auth_provider.dart';

class ParentProfileScreen extends ConsumerStatefulWidget {
  const ParentProfileScreen({super.key});

  @override
  ConsumerState<ParentProfileScreen> createState() =>
      _ParentProfileScreenState();
}

class _ParentProfileScreenState extends ConsumerState<ParentProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentMpinCtrl = TextEditingController();
  final _newMpinCtrl = TextEditingController();
  final _confirmMpinCtrl = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _saving = false;

  @override
  void dispose() {
    _currentMpinCtrl.dispose();
    _newMpinCtrl.dispose();
    _confirmMpinCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveMpin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.changeParentMpin(_currentMpinCtrl.text, _newMpinCtrl.text);
      _currentMpinCtrl.clear();
      _newMpinCtrl.clear();
      _confirmMpinCtrl.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('MPIN changed successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      final msg = e.toString().contains('400')
          ? 'Current MPIN is incorrect.'
          : 'Failed to change MPIN. Try again.';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final username = auth.username ?? 'Parent';

    return Scaffold(
      appBar: AppBar(title: const Text('My Profile')),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(R.sp(context, 16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Avatar card ──────────────────────────────────────────────
            Container(
              decoration: mindForgeCardDecoration(),
              padding: EdgeInsets.all(R.sp(context, 24)),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: R.fluid(context, 48, min: 38, max: 56),
                    backgroundColor: AppColors.accent.withValues(alpha: 0.15),
                    child: Text(
                      username.isNotEmpty ? username[0].toUpperCase() : 'P',
                      style: TextStyle(
                        fontSize: R.fs(context, 36, min: 28, max: 42),
                        fontWeight: FontWeight.bold,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(username,
                      style: TextStyle(
                          fontSize: R.fs(context, 20, min: 16, max: 23),
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'PARENT',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.accent,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Change MPIN ──────────────────────────────────────────────
            Container(
              decoration: mindForgeCardDecoration(),
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.lock_outline,
                            size: 18, color: AppColors.accent),
                        SizedBox(width: 8),
                        Text('Change MPIN',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _MpinField(
                      controller: _currentMpinCtrl,
                      label: 'Current MPIN',
                      obscure: _obscureCurrent,
                      onToggle: () => setState(
                          () => _obscureCurrent = !_obscureCurrent),
                      validator: (v) {
                        if (v == null || v.length != 6) {
                          return 'Enter your 6-digit MPIN';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    _MpinField(
                      controller: _newMpinCtrl,
                      label: 'New MPIN',
                      obscure: _obscureNew,
                      onToggle: () =>
                          setState(() => _obscureNew = !_obscureNew),
                      validator: (v) {
                        if (v == null || v.length != 6) {
                          return 'Must be exactly 6 digits';
                        }
                        if (v == _currentMpinCtrl.text) {
                          return 'New MPIN must differ from current';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    _MpinField(
                      controller: _confirmMpinCtrl,
                      label: 'Confirm New MPIN',
                      obscure: _obscureConfirm,
                      onToggle: () => setState(
                          () => _obscureConfirm = !_obscureConfirm),
                      validator: (v) {
                        if (v != _newMpinCtrl.text) {
                          return 'MPINs do not match';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _saving ? null : _saveMpin,
                        child: _saving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white),
                              )
                            : const Text('Update MPIN'),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _MpinField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool obscure;
  final VoidCallback onToggle;
  final String? Function(String?) validator;

  const _MpinField({
    required this.controller,
    required this.label,
    required this.obscure,
    required this.onToggle,
    required this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: TextInputType.number,
      maxLength: 6,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        suffixIcon: IconButton(
          icon: Icon(
              obscure
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              size: 18),
          onPressed: onToggle,
        ),
      ),
      validator: validator,
    );
  }
}
