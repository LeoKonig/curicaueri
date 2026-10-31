// Corre las estrategias y el experimento de divergencia. Uso: node correr.js
const { chromium } = require('playwright');
const fs = require('fs');

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  page.on('pageerror', e => console.error('error de página:', e.message));
  await page.route(/unpkg\.com\/(react|react-dom)@18\.3\.1\/umd\/(.*)$/, (r) => { const m = r.request().url().match(/unpkg\.com\/(react|react-dom)@18\.3\.1\/umd\/(.*)$/); r.fulfill({ contentType: 'application/javascript', body: require('fs').readFileSync(__dirname + '/vendor/' + m[1] + '-18.3.1/package/umd/' + m[2]) }); });
  await page.route(/fonts\.googleapis\.com/, (r) => r.fulfill({ contentType: 'text/css', body: '' }));
  await page.goto('http://127.0.0.1:8765/Hito%200%20v5%20-%20Reino%20purepecha.dc.html');
  await page.waitForFunction(() => window.__hito0 && window.__hito0.D && window.__hito0.g, null, { timeout: 30000 });
  await page.addScriptTag({ content: fs.readFileSync(__dirname + '/arnes.js', 'utf8') });

  const N = +(process.env.N || 60);
  const politicas = [
    { nombre: 'pasivo (nada, primera opción)', turno: 'nada', elegir: 'primera' },
    { nombre: 'pasivo (nada, última opción)', turno: 'nada', elegir: 'ultima' },
    { nombre: 'azar total', turno: 'nada', elegir: 'azar' },
    { nombre: 'codicioso (impuestos al máximo)', turno: 'codicioso', elegir: 'primera' },
    { nombre: 'constructor', turno: 'constructor', elegir: 'primera' },
    { nombre: 'militar', turno: 'militar', elegir: 'primera' },
    { nombre: 'experto', turno: 'experto', elegir: 'criterio' },
    { nombre: 'experto, eventos al azar', turno: 'experto', elegir: 'azar' },
  ];
  const res = await page.evaluate(({ politicas, N }) => {
    const out = {};
    for (const p of politicas) { out[p.nombre] = []; for (let i = 0; i < N; i++) { const r = H.jugar(1000 + i * 7919, p); delete r.cronica; out[p.nombre].push(r); } }
    return out;
  }, { politicas, N });
  fs.writeFileSync(__dirname + '/estrategias.json', JSON.stringify(res));

  // Divergencia: invertir una sola decisión de un evento y ver si cambia el final,
  // comparado con perturbar solo el azar (sin cambiar la decisión).
  const div = await page.evaluate(({ N }) => {
    const pol = { nombre: 'experto', turno: 'experto', elegir: 'criterio' }, filas = [];
    for (let s = 0; s < Math.min(N, 30); s++) {
      const seed = 1000 + s * 7919, b = H.jugar(seed, pol);
      for (const e of b.elecciones) {
        const alt = e.opciones.map((o, i) => o.ok && i !== e.elegida ? i : -1).filter(i => i >= 0);
        const ruido = H.jugar(seed, pol, { i: e.n, perturbar: true });
        for (const j of alt) { const r = H.jugar(seed, pol, { i: e.n, opcion: j });
          filas.push({ seed, n: e.n, anio: 1475 + Math.floor(e.t / 18), titulo: e.titulo, de: e.opciones[e.elegida].id, a: e.opciones[j].id,
            dPuntos: r.puntos - b.puntos, dRuido: ruido.puntos - b.puntos,
            dm: Object.fromEntries(Object.keys(b.m).map(k => [k, Math.round((r.m[k] - b.m[k]) * 10) / 10])),
            caidaCambia: r.capitalCaida !== b.capitalCaida }); }
      }
    }
    return filas;
  }, { N });
  fs.writeFileSync(__dirname + '/divergencia.json', JSON.stringify(div));

  // Una crónica completa de muestra por estrategia.
  const cron = await page.evaluate(() => ({ experto: H.jugar(1000, { nombre: 'experto', turno: 'experto', elegir: 'criterio' }), pasivo: H.jugar(1000, { nombre: 'pasivo', turno: 'nada', elegir: 'primera' }) }));
  fs.writeFileSync(__dirname + '/cronicas.json', JSON.stringify(cron));
  await browser.close();
  console.log('listo', Object.keys(res).length, 'estrategias,', div.length, 'filas de divergencia');
})();
