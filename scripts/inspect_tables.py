import os
import re

with open('supabase/schema.sql', 'r', encoding='utf-8') as f:
    text = f.read()

for t in ['dental_lab', 'vendors', 'purchase_orders', 'inventory', 'tasks', 'staff_attendance', 'appointments', 'billing']:
    # look for table definition
    idx = text.find(f'"{t}"')
    if idx != -1:
        # find the preceding CREATE TABLE
        start = text.rfind('CREATE TABLE', 0, idx)
        end = text.find(';', idx)
        if start != -1 and end != -1:
            print(f"=== {t} from schema.sql ===")
            print(text[start:end+1])
            print()

# Check migrations for purchase_orders
mig_dir = 'supabase/migrations'
for f in os.listdir(mig_dir):
    if 'purchase_order' in f or 'vendor' in f or 'dental_lab' in f:
        with open(os.path.join(mig_dir, f), 'r', encoding='utf-8') as mf:
            mtxt = mf.read()
            for m in re.finditer(r'CREATE TABLE IF NOT EXISTS [^\(]+\((.*?)\);', mtxt, re.DOTALL | re.IGNORECASE):
                print(f"=== from migration {f} ===")
                print(m.group(0)[:500])
                print()

