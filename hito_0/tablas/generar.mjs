// Genera las tablas de casos del hito 0a (V5, contrato de entrega, punto 2).
//
// Las fórmulas se toman del prototipo HTML tal cual: cada método se extrae por
// su nombre y se ejecuta con un `this` de prueba. Solo se fijan a mano las
// piezas que el juego de 1b todavía no tiene (la eficiencia y el territorio,
// que vienen del mapa, los gobernadores, la yácata, el troje y la guarnición);
// cada una queda anotada en la tabla como una entrada explícita.
//
// Uso: node hito_0/tablas/generar.mjs
// Salida: nucleo/reglas/test/tablas_hito0.json

import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const raiz = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const htmlPath = join(raiz, 'hito_0', 'Hito 0 v4 - Reino purepecha.dc.html');
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
];
const fuentes = NOMBRES.map(extraerMetodo).join(",\n");
const metodos = new Function(`return ({\n${fuentes}\n});`)();

// --- `this` de prueba -------------------------------------------------------
// eff: la eficiencia sale de los edificios y del gobernador; en 1b no existen,
// así que vale 1 (100 %). Es una entrada fija, no una fórmula del prototipo.
function nuevoThis(g) {
  const self = {
    D: { C },
    g,
    eff: () => 1,
    ...metodos,
  };
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

function gestionDe(T, I, alts, presupuesto = { ejercito: 0, administracion: 0, obras: 0, diplomacia: 0 }) {
  return {
    taxes: { tributo: T, impuesto: I },
    budget: presupuesto,
    tributeOut: { left: 0, amount: 0 },
    army: 0,
    alts,
    chars: { g: { admin: 2 } },
    harvest: { left: 0, pen: 0 },
  };
}

const redondo = (x) => Math.round(x * 1e9) / 1e9;

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

// 2. Ingreso total con tres altépetl (capital y dos sujetas): tributo a la capital.
//    Sin territorio (territoryValue = 0) y eficiencia 1.
casos.ingreso_total = [];
const pobladores = (tams) => tams.map((tam, i) => ({ id: `p${i}`, identidad: 'purepecha', estrato: 'comun', tam, lealtad: 50, agravio: 0 }));
for (const [T, I] of [[3, 3], [1, 5], [5, 1], [4, 2]]) {
  const cap = altepetl('tzintzuntzan', 30000, 0, pobladores([3000, 27000]));
  const z = altepetl('zacapu', 12000, 2, pobladores([8400, 3600]));
  const u = altepetl('uruapan', 18000, 1, pobladores([15300, 2700]));
  for (const a of [cap, z, u]) a.pop = a.pops.reduce((s, p) => s + p.tam, 0);
  const alts = [cap, z, u];
  const self = nuevoThis(gestionDe(T, I, alts));
  casos.ingreso_total.push({
    tributo: T, impuesto: I,
    poblacion: alts.map((a) => ({ alt: a.id, pop: a.pop, sujeta: a.id !== 'tzintzuntzan' })),
    totalIncome: redondo(self.totalIncome()),
  });
}

// 3. Gastos del presupuesto: puntos × tesoro_por_punto_presupuesto, sin ejército
//    (army = 0, así que el mínimo por soldados vale 0) y sin obras (sin edificios).
casos.gastos = [];
for (const [ej, adm, dip] of [[30, 25, 15], [0, 0, 0], [10, 40, 5], [50, 0, 20]]) {
  const alts = [altepetl('tzintzuntzan', 30000, 0, pobladores([3000, 27000]))];
  alts[0].pop = 30000;
  const self = nuevoThis(gestionDe(3, 3, alts, { ejercito: ej, administracion: adm, obras: 30, diplomacia: dip }));
  casos.gastos.push({
    ejercito: ej, administracion: adm, diplomacia: dip,
    totalExpenses: redondo(self.totalExpenses()),
  });
}

// 4. Agravio por veintena (componentes de popParts que 1b puede calcular):
//    Tributo, Impuesto interno, Identidad ajena y Distancia, divididos por TY.
//    Gobernador, yácata, troje, guarnición y necesidades quedan fuera (hitos 3 y 4).
const COMPONENTES = new Set(['Tributo', 'Impuesto interno', 'Identidad ajena', 'Distancia a la capital']);
casos.agravio_por_veintena = [];
for (const [T, I] of [[3, 3], [5, 3], [1, 3], [3, 5], [3, 1], [5, 5], [1, 1]]) {
  for (const capital of [true, false]) for (const estrato of ['comun', 'nobleza']) for (const identidad of ['purepecha', 'nahua']) for (const distancia of [0, 60]) {
    const pop = { id: 'p', identidad, estrato, tam: 1000, lealtad: 50, agravio: 0 };
    const a = altepetl(capital ? 'tzintzuntzan' : 'zacapu', 1000, distancia, [pop]);
    const self = nuevoThis(gestionDe(T, I, [a]));
    const partes = self.popParts(a, pop).filter((l) => COMPONENTES.has(l.k));
    const suma = partes.reduce((s, l) => s + l.v, 0);
    casos.agravio_por_veintena.push({
      tributo: T, impuesto: I, capital, estrato, identidad, distancia,
      componentes: Object.fromEntries(partes.map((l) => [l.k, redondo(l.v)])),
      porVeintena: redondo(suma / TY),
    });
  }
}

const salidaJson = {
  fuente: 'hito_0/Hito 0 v4 - Reino purepecha.dc.html (métodos extraídos por nombre)',
  generador: 'hito_0/tablas/generar.mjs',
  ticks_por_anio: TY,
  constantes: C.economia,
  supuestos: {
    eficiencia: 1,
    territoryValue: 0,
    ejercito_en_campana: 0,
    obras: 0,
    gobernador_admin: 2,
  },
  casos,
};

writeFileSync(salida, JSON.stringify(salidaJson, null, 2) + '\n');
console.log(`tablas escritas en ${salida}`);
for (const [nombre, lista] of Object.entries(casos)) console.log(`  ${nombre}: ${lista.length} casos`);
