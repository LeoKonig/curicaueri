const { chromium } = require('playwright'); const fs=require('fs');
(async () => { const b = await chromium.launch(); const page = await b.newPage();
  await page.route(/unpkg\.com\/(react|react-dom)@18\.3\.1\/umd\/(.*)$/, (r) => { const m = r.request().url().match(/unpkg\.com\/(react|react-dom)@18\.3\.1\/umd\/(.*)$/); r.fulfill({ contentType: 'application/javascript', body: fs.readFileSync(__dirname + '/vendor/' + m[1] + '-18.3.1/package/umd/' + m[2]) }); });
  await page.route(/fonts\.googleapis\.com/, (r) => r.fulfill({ contentType: 'text/css', body: '' }));
  await page.goto('http://127.0.0.1:8765/Hito%200%20v4%20-%20Reino%20purepecha.dc.html');
  await page.waitForFunction(() => window.__hito0 && window.__hito0.D && window.__hito0.g, null, { timeout: 30000 });
  await page.addScriptTag({ content: fs.readFileSync(__dirname + '/arnes.js', 'utf8') });
  const out = await page.evaluate(() => {
    const T = H.turno, base = T.experto;
    const envolver = (nombre, f) => { T[nombre] = f; return { nombre, turno: nombre, elegir: 'criterio' }; };
    const v = [
      { nombre: 'experto', turno: 'experto', elegir: 'criterio' },
      envolver('sin_expedicion', (c) => { const ws = c.warStrength; c.warStrength = () => 0; base(c); c.warStrength = ws; }),
      envolver('no_intercepta', (c) => { const o = c.ordenar; c.ordenar = () => {}; base(c); c.ordenar = o; }),
      envolver('rechaza_ultimatum', (c) => { const p = c.pagarUltimatum; c.pagarUltimatum = () => c.rechazarUltimatum(); base(c); c.pagarUltimatum = p; }),
      envolver('solo_expedicion', (c) => { const g = c.g; if (!g.invasor && c.warStrength() > 9000) { const def = c.D.A.find(d => d.id === 'expedicion_chichimeca'); const vv = c.actionView(def, c.alt('zacapu')); if (vv && !vv.off) vv.run(); } if (g.prisoners > 0) { const def = c.D.A.find(d => d.id === 'prisioneros_rescate'); const vv = c.actionView(def, c.alt('zacapu')); if (vv && !vv.off) vv.run(); } }),
      envolver('sin_guarnicion', (c) => { base(c); const z = c.alt('zacapu'); if (z) z.garrison = 0; }),
    ];
    const res = {};
    for (const p of v) { const L = []; for (let i = 0; i < 80; i++) { const r = H.jugar(5000 + i * 104729, p); L.push({ pts: r.puntos, caida: r.capitalCaida, tes: r.m.tes, pre: r.m.pre, exp: r.cronica.filter(l => l.includes('chichimecas (+')).length, derrotaExp: r.cronica.filter(l => /chichimecas/.test(l) && /Derrota|Empate/.test(l)).length }); } res[p.nombre] = L; }
    // probabilidades que muestra el juego para la expedición al inicio
    const c = H.fresh(5000); const odds = c.odds(c.warStrength() / c.D.C.guerra.enemigo_chichimeca);
    return { res, odds, fuerza: c.warStrength(), chichi: c.D.C.guerra.enemigo_chichimeca, alianza: c.enemigoAlianza() };
  });
  fs.writeFileSync(__dirname + '/ablacion.json', JSON.stringify(out)); await b.close();
  const st = (L, f) => (L.reduce((s, x) => s + f(x), 0) / L.length);
  for (const [k, L] of Object.entries(out.res)) console.log(k.padEnd(18), 'pts', Math.round(st(L, x => x.pts)), 'caída%', Math.round(100 * st(L, x => x.caida)), 'tes', Math.round(st(L, x => x.tes)), 'pre', st(L, x => x.pre).toFixed(1), 'expediciones', st(L, x => x.exp).toFixed(1), 'no-victorias', st(L, x => x.derrotaExp).toFixed(2));
  console.log('odds expedición al inicio:', out.odds.txt, 'fuerza', Math.round(out.fuerza), 'chichimecas', out.chichi, 'alianza', out.alianza);
})();
