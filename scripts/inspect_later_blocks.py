with open('scripts/clean_and_seed_demo_data.sql', 'r', encoding='utf-8') as f:
    sql = f.read()

import re
blocks = re.findall(r'DO\s+\$\$([\s\S]+?)\$\$;', sql)

for idx in [5, 6, 7, 8, 9, 10, 11]: # 0-indexed for blocks 6 to 12
    print(f"\n==================== BLOCK {idx+1} ====================")
    print(blocks[idx].strip()[:600])

