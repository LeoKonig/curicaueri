// Genera las tablas de casos del hito 0a (V5, contrato de entrega, punto 2).
//
// Las fórmulas se toman del prototipo HTML tal cual: cada método se extrae por
// su nombre y se ejecuta con un `this` de prueba. Solo se fijan a mano las
// piezas que el juego todavía no tiene (el territorio, que viene del mapa; los
// edificios, la guarnición y las necesidades); cada una queda anotada en la
// tabla como una entrada explícita.
//
// Uso: node hito_0/tablas/generar.mjs
// Salida: nucleo/reglas/test/tablas_hito0.json

import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const raiz = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const htmlPath = join(raiz, 'hito_0', 'Hito 0 v5 - Reino purepecha.dc.html');
const constPath = join(raiz, 'hito_0', 'datos', 'constantes.json');
const salida = join(raiz, 'nucleo', 'reglas', 'test', 'tablas_hito0.json');

const html = readFileSync(htmlPath, 'utf8');
const C = JSON.parse(readFileSync(constPath, 'utf8'));
const TY = C.ticks_por_anio;

// --- extracción de métodos por nombre, con balance de llaves ---------------
const lineas = html.split('\n');

function extraerMetodo(nombre) {
  const inicio = lineas.findIndex((l) => l.startsWith(`  ${nombre}(`));
  if (inicio < 0) throw new Error(`método no encontrado en el prototipo: ${nombre}`);
  let fuente = '';
  let profundidad = 0;
  let abierto = false;
  for (let i = inicio; i < lineas.length; i++) {
    fuente += lineas[i] + '\n';
    for (const ch of lineas[i]) {
      if (ch === '{') { profundidad++; abierto = true; }
      if (ch === '}') profundidad--;
    }
    if (abierto && profundidad === 0) break;
  }
  return fuente;
}

const NOMBRES = [
  'taxM', 'tShare', 'tx', 'incomeParts', 'rawIncome', 'tributeIn', 'income',
  'totalIncome', 'expenseLines', 'totalExpenses', 'needs', 'popParts',
  'effLines', 'eff',
];
const fuentes = NOMBRES.map(extraerMetodo).join(",\n");
const metodos = new Function(`return ({\n${fuentes}\n});`)();

// --- `this` de prueba -------------------------------------------------------
function nuevoThis(g) {
  const self = { D: { C }, g, ...metodos };
  for (const n of NOMBRES) self[n] = metodos[n].bind(self);
  return self;
}

function altepetl(id, pop, distance, pops, extra = {}) {
  return {
    id, pop, distance, pops,
    garrison: 0, yacata: false, fortaleza: false, troje: false,
    building: null, independent: false, moroso: false,
    territoryValue: 0, res: {}, governor: 'g',
    ...extra,
  };
}

// El cazonci por omisión es Zuangua (administración 3): su término de
// eficiencia vale 0. Los gobernadores se identifican por su administración.
const CAZONCI = { name: 'Zuangua', admin: 3 };
const gobernadores = (...admins) => Object.fromEntries(admins.map((a) => [`g${a}`, { name: `g${a}`, admin: a }]));

function gestionDe(T, I, alts, presupuesto, chars, ruler = CAZONCI) {
  return {
    taxes: { tributo: T, impuesto: I },
    budget: presupuesto ?? { ejercito: 0, administracion: 0, obras: 0, diplomacia: 0 },
    tributeOut: { left: 0, amount: 0 },
    army: 0,
    alts,
    chars: { ...gobernadores(0, 1, 2, 3, 4), ...(chars ?? {}), ruler },
    ruler: 'ruler',
    harvest: { left: 0, pen: 0 },
  };
}

const redondo = (x) => Math.round(x * 1e9) / 1e9;
const pobladores = (tams, identidades = []) =>
  tams.map((tam, i) => ({
    id: `p${i}`, identidad: identidades[i] ?? 'purepecha', estrato: 'comun', tam, lealtad: 50, agravio: 0,
  }));
