import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/logout_confirm.dart';
import '../../auth/providers/auth_provider.dart';

/// Platform-owner console: create/list schools and provision their admins.
class OwnerDashboardScreen extends ConsumerStatefulWidget {
  const OwnerDashboardScreen({super.key});

  @override
  ConsumerState<OwnerDashboardScreen> createState() =>
      _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends ConsumerState<OwnerDashboardScreen> {
  List<Map<String, dynamic>> _schools = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final schools = await ref.read(apiClientProvider).getOwnerSchools();
      if (!mounted) return;
      setState(() {
        _schools = schools;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load schools: $e';
        _loading = false;
      });
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.error : AppColors.success,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final username = ref.watch(authProvider).username ?? 'Owner';
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text('MIND FORGE — Owner Console',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700, fontSize: 16)),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Log out',
            onPressed: () => confirmLogout(context, ref),
            icon: const Icon(Icons.logout),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        onPressed: _showAddSchool,
        icon: const Icon(Icons.add),
        label: Text('Add School', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(username),
      ),
    );
  }

  Widget _buildBody(String username) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(children: [
        const SizedBox(height: 120),
        Center(child: Text(_error!, style: GoogleFonts.poppins(color: AppColors.error))),
      ]);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Text('Welcome, $username',
            style: GoogleFonts.poppins(
                fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        const SizedBox(height: 2),
        Text('${_schools.length} school${_schools.length == 1 ? '' : 's'} on the platform',
            style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 16),
        if (_schools.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: Center(
              child: Text('No schools yet. Tap "Add School" to onboard one.',
                  style: GoogleFonts.poppins(color: AppColors.textSecondary)),
            ),
          ),
        for (final s in _schools) _schoolCard(s),
      ],
    );
  }

  Widget _schoolCard(Map<String, dynamic> s) {
    final active = s['is_active'] == true;
    final counts = [
      ('Admins', s['admin_count']),
      ('Teachers', s['teacher_count']),
      ('Students', s['student_count']),
      ('Parents', s['parent_count']),
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s['name'] ?? '—',
                        style: GoogleFonts.poppins(
                            fontSize: 16, fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    Text(s['slug'] ?? '',
                        style: GoogleFonts.poppins(
                            fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (active ? AppColors.success : AppColors.error)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(active ? 'Active' : 'Suspended',
                    style: GoogleFonts.poppins(
                        fontSize: 11, fontWeight: FontWeight.w600,
                        color: active ? AppColors.success : AppColors.error)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in counts)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Text('${c.$1}: ${c.$2 ?? 0}',
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: AppColors.textSecondary)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _showAddAdmin(s),
                icon: const Icon(Icons.person_add_alt, size: 18),
                label: const Text('Add Admin'),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _toggleActive(s),
                icon: Icon(active ? Icons.pause_circle_outline : Icons.play_circle_outline,
                    size: 18, color: active ? AppColors.error : AppColors.success),
                label: Text(active ? 'Suspend' : 'Activate',
                    style: TextStyle(color: active ? AppColors.error : AppColors.success)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _toggleActive(Map<String, dynamic> s) async {
    try {
      await ref.read(apiClientProvider)
          .updateSchool(s['id'] as int, isActive: !(s['is_active'] == true));
      _snack('${s['name']} ${s['is_active'] == true ? 'suspended' : 'activated'}.');
      await _load();
    } catch (e) {
      _snack('Failed: $e', error: true);
    }
  }

  Future<void> _showAddSchool() async {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add School', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'School name *')),
              const SizedBox(height: 8),
              TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Contact email')),
              const SizedBox(height: 8),
              TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Contact phone')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
        ],
      ),
    );
    if (ok != true) return;
    if (nameCtrl.text.trim().isEmpty) {
      _snack('School name is required.', error: true);
      return;
    }
    try {
      await ref.read(apiClientProvider).createSchool(
            name: nameCtrl.text.trim(),
            contactEmail: emailCtrl.text.trim(),
            contactPhone: phoneCtrl.text.trim(),
          );
      _snack('School created.');
      await _load();
    } catch (e) {
      _snack(_msg(e), error: true);
    }
  }

  Future<void> _showAddAdmin(Map<String, dynamic> s) async {
    final userCtrl = TextEditingController();
    final mpinCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add Admin — ${s['name']}',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: userCtrl,
              decoration: const InputDecoration(labelText: 'Admin username *'),
              inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: mpinCtrl,
              decoration: const InputDecoration(labelText: '6-digit MPIN *', counterText: ''),
              keyboardType: TextInputType.number,
              maxLength: 6,
              obscureText: true,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
        ],
      ),
    );
    if (ok != true) return;
    if (userCtrl.text.trim().length < 3 || mpinCtrl.text.length != 6) {
      _snack('Username (3+) and a 6-digit MPIN are required.', error: true);
      return;
    }
    try {
      await ref.read(apiClientProvider)
          .createSchoolAdmin(s['id'] as int, userCtrl.text.trim(), mpinCtrl.text);
      _snack('Admin created for ${s['name']}.');
      await _load();
    } catch (e) {
      _snack(_msg(e), error: true);
    }
  }

  String _msg(Object e) {
    final s = e.toString();
    final i = s.indexOf('detail');
    return i == -1 ? 'Failed: $s' : s;
  }
}
