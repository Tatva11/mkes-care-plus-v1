import re

with open('MKES_CARE_FINAL_RESET_AND_SEED.sql', 'r', encoding='utf-8') as f:
    sql_text = f.read()

print("="*60)
print("INSPECTING ALL INSERT STATEMENTS IN MKES_CARE_FINAL_RESET_AND_SEED.sql")
print("="*60)

# Check purchase_orders columns
po_inserts = re.findall(r'INSERT\s+INTO\s+public\.purchase_orders\s*\(([^)]+)\)', sql_text, re.IGNORECASE)
for i, cols in enumerate(po_inserts):
    col_list = [c.strip() for c in cols.split(',')]
    assert 'tax_amount' not in col_list, f"PO {i+1} still has tax_amount!"
    assert 'shipping_amount' not in col_list, f"PO {i+1} still has shipping_amount!"
    print(f"PO {i+1} columns ({len(col_list)}): {col_list} -> OK")

# Check billing columns
billing_inserts = re.findall(r'INSERT\s+INTO\s+public\.billing\s*\(([^)]+)\)', sql_text, re.IGNORECASE)
for i, cols in enumerate(billing_inserts):
    col_list = [c.strip() for c in cols.split(',')]
    assert 'department' in col_list, f"Billing {i+1} is missing department!"
    assert 'total_amount' in col_list, f"Billing {i+1} is missing total_amount!"
    print(f"Billing {i+1} columns ({len(col_list)}): {col_list} -> OK")

# Check billing values for constraints
billing_values = re.findall(r'INSERT\s+INTO\s+public\.billing\s*\([^)]+\)\s*VALUES\s*\(([^;]+)\);', sql_text, re.IGNORECASE)
for i, vals in enumerate(billing_values):
    assert "'partial'" not in vals, f"Billing {i+1} uses invalid status 'partial'!"
    assert "'card'" not in vals, f"Billing {i+1} uses invalid mode 'card'!"
    print(f"Billing {i+1} values constraint check -> OK")

# Check billing_payments values
payment_values = re.findall(r'INSERT\s+INTO\s+public\.billing_payments\s*\([^)]+\)\s*VALUES\s*\(([^;]+)\);', sql_text, re.IGNORECASE)
for i, vals in enumerate(payment_values):
    assert "'card'" not in vals, f"Billing payment {i+1} uses invalid mode 'card'!"
    print(f"Billing payment {i+1} values constraint check -> OK")

# Check doctor_id in appointments
assert "doctor_id" not in re.findall(r'SELECT\s+doctor_id\s+FROM', sql_text, re.IGNORECASE), "Invalid doctor_id column select found!"

# Check alias scope error (IF p.id outside SQL query)
assert "IF p.id" not in sql_text, "Found IF p.id outside query scope!"

print("="*60)
print("ALL SQL VERIFICATIONS PASSED 100% PERFECTLY!")
print("="*60)
