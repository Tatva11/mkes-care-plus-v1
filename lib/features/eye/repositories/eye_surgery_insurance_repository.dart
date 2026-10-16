import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/supabase_provider.dart';
import '../models/eye_surgery_insurance_model.dart';

final eyeSurgeryInsuranceRepositoryProvider = Provider<EyeSurgeryInsuranceRepository>((ref) {
  return EyeSurgeryInsuranceRepository(ref.watch(supabaseProvider));
});

class EyeSurgeryInsuranceRepository {
  final SupabaseClient _supabase;

  EyeSurgeryInsuranceRepository(this._supabase);

  /// Fetch insurance record and its associated payment history for a specific eye surgery.
  Future<EyeSurgeryInsuranceModel?> fetchInsuranceForSurgery(String eyeSurgeryId) async {
    try {
      final response = await _supabase
          .from('eye_surgery_insurances')
          .select('*, eye_surgery_insurance_payments(*)')
          .eq('eye_surgery_id', eyeSurgeryId)
          .maybeSingle();

      if (response == null) return null;
      return EyeSurgeryInsuranceModel.fromJson(response);
    } catch (e) {
      debugPrint('EyeSurgeryInsuranceRepository.fetchInsuranceForSurgery error: $e');
      rethrow;
    }
  }

  /// Create or update eye surgery insurance configuration.
  Future<EyeSurgeryInsuranceModel> saveInsurance(EyeSurgeryInsuranceModel insurance) async {
    try {
      final json = insurance.toJson();
      if (insurance.id.isEmpty) {
        json.remove('id');
      }

      final response = await _supabase
          .from('eye_surgery_insurances')
          .upsert(
            json,
            onConflict: 'eye_surgery_id',
          )
          .select('*, eye_surgery_insurance_payments(*)')
          .single();

      return EyeSurgeryInsuranceModel.fromJson(response);
    } catch (e) {
      debugPrint('EyeSurgeryInsuranceRepository.saveInsurance error: $e');
      rethrow;
    }
  }

  /// Record an insurance payment against an insurance claim.
  Future<EyeSurgeryInsurancePaymentModel> recordInsurancePayment(
    EyeSurgeryInsurancePaymentModel payment,
  ) async {
    try {
      final json = payment.toJson();
      if (payment.id == null || payment.id!.isEmpty) {
        json.remove('id');
      }
      json['recorded_by'] = _supabase.auth.currentUser?.id;

      final response = await _supabase
          .from('eye_surgery_insurance_payments')
          .insert(json)
          .select()
          .single();

      return EyeSurgeryInsurancePaymentModel.fromJson(response);
    } catch (e) {
      debugPrint('EyeSurgeryInsuranceRepository.recordInsurancePayment error: $e');
      rethrow;
    }
  }

  /// Update claim decision/status with optional approved amount or rejection reason.
  Future<EyeSurgeryInsuranceModel> updateClaimStatus({
    required String insuranceId,
    required EyeSurgeryClaimStatus newStatus,
    double? approvedAmount,
    String? rejectionReason,
    String? claimNumber,
    DateTime? submissionDate,
  }) async {
    try {
      final updateData = <String, dynamic>{
        'claim_status': newStatus.value,
        'updated_at': DateTime.now().toIso8601String(),
        if (approvedAmount != null) 'approved_amount': approvedAmount,
        if (rejectionReason != null) 'rejection_reason': rejectionReason,
        if (claimNumber != null && claimNumber.trim().isNotEmpty)
          'claim_number': claimNumber.trim(),
        if (submissionDate != null)
          'claim_submission_date':
              '${submissionDate.year.toString().padLeft(4, '0')}-${submissionDate.month.toString().padLeft(2, '0')}-${submissionDate.day.toString().padLeft(2, '0')}',
      };

      final response = await _supabase
          .from('eye_surgery_insurances')
          .update(updateData)
          .eq('id', insuranceId)
          .select('*, eye_surgery_insurance_payments(*)')
          .single();

      return EyeSurgeryInsuranceModel.fromJson(response);
    } catch (e) {
      debugPrint('EyeSurgeryInsuranceRepository.updateClaimStatus error: $e');
      rethrow;
    }
  }
}
