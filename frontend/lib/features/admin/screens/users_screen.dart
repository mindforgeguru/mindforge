import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/user.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/admin_provider.dart';

class AdminUsersScreen extends ConsumerStatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  ConsumerState<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends ConsumerState<AdminUsersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // Immediately refresh when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(pendingUsersProvider);
    });

    // Refresh pending tab every 10 seconds automatically
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) ref.invalidate(pendingUsersProvider);
    });

    // Also refresh when switching to the Pending tab
    _tabController.addListener(() {
      if (_tabController.index == 0 && !_tabController.indexIsChanging) {
        ref.invalidate(pendingUsersProvider);
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(pendingUsersProvider);
              ref.invalidate(allUsersProvider);
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: AppColors.accent,
          tabs: const [
            Tab(text: 'Pending Approval'),
            Tab(text: 'Active Users'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _PendingUsersTab(),
          _ActiveUsersTab(),
        ],
      ),
    );
  }
}

class _PendingUsersTab extends ConsumerWidget {
  const _PendingUsersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(pendingUsersProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(pendingUsersProvider),
      color: AppColors.primary,
      child: usersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(
          children: [
            const SizedBox(height: 80),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 8),
                  const Text('Failed to load users'),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                    onPressed: () => ref.invalidate(pendingUsersProvider),
                  ),
                ],
              ),
            ),
          ],
        ),
        data: (users) {
          if (users.isEmpty) {
            return ListView(
              children: const [
                SizedBox(height: 80),
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 64, color: AppColors.success),
                      SizedBox(height: 16),
                      Text('No pending approvals',
                          style: TextStyle(fontSize: 18)),
                      SizedBox(height: 8),
                      Text('Pull down to refresh',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.textMuted)),
                    ],
                  ),
                ),
              ],
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: users.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (ctx, i) => _PendingUserTile(user: users[i]),
          );
        },
      ),
    );
  }
}

class _PendingUserTile extends ConsumerWidget {
  final UserModel user;
  const _PendingUserTile({required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: mindForgeCardDecoration(
          color: AppColors.warning.withOpacity(0.04)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _roleColor(user.role).withOpacity(0.15),
          child: Text(
            user.username[0].toUpperCase(),
            style: TextStyle(
                color: _roleColor(user.role), fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(user.username,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(user.role.toUpperCase(),
                style: TextStyle(
                    color: _roleColor(user.role),
                    fontWeight: FontWeight.bold,
                    fontSize: 11)),
            Text('Registered: ${DateFormat('dd MMM yyyy').format(user.createdAt)}',
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ],
        ),
        trailing: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.success,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          onPressed: () => _approveUser(context, ref, user.id),
          child: const Text('Approve', style: TextStyle(fontSize: 12)),
        ),
      ),
    );
  }

  Future<void> _approveUser(
      BuildContext context, WidgetRef ref, int userId) async {
    final api = ref.read(apiClientProvider);
    await api.approveUser(userId);
    ref.invalidate(pendingUsersProvider);
    ref.invalidate(allUsersProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('User approved!'),
            backgroundColor: AppColors.success),
      );
    }
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'teacher':
        return AppColors.secondary;
      case 'student':
        return AppColors.primary;
      case 'parent':
        return AppColors.accent;
      case 'admin':
        return AppColors.primaryDark;
      default:
        return AppColors.textSecondary;
    }
  }
}

// ── Edit User Bottom Sheet ────────────────────────────────────────────────────

class _EditUserSheet extends StatefulWidget {
  final UserModel user;
  final Future<void> Function(Map<String, dynamic>) onSave;

  const _EditUserSheet({required this.user, required this.onSave});

  @override
  State<_EditUserSheet> createState() => _EditUserSheetState();
}

class _EditUserSheetState extends State<_EditUserSheet> {
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _parentUsernameCtrl;
  late final TextEditingController _studentUsernameCtrl;
  late String _selectedRole;
  late int? _selectedGrade;
  final List<String> _mpin = ['', '', '', '', '', ''];
  int _mpinIndex = 0;
  bool _saving = false;
  bool _showMpinReset = false;

