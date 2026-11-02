import glob
import re

files_to_check = {
    'patients': 'supabase_sprint5_1_dental_lab.sql',
    'appointments': 'supabase_sprint5_4_clinical_records.sql',
    'billing': 'supabase/migrations/20260930140000_billing_database_foundation.sql',
    'purchase_orders': 'supabase_sprint6_4_purchase_orders.sql',
    'purchase_order_items': 'supabase_sprint6_4_purchase_orders.sql'
}

for tbl, f in files_to_check.items():
    with open(f, 'r', encoding='utf-8') as fp:
        c = fp.read()
    m = re.search(r'CREATE TABLE [^;]*\b' + tbl + r'\b\s*\(([\s\S]+?)\);', c, re.IGNORECASE)
    if m:
        cols = []
        for line in m.group(1).split('\n'):
            line = line.strip().rstrip(',')
            if not line or line.startswith('--') or line.startswith('CONSTRAINT') or line.startswith('PRIMARY KEY') or line.startswith('FOREIGN KEY') or line.startswith('UNIQUE') or line.startswith('CHECK'):
                continue
            cm = re.match(r'\"?(\w+)\"?', line)
            if cm:
                cols.append(cm.group(1))
        print(f"{tbl} in {f}:\n  {cols}\n")

