with open('supabase/schema.sql', 'r', encoding='utf-8') as f:
    schema = f.read()

import re

tables = ['patients', 'appointments', 'vendors', 'inventory', 'purchase_orders', 'purchase_order_items', 'dental_lab', 'billing', 'tasks', 'staff_attendance']

for t in tables:
    pattern = rf'CREATE TABLE IF NOT EXISTS "?public"?\."?{t}"?\s*\((.*?)\);'
    m = re.search(pattern, schema, re.DOTALL | re.IGNORECASE)
    if m:
        print(f"=== {t} ===")
        for line in m.group(1).splitlines():
            line = line.strip()
            if line and not line.startswith('CONSTRAINT'):
                print(" ", line)
    else:
        print(f"=== {t} NOT MATCHED ===")

