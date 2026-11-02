import urllib.request
import json

env = {}
with open('api.env', 'r', encoding='utf-8') as f:
    for line in f:
        line = line.strip()
        if line and '=' in line and not line.startswith('#'):
            k, v = line.split('=', 1)
            env[k.strip()] = v.strip().strip('"').strip("'")

url = env.get('SUPABASE_URL')
key = env.get('SUPABASE_ANON_KEY')

def fetch_table(table_name, select="*"):
    req = urllib.request.Request(
        f"{url}/rest/v1/{table_name}?select={select}",
        headers={
            'apikey': key,
            'Authorization': f"Bearer {key}"
        }
    )
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read().decode())
    except Exception as e:
        return f"Error: {e}"

print("=== PROFILES ===")
profiles = fetch_table("profiles", "id,full_name,email,role,is_active")
if isinstance(profiles, list):
    for p in profiles:
        print(p)
else:
    print(profiles)

print("\n=== DEPARTMENTS ===")
depts = fetch_table("departments", "id,name,is_active")
if isinstance(depts, list):
    for d in depts:
        print(d)
else:
    print(depts)

print("\n=== DEPARTMENT DOCTORS ===")
dd = fetch_table("department_doctors")
if isinstance(dd, list):
    for d in dd:
        print(d)
else:
    print(dd)