const sumarPop = (a) => { a.pop = a.pops.reduce((s, p) => s + p.tam, 0); return a; };

// --- casos ------------------------------------------------------------------
const casos = {};

// 1. Tasas: taxM y tShare para capital y para sujeta, con toda la rejilla 1..5.
casos.tasas = [];
for (const T of [1, 2, 3, 4, 5]) for (const I of [1, 2, 3, 4, 5]) {
  for (const capital of [true, false]) {
    const a = altepetl(capital ? 'tzintzuntzan' : 'zacapu', 1000, 0, []);
    const self = nuevoThis(gestionDe(T, I, [a]));
    casos.tasas.push({
      tributo: T, impuesto: I, capital,
      taxM: redondo(self.taxM(a)),
      tShare: redondo(self.tShare(a)),
    });
  }
}

// 2. Eficiencia (`effLines`): administración del gobernador, distancia,
//    presupuesto de administración, administración del cazonci y fracción de
//    pobladores de identidad ajena. Las fracciones se eligen lejos de un
//    empate de redondeo (x,5), donde los flotantes y el punto fijo difieren.
casos.eficiencia = [];
const fracciones = [
  { purepecha: 1000, ajena: 0 },
  { purepecha: 1999, ajena: 1 },      // 0,0005: bajo el umbral de 0,001
  { purepecha: 850, ajena: 150 },     // 0,15 → −3
  { purepecha: 700, ajena: 300 },     // 0,30 → −6
  { purepecha: 2000, ajena: 1000 },   // 1/3 → −6,67 → −7
  { purepecha: 500, ajena: 500 },     // 0,50 → −10
];
for (const adm of [0, 1, 2, 3, 4]) for (const dist of [0, 1, 2]) for (const presupuestoAdm of [0, 25, 40]) {
  for (const adminCazonci of [2, 3, 4]) for (const f of fracciones) {
    const pops = pobladores([f.purepecha, f.ajena].filter((n) => n > 0),
      f.ajena > 0 ? ['purepecha', 'nahua'] : ['purepecha']);
    const a = sumarPop(altepetl('zacapu', 0, dist, pops, { governor: `g${adm}` }));
    const self = nuevoThis(gestionDe(3, 3, [a],
      { ejercito: 0, administracion: presupuestoAdm, obras: 0, diplomacia: 0 },
      null, { name: 'Cazonci', admin: adminCazonci }));
    casos.eficiencia.push({
      adminGobernador: adm, distancia: dist, presupuestoAdministracion: presupuestoAdm,
      adminCazonci,
      pobladoresPurepecha: f.purepecha, pobladoresAjenos: f.ajena,
      puntos: self.effLines(a).tot,
    });
  }
}

// 3. Ingreso total del escenario de 1475: tres altépetl (capital y dos
//    sujetas) con sus gobernadores e identidades, y la eficiencia de cada
//    una. Sin territorio (territoryValue = 0).
casos.ingreso_total = [];
for (const [T, I, presupuestoAdm] of [[3, 3, 25], [1, 5, 25], [5, 1, 0], [4, 2, 40]]) {
  const cap = sumarPop(altepetl('tzintzuntzan', 0, 0, pobladores([3000, 27000]), { governor: 'g4' }));
  const z = sumarPop(altepetl('zacapu', 0, 2, pobladores([8400, 3600], ['purepecha', 'hnahnu']), { governor: 'g1' }));
  const u = sumarPop(altepetl('uruapan', 0, 1, pobladores([15300, 2700], ['purepecha', 'nahua']), { governor: 'g3' }));
  const alts = [cap, z, u];
  const self = nuevoThis(gestionDe(T, I, alts,
    { ejercito: 0, administracion: presupuestoAdm, obras: 0, diplomacia: 0 }));
  casos.ingreso_total.push({
    tributo: T, impuesto: I, presupuestoAdministracion: presupuestoAdm,
    altepetl: alts.map((a) => ({
      alt: a.id, sujeta: a.id !== 'tzintzuntzan',
      adminGobernador: Number(a.governor.slice(1)), distancia: a.distance,
      pobladoresPurepecha: a.pops.filter((p) => p.identidad === 'purepecha').reduce((s, p) => s + p.tam, 0),
      pobladoresAjenos: a.pops.filter((p) => p.identidad !== 'purepecha').reduce((s, p) => s + p.tam, 0),
    })),
    totalIncome: redondo(self.totalIncome()),
  });
}

