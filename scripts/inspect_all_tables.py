import re
import glob

def find_table_schema(table_name):
    print(f"=== Table: {table_name} ===")
    found = False
    with open('supabase/schema.sql', 'r', encoding='utf-8') as f:
        schema_sql = f.read()

    # Search in schema.sql
    pattern = rf'CREATE TABLE (?:IF NOT EXISTS )?["\']?(?:public\.)?{table_name}["\']?\s*\((.*?)\);'
    match = re.search(pattern, schema_sql, re.DOTALL | re.IGNORECASE)
    if match:
        print(f"Found in supabase/schema.sql:")
        for line in match.group(1).strip().splitlines():
            line = line.strip()
            if line and not line.startswith('--') and not line.startswith('CONSTRAINT'):
                print("  ", line)
        found = True

    # Search in migrations
    for p in sorted(glob.glob('supabase/migrations/*.sql')):
        with open(p, 'r', encoding='utf-8') as mf:
            mt = mf.read()
        match = re.search(pattern, mt, re.DOTALL | re.IGNORECASE)
        if match:
            print(f"Found in {p}:")
            for line in match.group(1).strip().splitlines():
                line = line.strip()
                if line and not line.startswith('--') and not line.startswith('CONSTRAINT'):
                    print("  ", line)
            found = True

    if not found:
        print("Not found with CREATE TABLE, searching ADD COLUMN...")
        for p in sorted(glob.glob('supabase/migrations/*.sql')):
            with open(p, 'r', encoding='utf-8') as mf:
                mt = mf.read()
            if f'ALTER TABLE public.{table_name}' in mt:
                print(f"ALTER in {p}")

tables = [
    'patients', 'appointments', 'eye_examinations', 'dental_treatments',
    'vendors', 'inventory', 'purchase_orders', 'purchase_order_items',
    'dental_lab', 'billing', 'billing_items', 'billing_payments', 'tasks', 'staff_attendance'
]

for t in tables:
    find_table_schema(t)