  @override
  void initState() {
    super.initState();
    _usernameCtrl = TextEditingController(text: widget.user.username);
    _parentUsernameCtrl = TextEditingController(text: widget.user.parentUsername ?? '');
    _studentUsernameCtrl = TextEditingController(text: widget.user.studentUsername ?? '');
    _selectedRole = widget.user.role;
    _selectedGrade = widget.user.grade;
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _parentUsernameCtrl.dispose();
    _studentUsernameCtrl.dispose();
    super.dispose();
  }

  void _tapDigit(String d) {
    if (_mpinIndex >= 6) return;
    setState(() {
      _mpin[_mpinIndex] = d;
      _mpinIndex++;
    });
  }

  void _tapDelete() {
    if (_mpinIndex == 0) return;
    setState(() {
      _mpinIndex--;
      _mpin[_mpinIndex] = '';
    });
  }

  Future<void> _save() async {
    final newUsername = _usernameCtrl.text.trim();
    if (newUsername.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Username cannot be empty.')));
      return;
    }
    final newMpin = _mpin.join();
    if (_showMpinReset && newMpin.length < 6) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter a complete 6-digit MPIN.')));
      return;
    }

    final data = <String, dynamic>{};
    if (newUsername != widget.user.username) data['username'] = newUsername;
    if (_selectedRole != widget.user.role) data['role'] = _selectedRole;
    if (_selectedRole == 'student' && _selectedGrade != widget.user.grade) {
      data['grade'] = _selectedGrade;
    }
    if (_showMpinReset && newMpin.length == 6) data['new_mpin'] = newMpin;
    // Parent field for students:
    // - If a parent is already linked → renaming the parent user
    // - If no parent linked yet → linking to an existing parent account
    if (_selectedRole == 'student') {
      final newParent = _parentUsernameCtrl.text.trim();
      final hasLinkedParent = widget.user.parentUserId != null;
      if (hasLinkedParent) {
        // Rename the linked parent user (different API call)
        if (newParent.isNotEmpty && newParent != (widget.user.parentUsername ?? '')) {
          data['_rename_parent_id'] = widget.user.parentUserId;
          data['_rename_parent_to'] = newParent;
        }
      } else {
        // Link to an existing parent account by username
        if (newParent != (widget.user.parentUsername ?? '')) {
          data['parent_username'] = newParent; // empty string = unlink
        }
      }
    }
    // Include student_username if this is a parent and the value changed
    if (_selectedRole == 'parent') {
      final newStudent = _studentUsernameCtrl.text.trim();
      if (newStudent != (widget.user.studentUsername ?? '')) {
        data['student_username'] = newStudent; // empty string = unlink
      }
    }