// 4. Gastos del presupuesto: puntos × tesoro_por_punto_presupuesto, sin ejército
//    (army = 0, así que el mínimo por soldados vale 0) y sin obras (sin edificios).
casos.gastos = [];
for (const [ej, adm, dip] of [[30, 25, 15], [0, 0, 0], [10, 40, 5], [50, 0, 20]]) {
  const alts = [sumarPop(altepetl('tzintzuntzan', 0, 0, pobladores([3000, 27000])))];
  const self = nuevoThis(gestionDe(3, 3, alts, { ejercito: ej, administracion: adm, obras: 30, diplomacia: dip }));
  casos.gastos.push({
    ejercito: ej, administracion: adm, diplomacia: dip,
    totalExpenses: redondo(self.totalExpenses()),
  });
}

// 5. Agravio por veintena (componentes de popParts que el juego puede calcular):
//    Tributo, Impuesto interno, Gobernador, Identidad ajena y Distancia,
//    divididos por TY. Yácata, troje, guarnición y necesidades quedan fuera
//    (hitos posteriores).
const COMPONENTES = new Map([
  ['Tributo', 'Tributo'],
  ['Impuesto interno', 'Impuesto interno'],
  ['Identidad ajena', 'Identidad ajena'],
  ['Distancia a la capital', 'Distancia a la capital'],
]);
const nombreComponente = (k) => (k.startsWith('Gobernador') ? 'Gobernador' : COMPONENTES.get(k));
casos.agravio_por_veintena = [];
for (const [T, I] of [[3, 3], [5, 3], [1, 3], [3, 5], [3, 1], [5, 5], [1, 1]]) {
  for (const capital of [true, false]) for (const estrato of ['comun', 'nobleza']) {
    for (const identidad of ['purepecha', 'nahua']) for (const distancia of [0, 60]) {
      for (const adm of [1, 3, 4]) {
        const pop = { id: 'p', identidad, estrato, tam: 1000, lealtad: 50, agravio: 0 };
        const a = sumarPop(altepetl(capital ? 'tzintzuntzan' : 'zacapu', 0, distancia, [pop], { governor: `g${adm}` }));
        const self = nuevoThis(gestionDe(T, I, [a]));
        const partes = self.popParts(a, pop).filter((l) => nombreComponente(l.k));
        const suma = partes.reduce((s, l) => s + l.v, 0);
        casos.agravio_por_veintena.push({
          tributo: T, impuesto: I, capital, estrato, identidad, distancia,
          adminGobernador: adm,
          componentes: Object.fromEntries(partes.map((l) => [nombreComponente(l.k), redondo(l.v)])),
          porVeintena: redondo(suma / TY),
        });
      }
    }
  }
}

const salidaJson = {
  fuente: 'hito_0/Hito 0 v5 - Reino purepecha.dc.html (métodos extraídos por nombre)',
  generador: 'hito_0/tablas/generar.mjs',
  ticks_por_anio: TY,
  constantes: { economia: C.economia, eficiencia: C.eficiencia },
  supuestos: {
    cazonci_admin: CAZONCI.admin,
    territoryValue: 0,
    ejercito_en_campana: 0,
    obras: 0,
    yacata_troje_guarnicion_necesidades: 'fuera: hitos posteriores',
  },
  casos,
};

writeFileSync(salida, JSON.stringify(salidaJson, null, 2) + '\n');
console.log(`tablas escritas en ${salida}`);
for (const [nombre, lista] of Object.entries(casos)) console.log(`  ${nombre}: ${lista.length} casos`);
