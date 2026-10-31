// Capturas de la interfaz real: el modal de invasión y la pantalla final.
const { chromium } = require('playwright'); const fs = require('fs');
(async () => { const b = await chromium.launch(); const page = await b.newPage({ viewport: { width: 1400, height: 900 } });
  page.on('pageerror', e => console.log('error de página:', e.message));
  await page.route(/unpkg\.com\/(react|react-dom)@18\.3\.1\/umd\/(.*)$/, (r) => { const m = r.request().url().match(/unpkg\.com\/(react|react-dom)@18\.3\.1\/umd\/(.*)$/); r.fulfill({ contentType: 'application/javascript', body: fs.readFileSync(__dirname + '/vendor/' + m[1] + '-18.3.1/package/umd/' + m[2]) }); });
  await page.route(/fonts\.googleapis\.com/, (r) => r.fulfill({ contentType: 'text/css', body: '' }));
  await page.goto('http://127.0.0.1:8765/Hito%200%20v5%20-%20Reino%20purepecha.dc.html');
  await page.waitForFunction(() => window.__hito0 && window.__hito0.D && window.__hito0.g, null, { timeout: 30000 });
  const dir = process.argv[2] || '.';
  // Avanza eligiendo la primera opción hasta que aparezca el modal de invasión.
  const hasta = async (pred) => page.evaluate((src) => { const c = window.__hito0, g = c.g, p = new Function('g', 'return ' + src); let n = 0;
    while (!g.ended && n < 4000) { if (g.modal) { if (p(g)) break; const i = g.modal.options.findIndex(o => o.ok); c.pick(i < 0 ? 0 : i); } else c.step(); n++; } c.forceUpdate(); return g.modal ? g.modal.title : (g.ended ? 'fin' : '?'); }, pred);
  console.log('modal:', await hasta("g.modal.def.id === 'invasion'")); await page.waitForTimeout(500);
  await page.screenshot({ path: dir + '/v5_invasion.png' });
  console.log('fin:', await hasta('false')); await page.waitForTimeout(500);
  await page.screenshot({ path: dir + '/v5_fin.png' });
  await b.close(); })();
