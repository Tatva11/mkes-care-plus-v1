import re

sql_file = "MKES_CARE_FINAL_RESET_AND_SEED.sql"
with open(sql_file, "r", encoding="utf-8") as f:
    sql = f.read()

print(f"=== VALIDATING {sql_file} (Size: {len(sql)} bytes) ===")

errors = []

# 1. Check transaction boundaries
if "BEGIN;" not in sql:
    errors.append("Does not contain BEGIN;")
if "COMMIT;" not in sql:
    errors.append("Missing COMMIT;")

# 2. Check RLS and trigger settings
if "SET LOCAL row_security = off;" not in sql:
    errors.append("Missing SET LOCAL row_security = off;")
if "DISABLE ROW LEVEL SECURITY;" not in sql:
    errors.append("Missing DISABLE ROW LEVEL SECURITY;")
if "DISABLE TRIGGER USER;" not in sql:
    errors.append("Missing DISABLE TRIGGER USER;")
if "ENABLE ROW LEVEL SECURITY;" not in sql:
    errors.append("Missing ENABLE ROW LEVEL SECURITY;")
if "ENABLE TRIGGER USER;" not in sql:
    errors.append("Missing ENABLE TRIGGER USER;")

# 3. Check PL/pgSQL alias bugs (like p.id outside query)
bad_p_id = re.findall(r'IF\s+p\.id\s+IS', sql)
if bad_p_id:
    errors.append(f"Found {len(bad_p_id)} occurrences of invalid alias 'p.id'")

# 4. Check all DO blocks have matching END $$;
do_count = len(re.findall(r'DO\s+\$\$', sql))
end_count = len(re.findall(r'END\s+\$\$;', sql))
print(f"DO blocks: {do_count}, END blocks: {end_count}")
if do_count != end_count:
    errors.append(f"Mismatched DO ({do_count}) and END ({end_count}) blocks")

# 5. Check patient count in INSERT statements
eye_patients = set(re.findall(r"\'(E-\d{4})\'", sql))
dental_patients = set(re.findall(r"\'(D-\d{4})\'", sql))
print(f"Eye patients seeded: {len(eye_patients)} (Expected: 25)")
print(f"Dental patients seeded: {len(dental_patients)} (Expected: 25)")
if len(eye_patients) != 25:
    errors.append(f"Expected 25 eye patients, found {len(eye_patients)}")
if len(dental_patients) != 25:
    errors.append(f"Expected 25 dental patients, found {len(dental_patients)}")

# 6. Check appointments count & daily distribution
# Find all appointment lines in appointments block
appt_match = re.search(r'INSERT INTO public\.appointments\s*\([^)]+\)\s*VALUES([\s\S]+?)\);\s*END', sql)
if appt_match:
    lines = appt_match.group(1).split('gen_random_uuid()')
    appt_entries = [l for l in lines if 'CURRENT_DATE' in l]
    print(f"Total appointments entries: {len(appt_entries)}")
    yesterday = [l for l in appt_entries if "- INTERVAL '1 day'" in l]
    today = [l for l in appt_entries if "CURRENT_DATE," in l and "INTERVAL" not in l]
    tomorrow = [l for l in appt_entries if "+ INTERVAL '1 day'" in l]
    print(f"  Yesterday appointments: {len(yesterday)} (Expected: 8)")
    print(f"  Today appointments:     {len(today)} (Expected: 9)")
    print(f"  Tomorrow appointments:  {len(tomorrow)} (Expected: 8)")
    if len(yesterday) < 5 or len(today) < 5 or len(tomorrow) < 5:
        errors.append("Appointments per day below 5 minimum requirement!")

# 7. Check Invoices
invoices = set(re.findall(r"\'(INV-2026-\d{3})\'", sql))
print(f"Seeded invoices: {len(invoices)} (Expected: 5)")
if len(invoices) != 5:
    errors.append(f"Expected 5 invoices, found {len(invoices)}")

# 8. Check Vendors, POs, Lab cases
vendors = set(re.findall(r"\'(VEND-\d{3})\'", sql))
print(f"Seeded vendors: {len(vendors)} (Expected: 8)")
pos = set(re.findall(r"\'(PO-2026-\d{3})\'", sql))
print(f"Seeded purchase orders: {len(pos)} (Expected: 5)")
labs = set(re.findall(r"\'(LAB-2026-\d{3})\'", sql))
print(f"Seeded dental lab cases: {len(labs)} (Expected: 5)")
inv_items = set(re.findall(r"\'(SKU-[A-Z0-9\-]+)\'", sql))
print(f"Seeded inventory SKUs: {len(inv_items)} (Expected: 14)")

# 9. Check deletion sequence
tbls_match = re.search(r"tbls TEXT\[\] := ARRAY\[([\s\S]+?)\];", sql)
if tbls_match:
    tbl_list = re.findall(r"\'([a-z_]+)\'", tbls_match.group(1))
    print(f"Tables in cleanup array: {len(tbl_list)}")
    if 'eye_surgery_items' not in tbl_list:
        errors.append("eye_surgery_items missing from cleanup array!")
    if 'inventory' not in tbl_list:
        errors.append("inventory missing from cleanup array!")
    esi_idx = tbl_list.index('eye_surgery_items')
    inv_idx = tbl_list.index('inventory')
    print(f"  eye_surgery_items index: {esi_idx}, inventory index: {inv_idx}")
    if esi_idx >= inv_idx:
        errors.append(f"eye_surgery_items (index {esi_idx}) must be deleted BEFORE inventory (index {inv_idx})!")

# Summary
if not errors:
    print("\n>>> ALL VALIDATION CHECKS PASSED PERFECTLY! ZERO ERRORS FOUND! <<<")
else:
    print(f"\n>>> VALIDATION FAILED WITH {len(errors)} ERRORS: <<<")
    for e in errors:
        print("  -", e)
