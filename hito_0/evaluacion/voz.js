// Partida "en voz alta": avanza hasta la siguiente situación cuya postura aún no se fijó y la muestra
// como la ve el jugador. Uso: node voz.js <semilla> <perfil> '<json de posturas>'
//   posturas: { "Título del evento": "id_opcion", ... }  (se reutilizan cada vez que el evento vuelve)
//   perfil: prudente | agresivo | novato  (decide la revisión anual: impuestos, obras, ultimátum, expediciones)
const { chromium } = require('playwright'); const fs = require('fs');
const [seed, perfil, posturasTxt] = [+process.argv[2], process.argv[3], process.argv[4] || '{}'];
(async () => {
  const b = await chromium.launch(); const page = await b.newPage();
  await page.route(/unpkg\.com\/(react|react-dom)@18\.3\.1\/umd\/(.*)$/, (r) => { const m = r.request().url().match(/unpkg\.com\/(react|react-dom)@18\.3\.1\/umd\/(.*)$/); r.fulfill({ contentType: 'application/javascript', body: fs.readFileSync(__dirname + '/vendor/' + m[1] + '-18.3.1/package/umd/' + m[2]) }); });
  await page.route(/fonts\.googleapis\.com/, (r) => r.fulfill({ contentType: 'text/css', body: '' }));
  await page.goto('http://127.0.0.1:8765/Hito%200%20v5%20-%20Reino%20purepecha.dc.html');
  await page.waitForFunction(() => window.__hito0 && window.__hito0.D && window.__hito0.g, null, { timeout: 30000 });
  await page.addScriptTag({ content: fs.readFileSync(__dirname + '/arnes.js', 'utf8') });
  const out = await page.evaluate(({ seed, perfil, posturas }) => {
    const c = H.fresh(seed), g = c.g;
    const act = (id, alt) => { const def = c.D.A.find(d => d.id === id); const v = c.actionView(def, c.alt(alt || 'zacapu')); if (v && !v.off) { v.run(); return true; } return false; };
    // Revisión anual de cada perfil (lo que una persona haría una vez al año, no cada veintena).
    const revisar = {
      prudente: () => { H.tasa(c, 'tributo', 3); H.tasa(c, 'impuesto', 3); if (g.prisoners > 0) act('prisioneros_rescate');
        for (const [a, k] of [['zacapu', 'yacata'], ['zacapu', 'troje'], ['uruapan', 'troje'], ['tzintzuntzan', 'troje']]) if (g.treasury > c.D.C.construccion.costo[k] + 200 && act('construir_' + k, a)) break; },
      agresivo: () => { H.tasa(c, 'tributo', 4); H.tasa(c, 'impuesto', 4); if (g.treasury > 600) act('reclutar'); act('expedicion_chichimeca'); if (g.prisoners > 0) act('prisioneros_ritual'); if (g.treasury > 500) act('construir_fortaleza', 'zacapu'); },
      novato: () => { if (g.treasury > 450) act('construir_yacata', 'tzintzuntzan'); },
    }[perfil];
    let k = 0, ultimoAnio = -1; const diario = [];
    while (!g.ended && k < 3000) {
      if (g.modal) {
        const M = g.modal, t = M.title, elegido = posturas[t];
        const idx = M.options.findIndex(o => o.o.id === elegido && o.ok);
        if (elegido === undefined || idx < 0) {
          return { pendiente: true, anio: g.year, veintena: g.v, titulo: t, cuerpo: M.cuerpo, desc: M.desc,
            opciones: M.options.map(o => ({ id: o.o.id, titulo: o.title, costo: o.cost, disponible: o.ok, por_que_no: o.why })),
            estado: { tesoro: Math.round(g.treasury), prestigio: g.prestige, ejercito: g.army, moral: g.morale, tasas: g.taxes, ingresoNeto: Math.round(c.totalIncome() - c.totalExpenses()),
              altepetl: g.alts.map(a => ({ n: a.name, pob: a.pop, lealtad: Math.round(a.loyalty), agravio: Math.round(a.agravio), indep: a.independent, gob: g.chars[a.governor] && g.chars[a.governor].name })) },
            diario };
        }
        diario.push(g.year + '·V' + g.v + ' ' + t + ' → ' + elegido); c.pick(idx);
      } else { if (g.year !== ultimoAnio) { revisar(); ultimoAnio = g.year; } c.step(); }
      k++;
    }
    c.resolveLog(true);
    return { pendiente: false, puntos: H.puntuar(c), capitalCaida: !!g.capitalCaida, m: c.metrics(), decisiones: g.log.length, deRumbo: g.log.filter(e => e.changing).length, diario,
      cronica: g.chron.filter(e => !/Frontera:/.test(e.text)).map(e => e.year + '·V' + e.v + ' ' + e.text) };
  }, { seed, perfil, posturas: JSON.parse(posturasTxt) });
  console.log(JSON.stringify(out, null, 1)); await b.close();
})();
