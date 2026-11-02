import re

with open('MKES_CARE_FINAL_RESET_AND_SEED.sql', 'r', encoding='utf-8') as f:
    sql = f.read()

inserts = re.findall(r'INSERT INTO\s+([a-zA-Z0-9_\.]+)\s*\((.*?)\)\s*VALUES', sql, re.DOTALL | re.IGNORECASE)

print(f"Total INSERT statements: {len(inserts)}")
for table, cols in inserts:
    col_list = [c.strip() for c in cols.replace('\n', ' ').split(',') if c.strip()]
    print(f"\nTable: {table}")
    print(f"Columns ({len(col_list)}): {', '.join(col_list)}")

