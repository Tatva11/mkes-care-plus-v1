import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../appointments/providers/appointment_provider.dart';
import '../models/whatsapp_appointment_request.dart';
import '../repositories/whatsapp_appointment_repository.dart';

final whatsappRequestsProvider = StateNotifierProvider<
    WhatsAppRequestsNotifier, AsyncValue<List<WhatsAppAppointmentRequest>>>((ref) {
  final repository = ref.watch(whatsappAppointmentRepositoryProvider);
  return WhatsAppRequestsNotifier(ref, repository);
});

final pendingWhatsAppRequestsCountProvider = Provider<int>((ref) {
  final requestsAsync = ref.watch(whatsappRequestsProvider);
  return requestsAsync.maybeWhen(
    data: (list) => list.where((r) => r.isPending).length,
    orElse: () => 0,
  );
});

class WhatsAppRequestsNotifier
    extends StateNotifier<AsyncValue<List<WhatsAppAppointmentRequest>>> {
  final Ref _ref;
  final WhatsAppAppointmentRepository _repository;
  String _currentStatusFilter = 'pending_review';
  String _currentDeptFilter = 'all';

  WhatsAppRequestsNotifier(this._ref, this._repository)
      : super(const AsyncValue.loading()) {
    loadRequests();
  }

  String get currentStatusFilter => _currentStatusFilter;
  String get currentDeptFilter => _currentDeptFilter;

  Future<void> loadRequests({
    String? status,
    String? department,
  }) async {
    if (status != null) _currentStatusFilter = status;
    if (department != null) _currentDeptFilter = department;

    state = const AsyncValue.loading();
    try {
      final items = await _repository.fetchRequests(
        status: _currentStatusFilter,
        department: _currentDeptFilter,
      );
      state = AsyncValue.data(items);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Approve a request via RPC.
  /// Refreshes appointments schedule provider so newly promoted appointment appears.
  Future<Map<String, dynamic>> approveRequest({
    required String requestId,
    String? doctorId,
    String? doctorName,
  }) async {
    try {
      final result = await _repository.approveRequest(
        requestId: requestId,
        doctorId: doctorId,
        doctorName: doctorName,
      );

      if (result['success'] == true) {
        // Refresh clinical appointments in dashboard
        _ref.invalidate(appointmentsNotifierProvider);

        // Update local request state
        state = state.whenData((list) {
          return list.map((req) {
            if (req.id == requestId) {
              return req.copyWith(
                status: 'approved',
                promotedAppointmentId: result['appointment_id'] as String?,
                reviewedAt: DateTime.now(),
              );
            }
            return req;
          }).toList();
        });
      }

      return result;
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Reject a request via RPC.
  Future<Map<String, dynamic>> rejectRequest({
    required String requestId,
    required String reason,
  }) async {
    try {
      final result = await _repository.rejectRequest(
        requestId: requestId,
        reason: reason,
      );

      if (result['success'] == true) {
        // Update local request state
        state = state.whenData((list) {
          return list.map((req) {
            if (req.id == requestId) {
              return req.copyWith(
                status: 'rejected',
                staffRemarks: reason,
                reviewedAt: DateTime.now(),
              );
            }
            return req;
          }).toList();
        });
      }

      return result;
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }
}
