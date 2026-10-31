# Resume estrategias.json y divergencia.json: criterios de tensión (a)-(e) y modelo de espera.
import json, statistics as st, collections as co, sys
d = sys.argv[1] if len(sys.argv) > 1 else '.'
r = json.load(open(d + '/estrategias.json'))
SEG = {'velocidad 3 (20 s por veintena)': 20, 'velocidad 5 (3 s por veintena)': 3}
print(f"{'estrategia':34} pts   sd   caída tes   pre  lea  agr  ind  ev  rumbo hueco  D%  A%  V%  veredictos")
filas = {}
for k, v in r.items():
    pts = [x['puntos'] for x in v]; n = len(v)
    cl = ''.join(x['clase'] for x in v); D = cl.count('D') / len(cl); A = cl.count('A') / len(cl); V = cl.count('V') / len(cl)
    ver = co.Counter(x['veredicto'] for x in v)
    filas[k] = dict(m=st.mean(pts), sd=st.pstdev(pts), caida=sum(x['capitalCaida'] for x in v) / n)
    f = lambda key: st.mean(x['m'][key] for x in v)
    print(f"{k:34} {round(st.mean(pts)):5} {round(st.pstdev(pts)):4} {round(100*filas[k]['caida']):4}% {round(f('tes')):6} {f('pre'):5.1f} {f('lea'):4.0f} {f('agr'):4.0f} {f('ind'):4.2f} {st.mean(x['eventos'] for x in v):4.1f} {st.mean(x['deRumbo'] for x in v):4.1f} {st.mean(x['maxHueco'] for x in v):5.1f} {round(100*D):3} {round(100*A):3} {round(100*V):3}  {dict(ver)}")
ex, pa = filas['experto'], filas['pasivo (nada, primera opción)']
sdp = st.mean([ex['sd'], pa['sd']])
print('\n(a) experto − pasivo =', round(ex['m'] - pa['m']), 'puntos =', round((ex['m'] - pa['m']) / sdp, 2), 'desviaciones (meta > 1,5)')
caidas = [f['caida'] for f in filas.values()]
print('(e) caída de la capital entre estrategias: de', round(100*min(caidas)), '% a', round(100*max(caidas)), '%')
# (d) años sin decisión con costo, estrategia experta
anios = co.Counter()
for x in r['experto']:
    ys = set(t // 18 for t, c in enumerate(x['clase']) if c == 'D')
    for y in range(len(x['clase']) // 18):
        if y not in ys: anios[1475 + y] += 1
print('(d) años sin ninguna decisión (experto, de', len(r['experto']), 'partidas):', dict(sorted(anios.items())))
# Modelo de espera: tramos vacíos (ni decisión ni anticipación) y tramos sin decisión
def tramos(s, ch):
    out, n = [], 0
    for c in s:
        if c in ch: n += 1
        else:
            if n: out.append(n); n = 0
    if n: out.append(n)
    return out
for k in ['experto', 'pasivo (nada, primera opción)', 'militar']:
    v = r[k]; vac = [t for x in v for t in tramos(x['clase'], 'V')]; sin = [t for x in v for t in tramos(x['clase'], 'VA')]
    largo = st.mean(max(tramos(x['clase'], 'V') or [0]) for x in v)
    print(f"\nEspera, {k}: tramo vacío más largo (media) {largo:.1f} veintenas; tramos vacíos ≥ 3: {sum(1 for t in vac if t >= 3)/len(v):.1f} por partida")
    for nom, s in SEG.items():
        print(f"   {nom}: tramo vacío más largo ≈ {largo*s/60:.1f} min; segundos vacíos por minuto de juego ≈ {60*''.join(x['clase'] for x in v).count('V')/len(''.join(x['clase'] for x in v)):.0f}")
try:
    dv = json.load(open(d + '/divergencia.json'))
    g = co.defaultdict(list)
    for x in dv: g[x['titulo'][:40]].append(x)
    print('\n(b) por tipo de decisión: |Δ al invertirla| contra |Δ al perturbar solo el azar|')
    gana = 0
    for k2, v in sorted(g.items(), key=lambda kv: -len(kv[1])):
        a = st.mean(abs(x['dPuntos']) for x in v); b = st.mean(abs(x['dRuido']) for x in v); gana += a > b
        print(f"   {k2:40} n={len(v):3} decisión {a:6.0f}  azar {b:6.0f}  {'✓' if a > b else '✗'}")
    print(f"   tipos donde la decisión pesa más que el azar: {gana} de {len(g)}")
except FileNotFoundError: pass
