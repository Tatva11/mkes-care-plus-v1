import re

with open("MKES_CARE_FINAL_RESET_AND_SEED.sql", "r", encoding="utf-8") as f:
    sql = f.read()

# Find all SELECT queries
selects = re.findall(r'SELECT\s+([\s\S]+?)\s+FROM\s+([a-zA-Z0-9_\.]+)([\s\S]+?)(?:;|\bLOOP\b|\bINTO\b)', sql, re.IGNORECASE)

print(f"Total SELECT queries found: {len(selects)}")
for i, sel in enumerate(selects, 1):
    cols = " ".join(sel[0].split())
    tbl = sel[1].strip()
    rest = " ".join(sel[2].split())[:60]
    print(f"{i}. FROM {tbl} -> SELECT {cols} ({rest})")

