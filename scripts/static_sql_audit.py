import re

with open('MKES_CARE_FINAL_RESET_AND_SEED.sql', 'r', encoding='utf-8') as f:
    sql = f.read()

print("=" * 60)
print("STATIC SQL AUDIT: MKES_CARE_FINAL_RESET_AND_SEED.sql")
print("=" * 60)

# 1. Check DO / END blocks
do_blocks = len(re.findall(r'\bDO\s+\$\$', sql))
end_blocks = len(re.findall(r'\bEND\s+\$\$;', sql))
print(f"1. Anonymous DO blocks: {do_blocks} open, {end_blocks} closed.")
assert do_blocks == end_blocks, "Mismatched DO/END blocks"

# 2. Check CREATE TABLE statements
create_tables = re.findall(r'CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?([a-zA-Z0-9_\.]+)', sql, re.IGNORECASE)
print(f"2. Permanent CREATE TABLE statements ({len(create_tables)}): {create_tables}")

# 3. Check for any table named v_staff_id
v_staff_table = re.findall(r'CREATE\s+TABLE\s+[^;]*v_staff_id', sql, re.IGNORECASE)
print(f"3. Occurrences of CREATE TABLE v_staff_id: {len(v_staff_table)}")

# 4. Check all DROP statements
drops = re.findall(r'DROP\s+([A-Z\s]+)(?:IF\s+EXISTS\s+)?([a-zA-Z0-9_\.]+)', sql, re.IGNORECASE)
print(f"4. DROP statements ({len(drops)}):")
for kind, name in drops:
    print(f"   - DROP {kind.strip()} {name.strip()}")

# 5. Check all DELETE statements
deletes = re.findall(r'DELETE\s+FROM\s+([a-zA-Z0-9_\.]+)', sql, re.IGNORECASE)
print(f"5. DELETE statements ({len(deletes)}): {deletes}")

# 6. Check all TRIGGER modifications
triggers = re.findall(r'(?:DISABLE|ENABLE)\s+TRIGGER\s+[a-zA-Z0-9_\.]+', sql, re.IGNORECASE)
print(f"6. Trigger enable/disable occurrences: {len(triggers)}")

# 7. Check all RLS policies
policies = re.findall(r'CREATE\s+POLICY\s+"([^"]+)"\s+ON\s+([a-zA-Z0-9_\.]+)', sql, re.IGNORECASE)
print(f"7. Policies created ({len(policies)}):")
for p_name, t_name in policies:
    print(f"   - Policy \"{p_name}\" on {t_name}")

# 8. Check for unrestricted policies (USING (true) WITH CHECK (true))
unrestricted = re.findall(r'CREATE\s+POLICY\s+"([^"]+)"[^;]+USING\s*\(\s*true\s*\)\s*WITH\s+CHECK\s*\(\s*true\s*\)', sql, re.IGNORECASE)
print(f"8. Unrestricted policies (USING true WITH CHECK true): {unrestricted}")

print("=" * 60)

