with open('scripts/generate_final_reset_and_seed.py', 'r', encoding='utf-8') as f:
    content = f.read()

target = "  RAISE NOTICE 'MKES CARE+ Complete Data Cleanup and Seeding verified successfully!';\nEND $$;\n\nCOMMIT;\n\"\"\""

queries = """  RAISE NOTICE 'MKES CARE+ Complete Data Cleanup and Seeding verified successfully!';
END $$;

COMMIT;

-- ============================================================================
-- FINAL VERIFICATION AUDIT QUERIES
-- ============================================================================

-- 1. Patient distribution by department (Expected: 25 Eye, 25 Dental, 50 Total)
SELECT department, count(*) AS patient_count
FROM public.patients
GROUP BY department
ORDER BY department;

-- 2. 3-Day Appointment schedule count per day (Expected: 8 Yesterday, 9 Today, 8 Tomorrow)
SELECT appointment_date, count(*) AS daily_appointments
FROM public.appointments
GROUP BY appointment_date
ORDER BY appointment_date;

-- 3. Billing Invoices verification (Expected: 5 invoices with correct balances & payment modes)
SELECT invoice_number, total_amount, amount_paid, (total_amount - amount_paid) AS remaining_balance, payment_status, payment_mode
FROM public.billing
ORDER BY invoice_number;

-- 4. Central Inventory stock status summary (Expected: 9 Normal, 3 Low Stock, 2 Expired)
SELECT
  CASE
    WHEN expiry_date < CURRENT_DATE THEN 'Expired (Quarantine)'
    WHEN quantity <= minimum_stock THEN 'Low Stock (Replenish)'
    ELSE 'Normal Stock'
  END AS stock_condition,
  count(*) AS item_count
FROM public.inventory
GROUP BY 1
ORDER BY 1;

-- 5. Operational entities summary
SELECT
  (SELECT count(*) FROM public.vendors) AS vendors_count,
  (SELECT count(*) FROM public.purchase_orders) AS purchase_orders_count,
  (SELECT count(*) FROM public.purchase_order_items) AS po_items_count,
  (SELECT count(*) FROM public.dental_lab) AS dental_lab_cases_count,
  (SELECT count(*) FROM public.tasks) AS active_tasks_count,
  (SELECT count(*) FROM public.profiles WHERE role = 'admin') AS preserved_admins_count,
  (SELECT count(*) FROM public.profiles WHERE role = 'staff') AS preserved_staff_count;
\"\"\""""

if target in content:
    content = content.replace(target, queries)
    with open('scripts/generate_final_reset_and_seed.py', 'w', encoding='utf-8') as f:
        f.write(content)
    print("Replaced successfully!")
else:
    # Try with \r\n
    target_crlf = target.replace('\n', '\r\n')
    if target_crlf in content:
        content = content.replace(target_crlf, queries.replace('\n', '\r\n'))
        with open('scripts/generate_final_reset_and_seed.py', 'w', encoding='utf-8') as f:
            f.write(content)
        print("Replaced with CRLF successfully!")
    else:
        print("Target not found!")

