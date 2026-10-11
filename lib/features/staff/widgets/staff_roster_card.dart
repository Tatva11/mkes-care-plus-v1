import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../admin/providers/users_provider.dart';
import 'staff_member_tile.dart';

class StaffRosterCard extends ConsumerStatefulWidget {
  const StaffRosterCard({super.key});

  @override
  ConsumerState<StaffRosterCard> createState() => _StaffRosterCardState();
}

class _StaffRosterCardState extends ConsumerState<StaffRosterCard> {
  final _searchController = TextEditingController();
  String _statusFilter = 'all'; // 'all', 'active', 'inactive'
  bool _showSearch = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usersState = ref.watch(usersProvider);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.6),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Card header
          DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.outlineVariant),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.badge_outlined,
                    size: 22,
                    color: AppColors.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'Staff Roster',
                      style: AppTypography.headlineMd,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _showSearch = !_showSearch;
                        if (!_showSearch) _searchController.clear();
                      });
                    },
                    icon: Icon(_showSearch ? Icons.close : Icons.search),
                    color: AppColors.onSurfaceVariant,
                    iconSize: 22,
                    tooltip: _showSearch ? 'Close search' : 'Search staff',
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(
                      Icons.filter_list,
                      color: AppColors.onSurfaceVariant,
                      size: 22,
                    ),
                    tooltip: 'Filter status',
                    initialValue: _statusFilter,
                    onSelected: (val) => setState(() => _statusFilter = val),
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'all', child: Text('All Staff')),
                      PopupMenuItem(value: 'active', child: Text('Active Only')),
                      PopupMenuItem(
                          value: 'inactive', child: Text('Inactive Only')),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Optional Search Bar
          if (_showSearch)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search by name, email, department...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () =>
                              setState(() => _searchController.clear()),
                        )
                      : null,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),

          // Table header
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              children: [
                const SizedBox(width: 40 + AppSpacing.sm), // avatar width
                Expanded(
                  child: Text(
                    'Name & Role',
                    style: AppTypography.labelCaps.copyWith(
                      color: AppColors.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  'Status / Contact',
                  style: AppTypography.labelCaps.copyWith(
                    color: AppColors.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(width: 28), // chevron width
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.outlineVariant),

          // Roster list
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.xs,
            ),
            child: usersState.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (e, st) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Unable to load staff roster: $e',
                        style: AppTypography.bodySm.copyWith(color: AppColors.error),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      TextButton.icon(
                        onPressed: () => ref.invalidate(usersProvider),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (users) {
                var staff =
                    users.where((user) => user.role == 'staff').toList();

                // Status filtering
                if (_statusFilter == 'active') {
                  staff = staff.where((u) => u.isActive).toList();
                } else if (_statusFilter == 'inactive') {
                  staff = staff.where((u) => !u.isActive).toList();
                }

                // Search query filtering
                final query = _searchController.text.trim().toLowerCase();
                if (query.isNotEmpty) {
                  staff = staff.where((u) {
                    final nameMatch = u.fullName.toLowerCase().contains(query);
                    final emailMatch = u.email.toLowerCase().contains(query);
                    final deptMatch = (u.departmentName ?? u.department ?? '')
                        .toLowerCase()
                        .contains(query);
                    final desigMatch =
                        (u.designation ?? '').toLowerCase().contains(query);
                    return nameMatch || emailMatch || deptMatch || desigMatch;
                  }).toList();
                }

                if (staff.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.people_outline,
                              size: 40, color: AppColors.outline),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            query.isNotEmpty
                                ? 'No staff matching "$query"'
                                : 'No staff found.',
                            style: AppTypography.bodyMd.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                          if (query.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.xs),
                            TextButton(
                              onPressed: () =>
                                  setState(() => _searchController.clear()),
                              child: const Text('Clear search'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }

                return Column(
                  children: [
                    for (var i = 0; i < staff.length; i++)
                      StaffMemberTile(
                        user: staff[i],
                        showDivider: i < staff.length - 1,
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
