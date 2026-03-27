import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';

class AdminProfileScreen extends ConsumerStatefulWidget {
  const AdminProfileScreen({super.key});

  @override
  ConsumerState<AdminProfileScreen> createState() => _AdminProfileScreenState();
}

class _AdminProfileScreenState extends ConsumerState<AdminProfileScreen> {
  // MPIN change state
  final List<String> _currentPin = ['', '', '', '', '', ''];
  final List<String> _newPin = ['', '', '', '', '', ''];
  final List<String> _confirmPin = ['', '', '', '', '', ''];
  int _activePinField = 0; // 0=current,1=new,2=confirm
  int _currentPinIndex = 0;
  int _newPinIndex = 0;
  int _confirmPinIndex = 0;

  bool _uploadingPhoto = false;
  bool _changingMpin = false;

  String get _currentPinStr => _currentPin.join();
  String get _newPinStr => _newPin.join();
  String get _confirmPinStr => _confirmPin.join();

  List<String> get _activeList {
    switch (_activePinField) {
      case 1:
        return _newPin;
      case 2:
        return _confirmPin;
      default:
        return _currentPin;
    }
  }

  int get _activeIndex {
    switch (_activePinField) {
      case 1:
        return _newPinIndex;
      case 2:
        return _confirmPinIndex;
      default:
        return _currentPinIndex;
    }
  }

  set _activeIndex(int v) {
    switch (_activePinField) {
      case 1:
        _newPinIndex = v;
        break;
      case 2:
        _confirmPinIndex = v;
        break;
      default:
        _currentPinIndex = v;
    }
  }

  void _tapDigit(String d) {
    if (_activeIndex >= 6) return;
    setState(() {
      _activeList[_activeIndex] = d;
      _activeIndex = _activeIndex + 1;
      // Auto-advance to next field when complete
      if (_activeIndex == 6 && _activePinField < 2) {
        _activePinField++;
      }
    });
  }

  void _tapDelete() {
    if (_activeIndex == 0) {
      // Go back to previous field
      if (_activePinField > 0) {
        setState(() => _activePinField--);
      }
      return;
    }
    setState(() {
      _activeIndex = _activeIndex - 1;
      _activeList[_activeIndex] = '';
    });
  }

  void _clearAll() {
    setState(() {
      for (int i = 0; i < 6; i++) {
        _currentPin[i] = '';
        _newPin[i] = '';
        _confirmPin[i] = '';
      }
      _currentPinIndex = 0;
      _newPinIndex = 0;
      _confirmPinIndex = 0;
      _activePinField = 0;
    });
  }

