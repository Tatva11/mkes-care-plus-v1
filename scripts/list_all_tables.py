import glob, re, os

sql_files = glob.glob('supabase/**/*.sql', recursive=True) + glob.glob('*.sql')
tables = set()
for f in sql_files:
    with open(f, 'r', encoding='utf-8', errors='ignore') as fl:
        matches = re.findall(r'CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:["\']?public["\']?\.)?["\']?([a-zA-Z0-9_]+)["\']?', fl.read(), re.IGNORECASE)
        for m in matches:
            tables.add(m.strip('\"'))

print(f"Total tables found: {len(tables)}")
for t in sorted(tables):
    print(" ", t)

