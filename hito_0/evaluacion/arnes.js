// Arnés para juzgar el prototipo del hito 0 jugando partidas completas desde la página.
// Se inyecta después de que el prototipo cargó sus datos (window.__hito0.D existe).
(() => {
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
  // Mover una tasa como lo haría el deslizador: no se puede subir si está bloqueada.
  const tasa = (c, k, v) => { const g = c.g; if (v > g.taxes[k] && g.locks && g.locks[k] > g.t) return; g.taxes[k] = v; };
  // Fuerza esperada contra la primera oleada, antes de que llegue (para decidir el ultimátum).
  const proporcionEsperada = (c) => { const g = c.g, IV = c.D.C.invasion, cap = c.alt('tzintzuntzan');
    const r = c.field() * (1 + IV.por_mando * (g.chars[g.captain].command - 3)) * (1 + IV.por_moral * (g.morale - 7)) * (1 + IV.bono_defensa + (cap.fortaleza ? IV.bono_fortaleza : 0));
    return r / Math.max(1, (g.invTropas || IV.tropas) * IV.fuerza_mexica); };
  const probExpedicion = (c) => { const X = c.D.C.guerra.expedicion; if (!X) return 1; const r = c.F('fuerza_expedicion', {}, {}), lo = r * X.base, w = r * X.varianza; return Math.max(0, Math.min(1, (lo + w - X.victoria) / w)); };

  // --- cómo elegir en un evento o crisis
  const elegir = {
    primera: (c) => okIdx(c)[0],
    ultima: (c) => { const o = okIdx(c); return o[o.length - 1]; },
    azar: (c, rnd) => { const o = okIdx(c); return o[Math.floor(rnd() * o.length)]; },
    criterio: (c) => { const g = c.g, o = okIdx(c), ti = g.modal.title || '', ids = g.modal.options.map(x => x.o.id);
      const por = (id) => { const i = ids.indexOf(id); return o.includes(i) ? i : null; };
      const primera = (...xs) => { for (const x of xs) { const i = por(x); if (i != null) return i; } return o[0]; };
      if (ids.includes('frontera')) { const pf = c.probBatalla(false), pc = c.probBatalla(true);
        if (Math.max(pf, pc) < 35 && por('pagar') != null) return por('pagar'); return pf >= pc ? por('frontera') : por('capital'); }
      if (ids.includes('ganar_tiempo')) return proporcionEsperada(c) >= 1.1 ? primera('rechazar') : primera('pagar', 'ganar_tiempo', 'rechazar');
      if (ids.includes('perseguir')) return probExpedicion(c) >= 0.6 ? primera('perseguir') : g.treasury >= 600 ? primera('reforzar') : primera('dejar');
      if (ids.includes('almacenar')) return g.treasury >= 500 ? primera('almacenar') : primera('rogativas', 'ignorar');
      if (ids.includes('apoyar')) return g.treasury >= 300 ? primera('apoyar') : primera('refugio');
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
    codicioso: (c) => { const g = c.g; tasa(c, 'tributo', 5); tasa(c, 'impuesto', 5); g.budget = { ejercito: 20, administracion: 10, obras: 0, diplomacia: 0 }; },
    constructor: (c) => { const g = c.g;
      for (const a of ['zacapu', 'uruapan', 'tzintzuntzan']) for (const k of ['yacata', 'troje', 'fortaleza']) if (g.treasury >= cuesta(c, k) && accion(c, 'construir_' + k, a)) return;
      if (g.treasury >= cuesta(c, 'gran_yacata')) accion(c, 'construir_gran_yacata', 'tzintzuntzan'); },
    militar: (c) => { const g = c.g;
      if (g.treasury > 600) accion(c, 'reclutar');
      if (!g.invasor && accion(c, 'expedicion_chichimeca')) return;
      accion(c, 'castigar'); accion(c, 'reconquistar');
      if (g.prisoners > 0) accion(c, 'prisioneros_ritual'); },
    experto: (c) => { const g = c.g, al = g.alts.filter(a => !a.independent);
      tasa(c, 'tributo', g.treasury < 300 ? 4 : 3); tasa(c, 'impuesto', 3);
      if (g.prisoners > 0) accion(c, 'prisioneros_rescate');
      const agr = al.reduce((s, a) => s + a.agravio, 0) / Math.max(1, al.length);
      if (agr > 28) accion(c, 'gran_fiesta');
      if (g.prestige < 25 && g.treasury > 900) accion(c, 'regalos');
      const amenaza = !g.invasor && g.year < g.invasionAnio && g.invasionAnio - g.year <= 2;
      if (amenaza && g.treasury > 700) accion(c, 'reclutar');
      const plan = [['tzintzuntzan', 'troje'], ['zacapu', 'yacata'], ['tzintzuntzan', 'fortaleza'], ['uruapan', 'troje'], ['zacapu', 'troje'], ['uruapan', 'yacata']];
      // Reserva para la embajada mexica de 1476 (el ultimátum y la ayuda a los matlatzincas cuestan).
      const reserva = g.year < 1476 || (g.ultimatum && g.ultimatum.estado === 'pendiente') ? 450 : 150;
      for (const [a, k] of plan) if (g.treasury >= cuesta(c, k) + reserva && accion(c, 'construir_' + k, a)) return;
      if (g.treasury >= cuesta(c, 'gran_yacata') + 300) accion(c, 'construir_gran_yacata', 'tzintzuntzan');
      if (!g.invasor && probExpedicion(c) >= 0.6) accion(c, 'expedicion_chichimeca'); },
  };

  // Puntuación provisional para comparar estrategias (no es una regla del juego).
  const puntuar = (c) => { const m = c.metrics(), g = c.g; return Math.round(m.pre * 10 + m.lea * 5 + m.ter * 20 + m.tes / 10 - m.ind * 300 - (g.capitalCaida ? 2000 : 0)); };

  // Qué hay "en el aire" en una veintena: lo que un jugador espera ver resolverse.
  // Es el componente de anticipación del modelo de espera (ver docs/evaluacion_hito0.md).
  const anticipaciones = (c) => { const g = c.g, L = [];
    if (g.alts.some(a => a.building) && g.budget.obras >= c.D.C.construccion.presupuesto_minimo) L.push('obra');
    if (g.invasor) L.push(g.invasor.asedio ? 'asedio' : 'invasor');
    if (g.ultimatum && g.ultimatum.estado === 'pendiente') L.push('ultimatum');
    if (!g.invasor && g.invasionAnio < 9000 && g.invasionAnio - g.year <= 1 && g.year >= 1476) L.push('invasion_anunciada');
    if (g.harvest && g.harvest.left > 0) L.push('hambre');
    if (g.sequiaEn != null) L.push('sequia_anunciada');
    if (g.ejercito && (g.ejercito.path.length || g.ejercito.incursion)) L.push('marcha');
    return L; };

  // Una partida. `forzar` cambia la elección del evento número i: {i, opcion} o {i, perturbar: true}.
  const jugar = (seed, pol, forzar) => {
    const c = fresh(seed), g = c.g, rnd = mulberry(seed * 31 + 7);
    let k = 0, nModal = 0; const elecciones = [], ticksDecision = new Set(), espera = [];
    let ultimoTurno = -1;
    while (!g.ended && k < 3000) {
      if (g.modal) {
        let i = elegir[pol.elegir](c, rnd);
        if (forzar && forzar.i === nModal) { if (forzar.perturbar) c.R(); else if (okIdx(c).includes(forzar.opcion)) i = forzar.opcion; }
        elecciones.push({ n: nModal, t: g.t, titulo: g.modal.title, opciones: g.modal.options.map(x => ({ id: x.o.id, ok: x.ok })), elegida: i });
        ticksDecision.add(g.t); nModal++;
        if (i == null || i < 0) { g.modal = null; c.next(); } else c.pick(i);
      } else {
        if (g.t !== ultimoTurno) { const n0 = g.log.length; turno[pol.turno](c); if (g.log.slice(n0).some(e => !e.routine)) ticksDecision.add(g.t); ultimoTurno = g.t;
          espera[g.t] = anticipaciones(c); }
        c.step();
      }
      k++;
    }
    c.resolveLog(true);
    const TY = c.D.C.ticks_por_anio, total = Math.min(g.t + 1, (g.endYear - 1475) * TY);
    const ts = [...ticksDecision].sort((a, b) => a - b); let maxHueco = 0, prev = 0; for (const t of ts) { maxHueco = Math.max(maxHueco, t - prev); prev = t; } maxHueco = Math.max(maxHueco, total - prev);
    // Clasificación de cada veintena para el modelo de espera.
    const clase = []; for (let t = 0; t < total; t++) clase.push(ticksDecision.has(t) ? 'D' : (espera[t] && espera[t].length ? 'A' : 'V'));
    const acciones = {}; for (const e of g.log) if (e.routine) acciones[e.decision] = (acciones[e.decision] || 0) + 1;
    const ver = c.veredicto ? c.veredicto() : null;
    return { seed, pol: pol.nombre, terminada: g.ended, anio: g.year, puntos: puntuar(c), m: c.metrics(), capitalCaida: !!g.capitalCaida, fin: g.fin || null,
      veredicto: ver ? ver.nivel : null, metas: ver ? ver.cumplidas : null,
      decisiones: g.log.length, deRumbo: g.log.filter(e => e.changing).length, eventos: nModal, acciones,
      ticksConDecision: ts.length, ticksTotales: total, maxHueco, clase: clase.join(''), elecciones, serie: g.series,
      cronica: g.chron.map(e => e.year + '·V' + e.v + ' ' + e.text) };
  };

  window.H = { fresh, jugar, elegir, turno, puntuar, tasa, anticipaciones };
})();
