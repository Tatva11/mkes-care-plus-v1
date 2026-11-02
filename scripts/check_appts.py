with open('MKES_CARE_FINAL_RESET_AND_SEED.sql', 'r', encoding='utf-8') as f:
    text = f.read()

import re
m = re.search(r'INSERT INTO public\.appointments[\s\S]+?;', text)
if m:
    lines = m.group(0).split('\n')
    for l in lines:
        if 'CURRENT_DATE' in l:
            print(l.strip()[:100])

