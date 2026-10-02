import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/leave_request.dart';
import '../repositories/leave_repository.dart';

// ---------------------------------------------------------------------------
// Staff-facing: their own leave requests.
// ---------------------------------------------------------------------------
final staffLeaveRequestsProvider = StateNotifierProvider.family<
    StaffLeaveNotifier,
    AsyncValue<List<LeaveRequest>>,
    String>((ref, staffId) {
  final repo = ref.watch(leaveRepositoryProvider);
  return StaffLeaveNotifier(repo, staffId);
});

class StaffLeaveNotifier
    extends StateNotifier<AsyncValue<List<LeaveRequest>>> {
  final LeaveRepository _repository;
  final String _staffId;

  StaffLeaveNotifier(this._repository, this._staffId)
      : super(const AsyncValue.loading()) {
    fetchRequests();
  }

  Future<void> fetchRequests() async {
    state = const AsyncValue.loading();
    try {
      final requests = await _repository.fetchStaffLeaveRequests(_staffId);
      state = AsyncValue.data(requests);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> createRequest({
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
  }) async {
    await _repository.createLeaveRequest(
      staffId: _staffId,
      startDate: startDate,
      endDate: endDate,
      reason: reason,
    );
    await fetchRequests();
  }

  Future<void> cancelRequest(String id) async {
    await _repository.cancelLeaveRequest(id);
    await fetchRequests();
  }
}

// ---------------------------------------------------------------------------
// Admin-facing: pending-only (for quick approval action).
// ---------------------------------------------------------------------------
final pendingAdminLeaveRequestsProvider =
    StateNotifierProvider<AdminPendingLeaveNotifier, AsyncValue<List<LeaveRequest>>>(
        (ref) {
  final repo = ref.watch(leaveRepositoryProvider);
  return AdminPendingLeaveNotifier(repo);
});

class AdminPendingLeaveNotifier
    extends StateNotifier<AsyncValue<List<LeaveRequest>>> {
  final LeaveRepository _repository;

  AdminPendingLeaveNotifier(this._repository)
      : super(const AsyncValue.loading()) {
    fetchPending();
  }

  Future<void> fetchPending() async {
    state = const AsyncValue.loading();
    try {
      final requests = await _repository.fetchAllPendingLeaveRequests();
      state = AsyncValue.data(requests);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> approveRequest(String id, String adminId) async {
    await _repository.approveLeaveRequest(id, adminId);
    await fetchPending();
  }

  Future<void> rejectRequest(String id, String adminId, String reason) async {
    await _repository.rejectLeaveRequest(id, adminId, reason);
    await fetchPending();
  }
}

// ---------------------------------------------------------------------------
// Admin-facing: all leave requests (for leave history tab).
// ---------------------------------------------------------------------------
final adminAllLeaveRequestsProvider =
    StateNotifierProvider<AdminAllLeaveNotifier, AsyncValue<List<LeaveRequest>>>(
        (ref) {
  final repo = ref.watch(leaveRepositoryProvider);
  return AdminAllLeaveNotifier(repo);
});

class AdminAllLeaveNotifier
    extends StateNotifier<AsyncValue<List<LeaveRequest>>> {
  final LeaveRepository _repository;

  AdminAllLeaveNotifier(this._repository)
      : super(const AsyncValue.loading()) {
    fetchAll();
  }

  Future<void> fetchAll() async {
    state = const AsyncValue.loading();
    try {
      final requests = await _repository.fetchAllLeaveRequests();
      state = AsyncValue.data(requests);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> approveRequest(String id, String adminId) async {
    await _repository.approveLeaveRequest(id, adminId);
    await fetchAll();
  }

  Future<void> rejectRequest(String id, String adminId, String reason) async {
    await _repository.rejectLeaveRequest(id, adminId, reason);
    await fetchAll();
  }
}
