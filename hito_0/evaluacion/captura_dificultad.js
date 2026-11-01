// Comprueba el selector de dificultad en la interfaz real y toma una captura de la barra superior.
const { chromium } = require('playwright'); const fs = require('fs');
(async () => { const b = await chromium.launch(); const page = await b.newPage({ viewport: { width: 1400, height: 900 } });
  page.on('pageerror', e => console.log('error de página:', e.message));
  await page.route(/unpkg\.com\/(react|react-dom)@18\.3\.1\/umd\/(.*)$/, (r) => { const m = r.request().url().match(/unpkg\.com\/(react|react-dom)@18\.3\.1\/umd\/(.*)$/); r.fulfill({ contentType: 'application/javascript', body: fs.readFileSync(__dirname + '/vendor/' + m[1] + '-18.3.1/package/umd/' + m[2]) }); });
  await page.route(/fonts\.googleapis\.com/, (r) => r.fulfill({ contentType: 'text/css', body: '' }));
  await page.goto('http://127.0.0.1:8765/Hito%200%20v5%20-%20Reino%20purepecha.dc.html?dificultad=dificil');
  await page.waitForFunction(() => window.__hito0 && window.__hito0.g, null, { timeout: 30000 });
  const estado = () => page.evaluate(() => { const c = window.__hito0; return { nivel: c.g.dificultad, tesoro: Math.round(c.g.treasury), tropas: c.D.C.invasion.tropas, cronica: c.g.chron.map(e => e.text).filter(t => /Dificultad/.test(t)) }; });
  console.log('con ?dificultad=dificil:', JSON.stringify(await estado()));
  const sel = page.locator('select[title^="Dificultad"]').first();
  console.log('selector visible:', await sel.isVisible(), 'opciones:', await sel.locator('option').allTextContents());
  await sel.selectOption('facil'); await page.waitForTimeout(300);
  console.log('tras elegir Fácil al empezar:', JSON.stringify(await estado()));
  await page.screenshot({ path: (process.argv[2] || '.') + '/v5_dificultad.png', clip: { x: 0, y: 0, width: 1400, height: 120 } });
  await b.close(); })();
