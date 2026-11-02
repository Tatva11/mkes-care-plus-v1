import re

with open('supabase/schema.sql', 'r', encoding='utf-8') as f:
    text = f.read()

# Pattern to extract CREATE TABLE statements in pg_dump format
# CREATE TABLE IF NOT EXISTS "public"."table_name" (
#     col1 type,
#     ...
# );
pattern = re.compile(r'CREATE TABLE IF NOT EXISTS "public"\."(\w+)" \((.*?)\n\);', re.DOTALL)

tables = {}
for m in pattern.finditer(text):
    tname = m.group(1)
    body = m.group(2)
    cols = []
    for line in body.splitlines():
        line = line.strip()
        if not line or line.startswith('CONSTRAINT'):
            continue
        # extract col name: "col_name" type
        cm = re.match(r'"(\w+)"\s+([^,]+)', line)
        if cm:
            cols.append((cm.group(1), cm.group(2).strip().rstrip(',')))
        else:
            cols.append((line, ''))
    tables[tname] = cols

for tname, cols in sorted(tables.items()):
    print(f'=== TABLE: {tname} ({len(cols)} cols) ===')
    for col, dtype in cols:
        print(f'  {col}: {dtype}')
