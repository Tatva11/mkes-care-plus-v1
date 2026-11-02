import glob
import re

tables = {}
for f in sorted(glob.glob('supabase/**/*.sql', recursive=True) + glob.glob('*.sql')):
    if 'clean_and_seed' in f or 'MKES_CARE' in f:
        continue
    with open(f, 'r', encoding='utf-8', errors='ignore') as fp:
        c = fp.read()
    for m in re.finditer(r'CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:public\.)?(\w+)\s*\(([\s\S]+?)\);', c, re.IGNORECASE):
        tname = m.group(1).lower()
        if tname not in tables:
            tables[tname] = []
        body = m.group(2)
        for line in body.split('\n'):
            line = line.strip().rstrip(',')
            if not line or line.startswith('--') or line.startswith('CONSTRAINT') or line.startswith('PRIMARY KEY') or line.startswith('FOREIGN KEY') or line.startswith('UNIQUE') or line.startswith('CHECK'):
                continue
            col_match = re.match(r'\"?(\w+)\"?\s+([A-Za-z0-9_\(\)]+)', line)
            if col_match:
                col = col_match.group(1).lower()
                if col not in tables[tname]:
                    tables[tname].append(col)

print(f"Total tables cataloged: {len(tables)}")
target_tables = [
    'patients', 'appointments', 'eye_examinations', 'dental_treatments',
    'dental_lab', 'billing', 'billing_items', 'billing_payments',
    'vendors', 'purchase_orders', 'purchase_order_items', 'inventory',
    'inventory_batches', 'tasks', 'staff_attendance', 'eye_surgeries',
    'eye_surgery_items', 'eye_surgery_item_templates', 'clinical_inventory_usage'
]

for t in target_tables:
    if t in tables:
        print(f"\nTABLE: {t}")
        print("  " + ", ".join(tables[t]))
    else:
        print(f"\nTABLE: {t} -> NOT FOUND IN DDL!")

