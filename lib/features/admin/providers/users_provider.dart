import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_profile.dart';
import '../repositories/user_management_repository.dart';

final usersProvider =
    StateNotifierProvider<UsersNotifier, AsyncValue<List<UserProfile>>>((ref) {
  final repo = ref.watch(userManagementRepositoryProvider);
  return UsersNotifier(repo);
});

class UsersNotifier extends StateNotifier<AsyncValue<List<UserProfile>>> {
  final UserManagementRepository _repository;
  List<UserProfile> _allUsers = [];
  String _searchQuery = '';

  UsersNotifier(this._repository) : super(const AsyncValue.loading()) {
    fetchUsers();
  }

  Future<void> fetchUsers() async {
    state = const AsyncValue.loading();
    try {
      _allUsers = await _repository.fetchUsers();
      _applySearch();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void search(String query) {
    _searchQuery = query.toLowerCase();
    _applySearch();
  }

  void _applySearch() {
    if (_searchQuery.isEmpty) {
      state = AsyncValue.data(_allUsers);
    } else {
      final filtered = _allUsers.where((u) {
        return u.fullName.toLowerCase().contains(_searchQuery) ||
            u.email.toLowerCase().contains(_searchQuery) ||
            u.role.toLowerCase().contains(_searchQuery) ||
            (u.departmentName ?? u.department ?? '')
                .toLowerCase()
                .contains(_searchQuery);
      }).toList();
      state = AsyncValue.data(filtered);
    }
  }

  Future<void> createUser({
    required String fullName,
    required String email,
    required String password,
    String? phoneNumber,
    String? departmentId,
    String? designation,
    required String role,
    double? salary,
    DateTime? joiningDate,
  }) async {
    await _repository.createUser(
      fullName: fullName,
      email: email,
      password: password,
      phoneNumber: phoneNumber,
      departmentId: departmentId,
      designation: designation,
      role: role,
      salary: salary,
      joiningDate: joiningDate,
    );
    await fetchUsers(); // Refresh list
  }

  Future<void> updateUser(String id, Map<String, dynamic> updates) async {
    await _repository.updateUser(id, updates);
    await fetchUsers();
  }

  Future<void> toggleStatus(String id, bool isActive) async {
    await _repository.toggleUserStatus(id, isActive);
    await fetchUsers();
  }

  Future<void> deleteUser(String id) async {
    await _repository.deleteUser(id);
    await fetchUsers();
  }
}
