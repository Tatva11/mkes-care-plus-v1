with open('MKES_CARE_FINAL_RESET_AND_SEED.sql', 'r', encoding='utf-8') as f:
    text = f.read()

import re
matches = re.findall(r'INSERT INTO public\.appointments[\s\S]+?;', text)
for idx, m in enumerate(matches, 1):
    dates = set(re.findall(r'CURRENT_DATE[^\,]*', m))
    print(f"Statement {idx} dates:", dates)

