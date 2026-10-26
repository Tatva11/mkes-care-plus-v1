import asyncio
import json
import base64
import urllib.request
import websockets
import os

async def main():
    targets = json.loads(urllib.request.urlopen('http://127.0.0.1:59255/json').read().decode())
    page = next(t for t in targets if t.get('type') == 'page' and ('MKES CARE+' in t.get('title', '') or 'localhost:58150' in t.get('url', '')))
    
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

        # Wait for flutter to be ready
        for i in range(25):
            eval_res = await call('Runtime.evaluate', {'expression': 'document.querySelector("flutter-view") !== null || document.querySelector("flt-glass-pane") !== null'})
            val = eval_res.get('result', {}).get('value')
            print(f'Check {i}: {val}')
            if val is True:
                break
            await asyncio.sleep(1)
            
        await asyncio.sleep(3)
        
        # Emulate 390x844
        await call('Emulation.setDeviceMetricsOverride', {
            'width': 390,
            'height': 844,
            'deviceScaleFactor': 2.0,
            'mobile': True,
        })
        await asyncio.sleep(1)
        
        res = await call('Page.captureScreenshot', {'format': 'png'})
        img_bytes = base64.b64decode(res['result']['data'])
        out_path = r'd:\mkes-lovable\presentation_screenshots\reloaded_mobile_schedule_rendered.png'
        with open(out_path, 'wb') as f:
            f.write(img_bytes)
        print('Saved screenshot to:', out_path)

if __name__ == '__main__':
    asyncio.run(main())
