const fs = require('fs');
const path = require('path');

const clientJsPath = path.resolve(__dirname, '../node_modules/whatsapp-web.js/src/Client.js');

if (!fs.existsSync(clientJsPath)) {
  process.exit(0);
}

try {
  let content = fs.readFileSync(clientJsPath, 'utf8');

  // Patch unhandled navigation execution context destruction during inject()
  const unhandledLoop = `        while (start > Date.now() - timeout) {
            res = await this.pupPage.evaluate(
                'window.Debug?.VERSION != undefined',
            );
            if (res) {
                break;
            }
            await new Promise((r) => setTimeout(r, 200));
        }`;

  const resilientLoop = `        while (start > Date.now() - timeout) {
            try {
                res = await this.pupPage.evaluate(
                    'window.Debug?.VERSION != undefined',
                );
            } catch (err) {
                res = false;
            }
            if (res) {
                break;
            }
            await new Promise((r) => setTimeout(r, 200));
        }`;

  if (content.includes(unhandledLoop)) {
    content = content.replace(unhandledLoop, resilientLoop);
    fs.writeFileSync(clientJsPath, content, 'utf8');
    console.log('[postinstall] Applied resilient navigation patch to whatsapp-web.js Client.js');
  }
} catch (e) {
  // Non-fatal
}
