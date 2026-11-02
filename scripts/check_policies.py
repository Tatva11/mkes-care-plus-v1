with open('supabase/schema.sql', 'r', encoding='utf-8') as f:
    text = f.read()

import re
matches = re.findall(r'CREATE POLICY\s+.*?\s+ON\s+"public"\."appointments"\s+.*?;', text, re.DOTALL)
print(f'Found {len(matches)} policies on appointments:')
for m in matches:
    print(m)
    print('-'*50)

