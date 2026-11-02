-- ============================================================================
-- MKES CARE+ — Diagnostic Query: Identify Inventory Item Dependencies
-- File: scripts/diagnose_inventory_dependency.sql
-- Description:
--   Inspects item '03fafd3c-09a5-413d-98fa-75606fe1a376' and all related
--   surgery items, surgeries, patients, and other inventory foreign keys.
-- ============================================================================

-- 1. Check the inventory item details
SELECT
  id AS inventory_id,
  name AS item_name,
  sku,
  category,
  quantity,
  unit,
  created_at
FROM public.inventory
WHERE id = '03fafd3c-09a5-413d-98fa-75606fe1a376';

-- 2. Inspect dependent eye surgery items
SELECT
  esi.id AS item_id,
  esi.eye_surgery_id,
  esi.inventory_item_id,
  esi.planned_quantity,
  esi.actual_quantity,
  esi.source,
  esi.created_at AS item_created_at,
  es.patient_id,
  es.surgery_date,
  es.surgery_time,
  es.status AS surgery_status,
  es.inventory_consumed_at,
  p.patient_number,
  p.name AS patient_name,
  p.department AS patient_dept,
  p.visit_date AS patient_visit_date,
  CASE
    WHEN p.patient_number LIKE 'P%' OR p.patient_number LIKE 'E-%' OR p.patient_number LIKE 'D-%' THEN 'CONFIRMED DEMO PATIENT'
    WHEN p.id IS NULL THEN 'ORPHANED DEMO RECORD'
    ELSE 'GENUINE CLINICAL RECORD'
  END AS record_classification
FROM public.eye_surgery_items esi
LEFT JOIN public.eye_surgeries es ON es.id = esi.eye_surgery_id
LEFT JOIN public.patients p ON p.id = es.patient_id
WHERE esi.inventory_item_id = '03fafd3c-09a5-413d-98fa-75606fe1a376';

-- 3. Check all other tables referencing this inventory item
SELECT 'clinical_inventory_usage' AS table_name, count(*) AS referencing_rows
FROM public.clinical_inventory_usage WHERE inventory_id = '03fafd3c-09a5-413d-98fa-75606fe1a376'
UNION ALL
SELECT 'eye_surgery_item_templates', count(*)
FROM public.eye_surgery_item_templates WHERE inventory_item_id = '03fafd3c-09a5-413d-98fa-75606fe1a376'
UNION ALL
SELECT 'stock_requests', count(*)
FROM public.stock_requests WHERE inventory_id = '03fafd3c-09a5-413d-98fa-75606fe1a376'
UNION ALL
SELECT 'purchase_order_items', count(*)
FROM public.purchase_order_items WHERE inventory_id = '03fafd3c-09a5-413d-98fa-75606fe1a376'
UNION ALL
SELECT 'inventory_batches', count(*)
FROM public.inventory_batches WHERE inventory_id = '03fafd3c-09a5-413d-98fa-75606fe1a376'
UNION ALL
SELECT 'department_inventory', count(*)
FROM public.department_inventory WHERE inventory_id = '03fafd3c-09a5-413d-98fa-75606fe1a376'
UNION ALL
SELECT 'inventory_transactions', count(*)
FROM public.inventory_transactions WHERE inventory_id = '03fafd3c-09a5-413d-98fa-75606fe1a376';

