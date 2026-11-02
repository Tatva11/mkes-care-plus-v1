import glob, re

def find_create_table(tbl_name):
    for f in glob.glob('**/*.sql', recursive=True):
        if 'clean_and_seed' in f or 'MKES_CARE' in f: continue
        with open(f, 'r', encoding='utf-8', errors='ignore') as fp:
            c = fp.read()
        pattern = r'CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:public\.)?' + tbl_name + r'\b\s*\(([\s\S]+?)\);'
        for m in re.finditer(pattern, c, re.IGNORECASE):
            body = m.group(1)
            # check if body starts with column definitions
            first_word = body.strip().split()[0].lower()
            if first_word in ['id', 'patient_id', 'user_id', 'created_at', 'order_number', 'patient_number', 'invoice_number']:
                print(f"=== FOUND {tbl_name} in {f} ===")
                for line in body.split('\n')[:25]:
                    if line.strip() and not line.strip().startswith('--'):
                        print(" ", line.strip())
                return

for t in ['patients', 'appointments', 'billing', 'purchase_orders', 'purchase_order_items', 'inventory']:
    find_create_table(t)

