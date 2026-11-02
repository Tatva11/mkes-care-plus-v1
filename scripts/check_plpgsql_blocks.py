import re

with open('scripts/clean_and_seed_demo_data.sql', 'r', encoding='utf-8') as f:
    sql = f.read()

# Find all DO $$ blocks
do_blocks = re.findall(r'DO\s+\$\$([\s\S]+?)\$\$;', sql)
print(f"Total DO blocks: {len(do_blocks)}")

for i, block in enumerate(do_blocks, 1):
    print(f"\n--- Checking DO block {i} ---")
    # Check for undeclared variables or wrong aliases like p.id
    # Look for patterns like \b[a-z]\.[a-z]
    bad_aliases = re.findall(r'\b([a-z]{1,3})\.([a-z_]+)\b', block)
    for alias, col in bad_aliases:
        if alias not in ['public', 'auth', 'now', 'v_rec', 'item', 'row', 'rec']:
            print(f"  POTENTIAL ALIAS BUG in block {i}: {alias}.{col}")

    # Check DECLARE block
    m_decl = re.search(r'DECLARE([\s\S]+?)BEGIN', block, re.IGNORECASE)
    declared_vars = []
    if m_decl:
        for line in m_decl.group(1).split('\n'):
            line = line.strip().rstrip(';')
            if line and not line.startswith('--'):
                var_name = line.split()[0]
                declared_vars.append(var_name)
        print(f"  Declared variables in block {i}: {declared_vars}")

