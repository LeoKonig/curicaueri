// Calibra los niveles de dificultad: juega cada nivel con varias estrategias y mide triunfo y caída.
// Uso: node calibrar_dificultad.js [candidatos.json]
//   Sin argumento, usa los niveles de datos/constantes.json. Con un JSON {nivel: {ruta: valor}},
//   prueba esos valores sin tocar los archivos.
// Metas: el experto logra el triunfo ≈ 95 % en fácil, ≈ 70 % en normal y ≈ 40 % en difícil, y en
// difícil una regla fija ("siempre la primera opción") casi nunca triunfa.
const { chromium } = require('playwright'); const fs = require('fs');
(async () => {
  const b = await chromium.launch(); const page = await b.newPage();
  page.on('pageerror', e => console.error('error de página:', e.message));
  await page.route(/unpkg\.com\/(react|react-dom)@18\.3\.1\/umd\/(.*)$/, (r) => { const m = r.request().url().match(/unpkg\.com\/(react|react-dom)@18\.3\.1\/umd\/(.*)$/); r.fulfill({ contentType: 'application/javascript', body: fs.readFileSync(__dirname + '/vendor/' + m[1] + '-18.3.1/package/umd/' + m[2]) }); });
  await page.route(/fonts\.googleapis\.com/, (r) => r.fulfill({ contentType: 'text/css', body: '' }));
  await page.goto('http://127.0.0.1:8765/Hito%200%20v5%20-%20Reino%20purepecha.dc.html');
  await page.waitForFunction(() => window.__hito0 && window.__hito0.D && window.__hito0.D.C0, null, { timeout: 30000 });
  await page.addScriptTag({ content: fs.readFileSync(__dirname + '/arnes.js', 'utf8') });
  const candidatos = process.argv[2] ? JSON.parse(fs.readFileSync(process.argv[2], 'utf8')) : null;
  const N = +(process.env.N || 60);
  const res = await page.evaluate(({ candidatos, N }) => {
    const D = window.__hito0.D.C0.dificultades;
    if (candidatos) for (const k in candidatos) D[k] = candidatos[k];
    const niveles = Object.keys(D).filter(k => k[0] !== '_');
    const pols = [['experto', 'experto', 'criterio'], ['constructor', 'constructor', 'primera'], ['militar', 'militar', 'primera'], ['primera opción', 'nada', 'primera'], ['azar', 'nada', 'azar']];
    const out = {};
    for (const nv of niveles) { out[nv] = {};
      for (const [nom, turno, elegir] of pols) { let tri = 0, caida = 0, metas = 0;
        for (let i = 0; i < N; i++) { const r = H.jugar(1000 + i * 7919, { nombre: nom, turno, elegir, dificultad: nv }); tri += r.veredicto === 'triunfo'; caida += r.capitalCaida; metas += r.metas; }
        out[nv][nom] = { triunfo: Math.round(100 * tri / N), caida: Math.round(100 * caida / N), metas: +(metas / N).toFixed(2) }; } }
    return out;
  }, { candidatos, N });
  for (const [nv, filas] of Object.entries(res)) {
    console.log('\n' + nv);
    for (const [nom, x] of Object.entries(filas)) console.log('  ' + nom.padEnd(16), 'triunfo', String(x.triunfo).padStart(3) + '%', ' caída', String(x.caida).padStart(3) + '%', ' metas', x.metas);
  }
  fs.writeFileSync(__dirname + '/calibracion.json', JSON.stringify(res, null, 1));
  await b.close();
})();
