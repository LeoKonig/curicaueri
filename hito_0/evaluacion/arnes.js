// Arnés para juzgar el prototipo del hito 0 jugando partidas completas desde la página.
// Se inyecta después de que el prototipo cargó sus datos (window.__hito0.D existe).
(() => {
  // El prototipo usa una función global `f` que no define (gvar, 'enemigo_alianza'): sin esto, la crisis de guerra truena.
  if (!window.f) window.f = (n) => Math.round(n).toLocaleString('es-MX');
  const base = window.__hito0, Cls = base.constructor;

  // Generador propio para las políticas (el juego usa su propia semilla).
  const mulberry = (s) => () => { s |= 0; s = s + 0x6D2B79F5 | 0; let t = Math.imul(s ^ s >>> 15, 1 | s); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; };

  const fresh = (seed) => {
    const c = new Cls(base.props);
    c.D = base.D; c.T = base.T;
    c.state = { err: '', sel: 'zacapu', selSet: 'Zacapu', tab: 'resumen', layer: 'influencia', left: 'tributo', chron: false };
    c.forceUpdate = () => {}; c.setState = () => {};
    c.newGame(); c.g.seed = seed | 1; c.g.seed0 = seed | 1;
    return c;
  };

  const okIdx = (c) => c.g.modal.options.map((o, i) => o.ok ? i : -1).filter(i => i >= 0);
  const accion = (c, id, altId) => {
    const def = c.D.A.find(d => d.id === id); if (!def) return false;
    const v = c.actionView(def, altId ? c.alt(altId) : c.alt('zacapu'));
    if (!v || v.off) return false; v.run(); return true;
  };
  const cuesta = (c, k) => c.D.C.construccion.costo[k];

  // --- cómo elegir en un evento o crisis
  const elegir = {
    primera: (c) => okIdx(c)[0],
    ultima: (c) => { const o = okIdx(c); return o[o.length - 1]; },
    azar: (c, rnd) => { const o = okIdx(c); return o[Math.floor(rnd() * o.length)]; },
    // La heurística del propio arnés del prototipo, ampliada con sentido común.
    criterio: (c) => { const g = c.g, o = okIdx(c), ti = g.modal.title || '', ids = g.modal.options.map(x => x.o.id);
      const por = (id) => { const i = ids.indexOf(id); return o.includes(i) ? i : null; };
      if (ti.includes('Guerra')) return c.warStrength() / 6000 >= 0.9 ? o[0] : o[o.length - 1];
      if (ti.includes('Excedente')) return g.treasury < 400 ? o[Math.min(2, o.length - 1)] : o[0];
      if (ti.includes('cosecha')) return g.treasury < 150 ? o[o.length - 1] : o[0];
      if (ti.includes('Rebelión')) return c.field() >= 1500 ? o[0] : o[o.length - 1];
      if (por('rebajar') != null && g.treasury > 500) return por('rebajar');
      if (por('acoger') != null) return por('acoger');
      if (por('tangaxoan') != null) return por('tangaxoan');
      return o[0]; },
  };

  // --- qué hace el jugador entre eventos (se llama una vez por veintena)
  const turno = {
    nada: () => {},
    codicioso: (c) => { const g = c.g; g.taxes.tributo = 5; g.taxes.impuesto = 5; g.budget = { ejercito: 20, administracion: 10, obras: 0, diplomacia: 0 }; },
    constructor: (c) => { const g = c.g;
      if (g.ultimatum && g.ultimatum.estado === 'pendiente') c.pagarUltimatum();
      for (const a of ['zacapu', 'uruapan', 'tzintzuntzan']) for (const k of ['yacata', 'troje', 'fortaleza']) if (g.treasury >= cuesta(c, k) && accion(c, 'construir_' + k, a)) return; },
    militar: (c) => { const g = c.g;
      if (g.ultimatum && g.ultimatum.estado === 'pendiente') c.rechazarUltimatum();
      if (g.invasor) c.ordenar(g.invasor.pos);
      if (g.treasury > 600) accion(c, 'reclutar');
      if (!g.invasor && accion(c, 'expedicion_chichimeca')) return;
      accion(c, 'castigar'); accion(c, 'reconquistar');
      if (g.prisoners > 0) accion(c, 'prisioneros_ritual'); },
    experto: (c) => { const g = c.g, z = c.alt('zacapu');
      g.taxes.tributo = g.treasury < 300 ? 4 : 3; g.taxes.impuesto = 3;
      if (g.ultimatum && g.ultimatum.estado === 'pendiente' && g.treasury >= g.ultimatum.monto) c.pagarUltimatum();
      if (z && !z.independent) z.garrison = Math.min(1500, Math.max(0, g.army - 1000));
      if (g.invasor) c.ordenar(g.invasor.pos);
      if (g.prisoners > 0) accion(c, 'prisioneros_rescate');
      if (g.prestige < 15 && g.treasury > 700) accion(c, 'regalos');
      const plan = [['zacapu', 'yacata'], ['zacapu', 'troje'], ['uruapan', 'troje'], ['zacapu', 'fortaleza'], ['tzintzuntzan', 'troje'], ['uruapan', 'yacata']];
      for (const [a, k] of plan) if (g.treasury >= cuesta(c, k) + 150 && accion(c, 'construir_' + k, a)) return;
      if (!g.invasor && c.warStrength() > 9000) accion(c, 'expedicion_chichimeca'); },
  };

  // Puntuación provisional para comparar estrategias (no es una regla del juego).
  const puntuar = (c) => { const m = c.metrics(), g = c.g; return Math.round(m.pre * 10 + m.lea * 5 + m.ter * 20 + m.tes / 10 - m.ind * 300 - (g.capitalCaida ? 2000 : 0)); };

  // Una partida. `forzar` cambia la elección del evento número i: {i, opcion} o {i, perturbar: true}.
  const jugar = (seed, pol, forzar) => {
    const c = fresh(seed), g = c.g, rnd = mulberry(seed * 31 + 7);
    let k = 0, nModal = 0; const elecciones = [], ticksDecision = new Set();
    let ultimoTurno = -1;
    while (!g.ended && k < 2000) {
      if (g.modal) {
        let i = elegir[pol.elegir](c, rnd);
        if (forzar && forzar.i === nModal) { if (forzar.perturbar) c.R(); else if (okIdx(c).includes(forzar.opcion)) i = forzar.opcion; }
        elecciones.push({ n: nModal, t: g.t, titulo: g.modal.title, opciones: g.modal.options.map(x => ({ id: x.o.id, ok: x.ok })), elegida: i });
        ticksDecision.add(g.t); nModal++;
        if (i == null || i < 0) { g.modal = null; c.next(); } else c.pick(i);
      } else {
        if (g.t !== ultimoTurno) { const n0 = g.log.length; turno[pol.turno](c); if (g.log.slice(n0).some(e => !e.routine)) ticksDecision.add(g.t); ultimoTurno = g.t; }
        c.step();
      }
      k++;
    }
    c.resolveLog(true);
    const TY = c.D.C.ticks_por_anio, total = (g.endYear - 1475) * TY;
    const ts = [...ticksDecision].sort((a, b) => a - b); let maxHueco = 0, prev = 0; for (const t of ts) { maxHueco = Math.max(maxHueco, t - prev); prev = t; } maxHueco = Math.max(maxHueco, total - prev);
    const acciones = {}; for (const e of g.log) if (e.routine) acciones[e.decision] = (acciones[e.decision] || 0) + 1;
    return { seed, pol: pol.nombre, terminada: g.ended, anio: g.year, puntos: puntuar(c), m: c.metrics(), capitalCaida: !!g.capitalCaida,
      decisiones: g.log.length, deRumbo: g.log.filter(e => e.changing).length, eventos: nModal, acciones,
      ticksConDecision: ts.length, ticksTotales: total, maxHueco, elecciones, serie: g.series,
      cronica: g.chron.map(e => e.year + '·V' + e.v + ' ' + e.text) };
  };

  window.H = { fresh, jugar, elegir, turno, puntuar };
})();