  Future<void> _pickAndUploadPhoto() async {
    final picker = ImagePicker();
    final picked =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;

    setState(() => _uploadingPhoto = true);
    try {
      final bytes = await picked.readAsBytes();
      final api = ref.read(apiClientProvider);
      final result = await api.uploadAdminPhoto(bytes, picked.name);
      final url = result['profile_pic_url'] as String;
      await ref.read(authProvider.notifier).updateProfilePicUrl(url);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Profile photo updated!'),
            backgroundColor: AppColors.success));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: AppColors.error));
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _changeMpin() async {
    if (_currentPinStr.length < 6) {
      _showSnack('Enter your current 6-digit MPIN.');
      setState(() => _activePinField = 0);
      return;
    }
    if (_newPinStr.length < 6) {
      _showSnack('Enter your new 6-digit MPIN.');
      setState(() => _activePinField = 1);
      return;
    }
    if (_confirmPinStr.length < 6) {
      _showSnack('Confirm your new 6-digit MPIN.');
      setState(() => _activePinField = 2);
      return;
    }
    if (_newPinStr != _confirmPinStr) {
      _showSnack('New MPIN and confirmation do not match.', isError: true);
      setState(() {
        for (int i = 0; i < 6; i++) {
          _newPin[i] = '';
          _confirmPin[i] = '';
        }
        _newPinIndex = 0;
        _confirmPinIndex = 0;
        _activePinField = 1;
      });
      return;
    }

    setState(() => _changingMpin = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.changeAdminMpin(_currentPinStr, _newPinStr);
      _clearAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('MPIN changed successfully!'),
            backgroundColor: AppColors.success));
      }
    } catch (e) {
      final msg = e.toString().contains('400')
          ? 'Current MPIN is incorrect.'
          : 'Failed to change MPIN. Try again.';
      _showSnack(msg, isError: true);
      _clearAll();
    } finally {
      if (mounted) setState(() => _changingMpin = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.error : AppColors.warning,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final username = auth.username ?? 'Admin';
    final photoUrl = auth.profilePicUrl;

    return Scaffold(
      appBar: AppBar(title: const Text('My Profile')),
      resizeToAvoidBottomInset: false,
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Avatar ────────────────────────────────────────────────
            Center(
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 56,
                    backgroundColor:
                        AppColors.primaryDark.withValues(alpha: 0.15),
                    backgroundImage:
                        photoUrl != null ? NetworkImage(photoUrl) : null,
                    child: photoUrl == null
                        ? Text(
                            username[0].toUpperCase(),
                            style: const TextStyle(
                                fontSize: 42,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryDark),
                          )
                        : null,
                  ),
                  GestureDetector(
                    onTap: _uploadingPhoto ? null : _pickAndUploadPhoto,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: _uploadingPhoto
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.camera_alt,
                              size: 18, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),
            Center(
              child: Text(username,
                  style: Theme.of(context).textTheme.headlineSmall),
            ),
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primaryDark.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('ADMIN',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryDark,
                        letterSpacing: 1)),
              ),
            ),

            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),

            // ── Change MPIN section ───────────────────────────────────
            Text('Change MPIN',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),

            _PinRow(
              label: 'Current MPIN',
              pin: _currentPin,
              pinIndex: _currentPinIndex,
              active: _activePinField == 0,
              onTap: () => setState(() => _activePinField = 0),
            ),
            const SizedBox(height: 16),
            _PinRow(
              label: 'New MPIN',
              pin: _newPin,
              pinIndex: _newPinIndex,
              active: _activePinField == 1,
              onTap: () => setState(() => _activePinField = 1),
            ),
            const SizedBox(height: 16),
            _PinRow(
              label: 'Confirm New MPIN',
              pin: _confirmPin,
              pinIndex: _confirmPinIndex,
              active: _activePinField == 2,
              onTap: () => setState(() => _activePinField = 2),
            ),

            const SizedBox(height: 20),
            _buildPad(),
            const SizedBox(height: 20),

            const SizedBox(height: 8),
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                icon: _changingMpin
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_circle_outline),
                label: Text(
                  _changingMpin ? 'Saving…' : 'Submit',
                  style: GoogleFonts.specialElite(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                onPressed: _changingMpin ? null : _changeMpin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondary,
                  foregroundColor: AppColors.textOnDark,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _clearAll,
              child: const Text('Clear all fields',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPad() {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', '⌫'],
    ];
    return Column(
      children: rows.map((row) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: row.map((key) {
              if (key.isEmpty) return const SizedBox(width: 80, height: 48);
              final isDel = key == '⌫';
              return GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  isDel ? _tapDelete() : _tapDigit(key);
                },
                child: Container(
                  width: 80,
                  height: 48,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: isDel
                        ? AppColors.error.withValues(alpha: 0.08)
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Center(
                    child: Text(
                      key,
                      style: GoogleFonts.specialElite(
                        fontSize: isDel ? 16 : 20,
                        fontWeight: FontWeight.w700,
                        color: isDel ? AppColors.error : AppColors.textPrimary,
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

class _PinRow extends StatelessWidget {
  final String label;
  final List<String> pin;
  final int pinIndex;
  final bool active;
  final VoidCallback onTap;

  const _PinRow({
    required this.label,
    required this.pin,
    required this.pinIndex,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.specialElite(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: active ? AppColors.primary : AppColors.textSecondary)),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(6, (i) {
              final filled = pin[i].isNotEmpty;
              final isCursor = active && i == pinIndex;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: 36,
                height: 42,
                decoration: BoxDecoration(
                  color: filled
                      ? AppColors.primary.withValues(alpha: 0.12)
                      : AppColors.surface,
                  border: Border.all(
                    color: isCursor
                        ? AppColors.primary
                        : active
                            ? AppColors.primary.withValues(alpha: 0.4)
                            : AppColors.divider,
                    width: isCursor ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: filled
                      ? Container(
                          width: 9,
                          height: 9,
                          decoration: const BoxDecoration(
                              color: AppColors.primary, shape: BoxShape.circle),
                        )
                      : null,
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
