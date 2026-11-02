with open('MKES_CARE_FINAL_RESET_AND_SEED.sql', 'r', encoding='utf-8') as f:
    text = f.read()

import re
matches = re.findall(r'INSERT INTO public\.appointments[\s\S]+?;', text)
print(f"Total INSERT INTO appointments statements: {len(matches)}")
for idx, m in enumerate(matches, 1):
    print(f"Statement {idx} has {m.count('(') - 1} appointment rows")

