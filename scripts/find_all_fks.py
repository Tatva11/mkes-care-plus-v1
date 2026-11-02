import os
import glob
import re

sql_files = glob.glob('supabase/**/*.sql', recursive=True) + glob.glob('*.sql')
print(f'Total SQL files: {len(sql_files)}')

fk_pattern = re.compile(
    r'(?:CONSTRAINT\s+([a-zA-Z0-9_]+)\s+)?FOREIGN KEY\s*\(([^)]+)\)\s*REFERENCES\s*(?:public\.)?([a-zA-Z0-9_]+)\s*\(([^)]+)\)',
    re.IGNORECASE
)
alter_fk_pattern = re.compile(
    r'ALTER TABLE\s+(?:ONLY\s+)?(?:public\.)?([a-zA-Z0-9_]+)\s+ADD CONSTRAINT\s+([a-zA-Z0-9_]+)\s+FOREIGN KEY\s*\(([^)]+)\)\s*REFERENCES\s*(?:public\.)?([a-zA-Z0-9_]+)\s*\(([^)]+)\)',
    re.IGNORECASE
)

all_fks = []

for f in sql_files:
    try:
        with open(f, 'r', encoding='utf-8', errors='ignore') as fl:
            content = fl.read()
            # ALTER TABLE FKs
            for m in alter_fk_pattern.finditer(content):
                tbl, cname, cols, rtbl, rcols = m.groups()
                all_fks.append({
                    'table': tbl.strip('\"'),
                    'constraint': cname.strip('\"'),
                    'cols': [c.strip().strip('\"') for c in cols.split(',')],
                    'ref_table': rtbl.strip('\"'),
                    'ref_cols': [c.strip().strip('\"') for c in rcols.split(',')],
                    'file': f
                })
            # Inline CREATE TABLE FKs
            for m_tbl in re.finditer(r'CREATE TABLE\s+(?:IF NOT EXISTS\s+)?(?:public\.)?([a-zA-Z0-9_]+)\s*\((.*?)\);', content, re.DOTALL | re.IGNORECASE):
                tbl_name = m_tbl.group(1).strip('\"')
                body = m_tbl.group(2)
                for m_fk in fk_pattern.finditer(body):
                    cname, cols, rtbl, rcols = m_fk.groups()
                    all_fks.append({
                        'table': tbl_name,
                        'constraint': cname.strip('\"') if cname else 'unnamed',
                        'cols': [c.strip().strip('\"') for c in cols.split(',')],
                        'ref_table': rtbl.strip('\"'),
                        'ref_cols': [c.strip().strip('\"') for c in rcols.split(',')],
                        'file': f
                    })
    except Exception as e:
        print(f'Error reading {f}: {e}')

print(f'Total FK definitions discovered: {len(all_fks)}')

by_ref = {}
for fk in all_fks:
    rt = fk['ref_table']
    by_ref.setdefault(rt, []).append(fk)

print('\n=== Tables referencing inventory ===')
for fk in by_ref.get('inventory', []):
    print(f"  {fk['table']:35} ({','.join(fk['cols'])}) via {fk['constraint']:35} in {fk['file']}")

print('\n=== Tables referencing eye_surgeries ===')
for rt in ['eye_surgeries', 'eye_surgery', 'surgeries']:
    for fk in by_ref.get(rt, []):
        print(f"  {fk['table']:35} ({','.join(fk['cols'])}) via {fk['constraint']:35} in {fk['file']}")

print('\n=== Tables referencing patients ===')
for fk in by_ref.get('patients', []):
    print(f"  {fk['table']:35} ({','.join(fk['cols'])}) via {fk['constraint']:35} in {fk['file']}")

print('\n=== Tables referencing vendors ===')
for fk in by_ref.get('vendors', []):
    print(f"  {fk['table']:35} ({','.join(fk['cols'])}) via {fk['constraint']:35} in {fk['file']}")

print('\n=== Tables referencing purchase_orders ===')
for fk in by_ref.get('purchase_orders', []):
    print(f"  {fk['table']:35} ({','.join(fk['cols'])}) via {fk['constraint']:35} in {fk['file']}")

print('\n=== Tables referencing billing ===')
for fk in by_ref.get('billing', []):
    print(f"  {fk['table']:35} ({','.join(fk['cols'])}) via {fk['constraint']:35} in {fk['file']}")

