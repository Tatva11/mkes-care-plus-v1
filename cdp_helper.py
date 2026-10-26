import asyncio
import json
import base64
import urllib.request
import websockets
import os

async def get_page_ws():
    targets = json.loads(urllib.request.urlopen('http://127.0.0.1:59255/json').read().decode())
    for t in targets:
        if t.get('type') == 'page' and ('MKES CARE+' in t.get('title', '') or 'localhost:58150' in t.get('url', '')):
            return t['webSocketDebuggerUrl']
    raise Exception('No matching page target found')

async def capture_screenshot(out_path, width=390, height=844, device_scale=2.0):
    ws_url = await get_page_ws()
    async with websockets.connect(ws_url) as ws:
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

        # Set device metrics
        await call('Emulation.setDeviceMetricsOverride', {
            'width': width,
            'height': height,
            'deviceScaleFactor': device_scale,
            'mobile': True,
        })
        
        await asyncio.sleep(0.5)
        
        # Capture screenshot
        res = await call('Page.captureScreenshot', {'format': 'png'})
        img_b64 = res['result']['data']
        img_bytes = base64.b64decode(img_b64)
        
        os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
        with open(out_path, 'wb') as f:
            f.write(img_bytes)
        print(f'Screenshot saved to {out_path} ({len(img_bytes)} bytes)')

if __name__ == '__main__':
    asyncio.run(capture_screenshot(r'd:\mkes-lovable\presentation_screenshots\current_live_state.png'))
