-- Migration: 20261016160000_fix_eye_surgery_inventory_consumption_rpc.sql
-- Description: Fix consume_eye_surgery_inventory RPC to insert into eye_surgery_inventory_consumptions
-- before updating eye_surgeries, resolving P0001 trigger guard exception.

CREATE OR REPLACE FUNCTION public.consume_eye_surgery_inventory(
  p_eye_surgery_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_surgery RECORD;
  v_item RECORD;
  v_consumed_count INT := 0;
  v_consumed_at TIMESTAMPTZ := now();
BEGIN
  -- Authorisation check
  IF NOT public.is_admin_or_staff() THEN
    RAISE EXCEPTION 'Active Admin or Staff access required';
  END IF;

  -- Lock surgery record
  SELECT * INTO v_surgery
  FROM public.eye_surgeries
  WHERE id = p_eye_surgery_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Eye Surgery not found';
  END IF;

  -- Idempotency check: if already in_surgery or past it, return success without re-deducting
  IF v_surgery.inventory_consumed_at IS NOT NULL OR v_surgery.status IN ('in_surgery', 'post_op', 'discharged') THEN
    RETURN jsonb_build_object(
      'already_consumed', true,
      'status', v_surgery.status,
      'surgery_id', p_eye_surgery_id,
      'items_consumed', 0
    );
  END IF;

  -- Validation: must be in pre_op
  IF v_surgery.status <> 'pre_op' THEN
    RAISE EXCEPTION 'Surgery must be in Pre-op before inventory can be consumed';
  END IF;

  -- Pre-op checklist validation
  IF v_surgery.pre_op_checklist->'identity_verified' IS DISTINCT FROM 'true'::jsonb
    OR v_surgery.pre_op_checklist->'consent_confirmed' IS DISTINCT FROM 'true'::jsonb
    OR v_surgery.pre_op_checklist->'correct_eye_confirmed' IS DISTINCT FROM 'true'::jsonb
    OR v_surgery.pre_op_checklist->'pre_op_exam_completed' IS DISTINCT FROM 'true'::jsonb
    OR v_surgery.pre_op_checklist->'investigations_reviewed' IS DISTINCT FROM 'true'::jsonb
    OR v_surgery.pre_op_checklist->'allergies_checked' IS DISTINCT FROM 'true'::jsonb
    OR v_surgery.pre_op_checklist->'assigned_staff_confirmed' IS DISTINCT FROM 'true'::jsonb
    OR v_surgery.pre_op_checklist->'procedure_confirmed' IS DISTINCT FROM 'true'::jsonb THEN
    RAISE EXCEPTION 'Complete the pre-op checklist before entering surgery.';
  END IF;

  -- Process inventory items
  FOR v_item IN
    SELECT esi.id, esi.inventory_item_id, esi.planned_quantity,
           esi.actual_quantity, esi.allocation_status,
           inv.name, inv.quantity AS stock_qty
    FROM public.eye_surgery_items esi
    LEFT JOIN public.inventory inv ON inv.id = esi.inventory_item_id
    WHERE esi.eye_surgery_id = p_eye_surgery_id
  LOOP
    IF v_item.allocation_status = 'allocated' THEN
      -- Already deducted at assignment/scheduling — just mark as consumed
      UPDATE public.eye_surgery_items
      SET allocation_status = 'consumed',
          consumed_at = v_consumed_at,
          updated_at = v_consumed_at
      WHERE id = v_item.id;
      v_consumed_count := v_consumed_count + 1;
    ELSIF v_item.allocation_status = 'pending' THEN
      -- Validate stock
      IF v_item.actual_quantity <= 0 THEN
        RAISE EXCEPTION 'Surgery item quantity must be greater than zero for %', v_item.name;
      END IF;
      IF v_item.stock_qty < v_item.actual_quantity THEN
        RAISE EXCEPTION 'Insufficient stock for %: available %, requested %',
          v_item.name, v_item.stock_qty, v_item.actual_quantity;
      END IF;

      -- Deduct inventory using perform_stock_operation
      PERFORM public.perform_stock_operation(
        p_inventory_id := v_item.inventory_item_id,
        p_transaction_type := 'stock_out',
        p_quantity := v_item.actual_quantity,
        p_reason := 'Dispensed to Patient',
        p_remarks := format('Eye Surgery %s: %s', p_eye_surgery_id, v_item.name),
        p_patient_id := v_surgery.patient_id
      );

      UPDATE public.eye_surgery_items
      SET allocation_status = 'consumed',
          consumed_at = v_consumed_at,
          updated_at = v_consumed_at
      WHERE id = v_item.id;
      v_consumed_count := v_consumed_count + 1;
    END IF;
  END LOOP;

  -- CRITICAL FIX: Record into eye_surgery_inventory_consumptions BEFORE updating eye_surgeries
  -- to satisfy the validate_eye_surgery_status_transition trigger guard.
  INSERT INTO public.eye_surgery_inventory_consumptions (
    eye_surgery_id, consumed_at, item_count
  ) VALUES (
    p_eye_surgery_id, v_consumed_at, v_consumed_count
  )
  ON CONFLICT (eye_surgery_id) DO UPDATE
    SET consumed_at = EXCLUDED.consumed_at,
        item_count = EXCLUDED.item_count;

  -- Advance surgery status to in_surgery
  UPDATE public.eye_surgeries
  SET status = 'in_surgery',
      inventory_consumed_at = v_consumed_at,
      updated_at = v_consumed_at
  WHERE id = p_eye_surgery_id;

  RETURN jsonb_build_object(
    'status', 'in_surgery',
    'surgery_id', p_eye_surgery_id,
    'items_consumed', v_consumed_count
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.consume_eye_surgery_inventory(UUID) TO authenticated;
