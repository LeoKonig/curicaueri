// Sonda rápida: una partida por estrategia, con errores y consola visibles.
const { chromium } = require('playwright'); const fs = require('fs');
(async () => { const b = await chromium.launch(); const page = await b.newPage();
  page.on('console', m => { if (/warn|error/.test(m.type())) console.log('consola:', m.text().slice(0, 200)); });
  page.on('pageerror', e => console.log('error de página:', e.message));
  await page.route(/unpkg\.com\/(react|react-dom)@18\.3\.1\/umd\/(.*)$/, (r) => { const m = r.request().url().match(/unpkg\.com\/(react|react-dom)@18\.3\.1\/umd\/(.*)$/); r.fulfill({ contentType: 'application/javascript', body: fs.readFileSync(__dirname + '/vendor/' + m[1] + '-18.3.1/package/umd/' + m[2]) }); });
  await page.route(/fonts\.googleapis\.com/, (r) => r.fulfill({ contentType: 'text/css', body: '' }));
  await page.goto('http://127.0.0.1:8765/Hito%200%20v5%20-%20Reino%20purepecha.dc.html');
  await page.waitForFunction(() => window.__hito0 && window.__hito0.D && window.__hito0.g, null, { timeout: 30000 });
  await page.addScriptTag({ content: fs.readFileSync(__dirname + '/arnes.js', 'utf8') });
  console.log(await page.evaluate(() => { const out = []; for (const t of Object.keys(H.turno)) { try { const r = H.jugar(1001, { nombre: t, turno: t, elegir: t === 'experto' ? 'criterio' : 'primera' }); out.push(t + ' pts ' + r.puntos + ' fin ' + r.fin + ' ver ' + r.veredicto + ' eventos ' + r.eventos + ' ' + r.clase.slice(0, 60)); } catch (e) { out.push(t + ' ERR ' + String(e.stack).split('\n').slice(0, 3).join(' | ')); } } return out.join('\n'); }));
  await b.close(); })();