    if (data.isEmpty) {
      Navigator.pop(context);
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.onSave(data);
      if (mounted) Navigator.pop(context, data);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isStudent = widget.user.role == 'student';
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                const Icon(Icons.edit_outlined, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  'Edit  ${widget.user.username}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    widget.user.role.toUpperCase(),
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Username
            TextField(
              controller: _usernameCtrl,
              decoration: const InputDecoration(
                labelText: 'Username',
                prefixIcon: Icon(Icons.person_outline),
                isDense: true,
              ),
              inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
            ),

            const SizedBox(height: 14),

            // Role
            DropdownButtonFormField<String>(
              initialValue: _selectedRole,
              decoration: const InputDecoration(
                labelText: 'Role',
                prefixIcon: Icon(Icons.badge_outlined),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 'student', child: Text('Student')),
                DropdownMenuItem(value: 'teacher', child: Text('Teacher')),
                DropdownMenuItem(value: 'parent', child: Text('Parent')),
              ],
              onChanged: (v) => setState(() {
                _selectedRole = v ?? _selectedRole;
                if (_selectedRole != 'student') _selectedGrade = null;
                if (_selectedRole == 'student' && _selectedGrade == null) {
                  _selectedGrade = 8;
                }
              }),
            ),

            // Grade + Parent username (students only)
            if (_selectedRole == 'student') ...[
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                initialValue: _selectedGrade,
                decoration: const InputDecoration(
                  labelText: 'Grade',
                  prefixIcon: Icon(Icons.school_outlined),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: 8, child: Text('Grade 8')),
                  DropdownMenuItem(value: 9, child: Text('Grade 9')),
                  DropdownMenuItem(value: 10, child: Text('Grade 10')),
                ],
                onChanged: (v) => setState(() => _selectedGrade = v),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _parentUsernameCtrl,
                decoration: InputDecoration(
                  labelText: widget.user.parentUserId != null
                      ? "Parent's Username (rename)"
                      : "Link Parent Account",
                  prefixIcon: const Icon(Icons.family_restroom),
                  isDense: true,
                  helperText: widget.user.parentUserId != null
                      ? 'Change to rename the parent\'s login username.'
                      : 'Enter an existing parent\'s username to link.',
                  helperMaxLines: 2,
                ),
                inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
              ),
            ],

            // Student username (parents only)
            if (_selectedRole == 'parent') ...[
              const SizedBox(height: 14),
              TextField(
                controller: _studentUsernameCtrl,
                decoration: const InputDecoration(
                  labelText: "Student's Username",
                  prefixIcon: Icon(Icons.school_outlined),
                  isDense: true,
                  helperText: 'Enter student username to link. Leave empty to unlink.',
                  helperMaxLines: 2,
                ),
                inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
              ),
            ],

            const SizedBox(height: 16),

            // MPIN reset toggle
            InkWell(
              onTap: () => setState(() {
                _showMpinReset = !_showMpinReset;
                if (!_showMpinReset) {
                  for (int i = 0; i < 6; i++) {
                    _mpin[i] = '';
                  }
                  _mpinIndex = 0;
                }
              }),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _showMpinReset
                      ? AppColors.warning.withOpacity(0.08)
                      : AppColors.surface,
                  border: Border.all(
                    color: _showMpinReset
                        ? AppColors.warning
                        : AppColors.divider,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock_reset_outlined,
                        color: _showMpinReset
                            ? AppColors.warning
                            : AppColors.textMuted,
                        size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Reset MPIN',
                      style: TextStyle(
                        color: _showMpinReset
                            ? AppColors.warning
                            : AppColors.textSecondary,
                        fontWeight: _showMpinReset
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      _showMpinReset
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: AppColors.textMuted,
                    ),
                  ],
                ),
              ),
            ),

            if (_showMpinReset) ...[
              const SizedBox(height: 14),
              const Text(
                'New 6-digit MPIN',
                style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              // PIN dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(6, (i) {
                  final filled = _mpin[i].isNotEmpty;
                  final active = i == _mpinIndex;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    width: 36,
                    height: 42,
                    decoration: BoxDecoration(
                      color: filled
                          ? AppColors.primary.withOpacity(0.12)
                          : AppColors.surface,
                      border: Border.all(
                        color: active ? AppColors.primary : AppColors.divider,
                        width: active ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: filled
                          ? Container(
                              width: 10,
                              height: 10,
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
              const SizedBox(height: 10),
              // Numpad
              ...[
                ['1', '2', '3'],
                ['4', '5', '6'],
                ['7', '8', '9'],
                ['', '0', '⌫'],
              ].map(
                (row) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: row.map((key) {
                      if (key.isEmpty) {
                        return const SizedBox(width: 80, height: 48);
                      }
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
                                ? AppColors.error.withOpacity(0.08)
                                : AppColors.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.divider),
                          ),
                          child: Center(
                            child: Text(
                              key,
                              style: TextStyle(
                                fontSize: isDel ? 14 : 18,
                                fontWeight: FontWeight.w700,
                                color: isDel
                                    ? AppColors.error
                                    : AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 20),

            // Save button
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Save Changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveUsersTab extends ConsumerStatefulWidget {
  const _ActiveUsersTab();

  @override
  ConsumerState<_ActiveUsersTab> createState() => _ActiveUsersTabState();
}

class _ActiveUsersTabState extends ConsumerState<_ActiveUsersTab> {
  String _selectedRole = 'student';
  int? _selectedGrade;

  bool get _needsGrade =>
      _selectedRole == 'student' || _selectedRole == 'parent';

  @override
  Widget build(BuildContext context) {
    final providerParam = (
      _selectedRole,
      _needsGrade ? _selectedGrade : null,
    );
    final usersAsync = ref.watch(allUsersProvider(providerParam));

    return Column(
      children: [
        // ── Filters ──────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          color: AppColors.cardBackground,
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                initialValue: _selectedRole,
                decoration: const InputDecoration(
                  labelText: 'User Type',
                  prefixIcon: Icon(Icons.badge_outlined),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: 'student', child: Text('Student')),
                  DropdownMenuItem(value: 'teacher', child: Text('Teacher')),
                  DropdownMenuItem(value: 'parent', child: Text('Parent')),
                ],
                onChanged: (v) => setState(() {
                  _selectedRole = v ?? 'student';
                  _selectedGrade = null;
                }),
              ),
              if (_needsGrade) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<int?>(
                  initialValue: _selectedGrade,
                  decoration: const InputDecoration(
                    labelText: 'Grade',
                    prefixIcon: Icon(Icons.school_outlined),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('All Grades')),
                    DropdownMenuItem(value: 8, child: Text('Grade 8')),
                    DropdownMenuItem(value: 9, child: Text('Grade 9')),
                    DropdownMenuItem(value: 10, child: Text('Grade 10')),
                  ],
                  onChanged: (v) => setState(() => _selectedGrade = v),
                ),
              ],
            ],
          ),
        ),

        // ── User list ─────────────────────────────────────────────────────
        Expanded(
          child: usersAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline,
                      size: 48, color: Colors.red),
                  const SizedBox(height: 8),
                  const Text('Failed to load users'),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                    onPressed: () =>
                        ref.invalidate(allUsersProvider(providerParam)),
                  ),
                ],
              ),
            ),
            data: (users) {
              if (users.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.people_outline,
                          size: 56, color: AppColors.textMuted),
                      const SizedBox(height: 12),
                      Text(
                        _needsGrade && _selectedGrade == null
                            ? 'Select a grade to view ${_selectedRole}s.'
                            : 'No ${_selectedRole}s found.',
                        style: const TextStyle(
                            color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: users.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) => _ActiveUserTile(
                  user: users[i],
                  providerParam: providerParam,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ActiveUserTile extends ConsumerStatefulWidget {
  final UserModel user;
  final (String?, int?) providerParam;

  const _ActiveUserTile({
    required this.user,
    required this.providerParam,
  });

  @override
  ConsumerState<_ActiveUserTile> createState() => _ActiveUserTileState();
}

class _ActiveUserTileState extends ConsumerState<_ActiveUserTile> {
  late bool _isActive;
  bool _toggling = false;

  @override
  void initState() {
    super.initState();
    _isActive = widget.user.isActive;
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'teacher':
        return AppColors.secondary;
      case 'student':
        return AppColors.primary;
      case 'parent':
        return AppColors.accent;
      case 'admin':
        return AppColors.primaryDark;
      default:
        return AppColors.textSecondary;
    }
  }

  Future<void> _toggleActive(bool newValue) async {
    if (widget.user.role == 'admin') return;

    // Warn when deactivating a student that parent will also be deactivated
    if (!newValue && widget.user.role == 'student' &&
        widget.user.parentUserId != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Deactivate Student'),
          content: const Text(
              'Deactivating this student will also deactivate their linked parent account. Continue?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Deactivate'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() => _toggling = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.setUserActive(widget.user.id, newValue);
      setState(() => _isActive = newValue);
      ref.invalidate(allUsersProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(newValue
              ? '${widget.user.username} activated.'
              : '${widget.user.username} deactivated.'),
          backgroundColor:
              newValue ? AppColors.success : AppColors.warning,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  Future<void> _openEditSheet() async {
    final result = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditUserSheet(
        user: widget.user,
        onSave: (data) async {
          final api = ref.read(apiClientProvider);
          // Extract parent-rename keys — handled separately
          final parentId = data.remove('_rename_parent_id') as int?;
          final parentNewName = data.remove('_rename_parent_to') as String?;
          // Save the student/teacher/parent's own changes
          if (data.isNotEmpty) {
            await api.editUser(widget.user.id, data);
          }
          // Rename the linked parent user if requested
          if (parentId != null && parentNewName != null && parentNewName.isNotEmpty) {
            await api.editUser(parentId, {'username': parentNewName});
          }
          ref.invalidate(allUsersProvider);
        },
      ),
    );
    if (result != null && mounted) {
      // Build a human-readable summary of what changed
      final changes = <String>[];
      if (result.containsKey('username')) {
        changes.add('Username → "${result['username']}"');
      }
      if (result.containsKey('role')) {
        changes.add('Role → ${result['role']}');
      }
      if (result.containsKey('grade')) {
        changes.add('Grade → ${result['grade']}');
      }
      if (result.containsKey('new_mpin')) {
        changes.add('MPIN reset');
      }
      if (result.containsKey('parent_username')) {
        changes.add(result['parent_username'].toString().isEmpty
            ? 'Parent unlinked'
            : 'Parent linked → "${result['parent_username']}"');
      }
      if (result.containsKey('_rename_parent_to')) {
        changes.add('Parent username → "${result['_rename_parent_to']}"');
      }
      if (result.containsKey('student_username')) {
        changes.add(result['student_username'].toString().isEmpty
            ? 'Student unlinked'
            : 'Student → "${result['student_username']}"');
      }

      final summary = changes.isEmpty
          ? 'No changes made.'
          : changes.join('  ·  ');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${widget.user.username} updated',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14)),
              Text(summary,
                  style: const TextStyle(fontSize: 12)),
              if (result.containsKey('username') || result.containsKey('_rename_parent_to'))
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Affected user(s) will be prompted to log in again.',
                    style: TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ),
            ],
          ),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _confirmRevoke() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Revoke Access'),
        content: Text(
            'Are you sure you want to permanently revoke access for "${widget.user.username}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final api = ref.read(apiClientProvider);
      await api.revokeUser(widget.user.id);
      ref.invalidate(allUsersProvider);
      ref.invalidate(pendingUsersProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('User access revoked.'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final roleColor = _roleColor(widget.user.role);
    final isAdmin = widget.user.role == 'admin';

    // Build subtitle info lines
    final infoLines = <String>[];
    if (widget.user.grade != null) infoLines.add('Grade ${widget.user.grade}');
    if (widget.user.role == 'student') {
      infoLines.add(widget.user.parentUsername != null
          ? 'Parent: ${widget.user.parentUsername}'
          : 'No parent linked');
    }
    if (widget.user.role == 'parent') {
      infoLines.add(widget.user.studentUsername != null
          ? 'Student: ${widget.user.studentUsername}'
          : 'No student linked');
    }

    return Container(
      decoration: mindForgeCardDecoration(
        color: _isActive ? null : AppColors.error.withValues(alpha: 0.04),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Avatar ──────────────────────────────────────────────────
          CircleAvatar(
            radius: 22,
            backgroundColor:
                roleColor.withValues(alpha: _isActive ? 0.15 : 0.07),
            child: Text(
              widget.user.username[0].toUpperCase(),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: roleColor.withValues(alpha: _isActive ? 1.0 : 0.4),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // ── Name + info ─────────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.user.username,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: _isActive ? AppColors.textPrimary : AppColors.textMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: roleColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    widget.user.role.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _isActive ? roleColor : AppColors.textMuted,
                    ),
                  ),
                ),
                if (infoLines.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  ...infoLines.map((line) => Text(
                        line,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textMuted),
                        overflow: TextOverflow.ellipsis,
                      )),
                ],
              ],
            ),
          ),

          // ── Actions ─────────────────────────────────────────────────
          if (isAdmin)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.shield, color: AppColors.primaryDark, size: 22),
            )
          else
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Active toggle
                if (_toggling)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Transform.scale(
                    scale: 0.85,
                    child: Switch.adaptive(
                      value: _isActive,
                      activeColor: AppColors.success,
                      inactiveTrackColor:
                          AppColors.error.withValues(alpha: 0.3),
                      onChanged: _toggling ? null : _toggleActive,
                    ),
                  ),
                const SizedBox(height: 4),
                // Edit + Revoke buttons
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ActionBtn(
                      icon: Icons.edit_outlined,
                      color: AppColors.primary,
                      tooltip: 'Edit',
                      onTap: _toggling ? null : _openEditSheet,
                    ),
                    const SizedBox(width: 4),
                    _ActionBtn(
                      icon: Icons.block,
                      color: AppColors.error,
                      tooltip: 'Revoke',
                      onTap: _toggling ? null : _confirmRevoke,
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onTap;

  const _ActionBtn({
    required this.icon,
    required this.color,
    required this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: onTap == null ? AppColors.textMuted : color, size: 18),
        ),
      ),
    );
  }
}
