// Comprueba los textos: claves malformadas y marcadores que no se resuelven.
const { chromium } = require('playwright'); const fs = require('fs');
(async () => { const b = await chromium.launch(); const page = await b.newPage();
  await page.route(/unpkg\.com\/(react|react-dom)@18\.3\.1\/umd\/(.*)$/, (r) => { const m = r.request().url().match(/unpkg\.com\/(react|react-dom)@18\.3\.1\/umd\/(.*)$/); r.fulfill({ contentType: 'application/javascript', body: fs.readFileSync(__dirname + '/vendor/' + m[1] + '-18.3.1/package/umd/' + m[2]) }); });
  await page.route(/fonts\.googleapis\.com/, (r) => r.fulfill({ contentType: 'text/css', body: '' }));
  await page.goto('http://127.0.0.1:8765/Hito%200%20v5%20-%20Reino%20purepecha.dc.html');
  await page.waitForFunction(() => window.__hito0 && window.__hito0.D && window.__hito0.g, null, { timeout: 30000 });
  const r = await page.evaluate(() => { const x = window.__hito0.checkI18n(); return { ok: x.ok, malformadas: x.malformadas, sinVars: x.sinVars.filter(s => !/^(a|t|alt|alts)\./.test(s.ph) && !['a.nombre','alt','edificio','ganador','perdedor','personaje','anio','tesoro','prestigio','hexes','n','monto','botin','prisioneros','invasores','bajas','decision','opcion','items','veintenas','probabilidad','fuerza','enemigo','ratio','lealtad','agravio','mantenimiento'].includes(s.ph)) }; });
  console.log(JSON.stringify(r, null, 1)); await b.close(); })();
