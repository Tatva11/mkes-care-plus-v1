import os
import glob
import re

sql_files = glob.glob('supabase/**/*.sql', recursive=True) + glob.glob('*.sql')

all_fks = []

for f in sorted(sql_files):
    with open(f, 'r', encoding='utf-8', errors='ignore') as fl:
        text = fl.read()

        # 1. Table-level: [CONSTRAINT name] FOREIGN KEY (cols) REFERENCES rtbl(rcols) [ON DELETE action]
        t_pattern = re.compile(
            r'(?:CONSTRAINT\s+["\']?([a-zA-Z0-9_]+)["\']?\s+)?FOREIGN KEY\s*\(([^)]+)\)\s*REFERENCES\s*(?:["\']?public["\']?\.)?["\']?([a-zA-Z0-9_]+)["\']?\s*(?:\(([^)]+)\))?(?:\s+ON\s+DELETE\s+([A-Z\s]+))?',
            re.IGNORECASE | re.DOTALL
        )
        for m in t_pattern.finditer(text):
            cname, col, rtbl, rcol, on_del = m.groups()
            idx = m.start()
            t_chunk = text[:idx]
            m_tbl = list(re.finditer(r'(?:CREATE\s+TABLE|ALTER\s+TABLE(?:\s+ONLY)?)\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:["\']?public["\']?\.)?["\']?([a-zA-Z0-9_]+)["\']?', t_chunk, re.IGNORECASE))
            tbl_name = m_tbl[-1].group(1) if m_tbl else 'unknown'
            all_fks.append({
                'source_table': tbl_name.strip('\"'),
                'source_cols': [c.strip().strip('\"') for c in col.split(',')],
                'ref_table': rtbl.strip('\"'),
                'ref_cols': [c.strip().strip('\"') for c in (rcol or 'id').split(',')],
                'constraint': cname.strip('\"') if cname else 'unnamed',
                'on_delete': on_del.strip() if on_del else 'NO ACTION',
                'file': f,
                'type': 'table-level'
            })

        # 2. Column-level: col_name type ... REFERENCES rtbl(rcol) [ON DELETE action]
        c_pattern = re.compile(
            r'([a-zA-Z0-9_]+)\s+[^,\n]+?\s+REFERENCES\s+(?:["\']?public["\']?\.)?["\']?([a-zA-Z0-9_]+)["\']?\s*(?:\(([^)]+)\))?(?:\s+ON\s+DELETE\s+([A-Z\s]+))?',
            re.IGNORECASE
        )
        for m in c_pattern.finditer(text):
            col, rtbl, rcol, on_del = m.groups()
            line_start = text.rfind('\n', 0, m.start())
            line = text[line_start:m.end()]
            if 'FOREIGN KEY' in line.upper():
                continue
            idx = m.start()
            t_chunk = text[:idx]
            m_tbl = list(re.finditer(r'(?:CREATE\s+TABLE|ALTER\s+TABLE(?:\s+ONLY)?)\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:["\']?public["\']?\.)?["\']?([a-zA-Z0-9_]+)["\']?', t_chunk, re.IGNORECASE))
            tbl_name = m_tbl[-1].group(1) if m_tbl else 'unknown'
            all_fks.append({
                'source_table': tbl_name.strip('\"'),
                'source_cols': [col.strip().strip('\"')],
                'ref_table': rtbl.strip('\"'),
                'ref_cols': [c.strip().strip('\"') for c in (rcol or 'id').split(',')],
                'constraint': 'column-level',
                'on_delete': on_del.strip() if on_del else 'NO ACTION',
                'file': f,
                'type': 'column-level'
            })

print(f"Total FK references captured: {len(all_fks)}")

unique_fks = {}
for fk in all_fks:
    key = (fk['source_table'], tuple(fk['source_cols']), fk['ref_table'])
    if key not in unique_fks:
        unique_fks[key] = fk
    else:
        if fk['on_delete'] != 'NO ACTION':
            unique_fks[key]['on_delete'] = fk['on_delete']

print(f"Unique FK relationships: {len(unique_fks)}")

by_ref = {}
for key, fk in unique_fks.items():
    rt = fk['ref_table']
    by_ref.setdefault(rt, []).append(fk)

for rt in sorted(by_ref.keys()):
    print(f"\nTarget Table: [{rt}] (referenced by {len(by_ref[rt])} tables)")
    for fk in sorted(by_ref[rt], key=lambda x: x['source_table']):
        print(f"  <- {fk['source_table']:32} ({','.join(fk['source_cols'])}) [ON DELETE {fk['on_delete']:10}] (in {os.path.basename(fk['file'])})")
