import asyncio
import json
import websockets
import urllib.request

async def run():
    targets = json.loads(urllib.request.urlopen('http://127.0.0.1:59255/json').read().decode())
    page = next(t for t in targets if 'localhost:58150' in t.get('url', ''))
    async with websockets.connect(page['webSocketDebuggerUrl']) as ws:
        msg_id = 1
        async def call(method, params=None):
            nonlocal msg_id
            curr_id = msg_id
            msg_id += 1
            payload = {'id': curr_id, 'method': method}
            if params:
                payload['params'] = params
            await ws.send(json.dumps(payload))
            while True:
                resp = json.loads(await ws.recv())
                if resp.get('id') == curr_id:
                    return resp

        res = await call('Runtime.evaluate', {
            'expression': 'localStorage.getItem("sb-mfalgfodhsszyxnfiofi-auth-token")',
            'returnByValue': True
        })
        auth_data = json.loads(res['result']['result']['value'])
        token = auth_data['access_token']
        user_id = auth_data['user']['id']
        print('User ID:', user_id)
        
        headers = {
            'apikey': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1mYWxnZm9kaHNzenl4bmZpb2ZpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY3MDYwMzAsImV4cCI6MjEwMjI4MjAzMH0.RlnskZQMbtjG6vBEKbleVluAbsBtoM3kNXSzYgk-P7I',
            'Authorization': f'Bearer {token}'
        }
        
        # 1. Query shift_configurations
        req = urllib.request.Request('https://mfalgfodhsszyxnfiofi.supabase.co/rest/v1/shift_configurations?select=*', headers=headers)
        with urllib.request.urlopen(req) as resp:
            print('shift_configurations:', json.dumps(json.loads(resp.read().decode()), indent=2))
            
        # 2. Query user profile
        req = urllib.request.Request(f'https://mfalgfodhsszyxnfiofi.supabase.co/rest/v1/profiles?select=*&id=eq.{user_id}', headers=headers)
        with urllib.request.urlopen(req) as resp:
            print('profile:', json.dumps(json.loads(resp.read().decode()), indent=2))

        # 3. Query staff_attendance
        req = urllib.request.Request(f'https://mfalgfodhsszyxnfiofi.supabase.co/rest/v1/staff_attendance?select=*&order=record_date.desc&limit=5', headers=headers)
        with urllib.request.urlopen(req) as resp:
            print('attendance records:', json.dumps(json.loads(resp.read().decode()), indent=2))

if __name__ == '__main__':
    asyncio.run(run())
