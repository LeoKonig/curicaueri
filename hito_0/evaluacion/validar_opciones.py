# Criterio (c): ninguna opción de evento o crisis sin algún costo o efecto negativo.
# Heurística sobre los datos: cuenta como costo un "costo", una magnitud buena que baja,
# un agravio que sube, un riesgo (resolver/probabilidad), un bloqueo o plazo (estado con tick_mas),
# o perder algo (invasor que adelanta, tributo menor por autonomía, trojes vaciadas).
# Una opción cuyo costo llega después declara su riesgo en el campo "riesgo" de los datos.
import json, sys, os
d = os.path.join(os.path.dirname(__file__), '..', 'datos')
BUENAS = {'prestigio', 'tesoro', 'lealtad', 'ejercito', 'poblacion', 'guarnicion'}
def negativo(e):
    t = e.get('tipo')
    if t == 'magnitud':
        v = e.get('sumar'); f = e.get('factor')
        if isinstance(v, (int, float)): return (v < 0 and e['magnitud'] in BUENAS) or (v > 0 and e['magnitud'] == 'agravio')
        if isinstance(v, dict) and v.get('formula') == 'negar': return e['magnitud'] in BUENAS
        if isinstance(f, (int, float)): return f < 1 and e['magnitud'] in BUENAS
    if t in ('resolver', 'probabilidad'): return True
    if t == 'construir' and e.get('costo'): return True
    if t == 'estado':
        f = e.get('fijar'); c = e.get('campo', '')
        if isinstance(f, dict) and f.get('formula') == 'tick_mas' and (c.startswith('locks') or 'autonomia' in c or 'trojeVacia' in c): return True
        if c == 'invasionAnio' and isinstance(f, dict) and f['args'].get('n', 0) < 0: return True
        if c == 'invTropas' and isinstance(f, (int, float)) and f > 30000: return True
        if c == 'tributeOut': return True
    if t in ('para_cada', 'si'): return any(negativo(x) for k in ('efectos', 'entonces', 'sino') for x in e.get(k, []) or [])
    if t == 'crear_pop': return (e.get('agravio') or 0) >= 30
    if t == 'encolar': return True
    return False
malas = []
for f, k in (('eventos', 'eventos'), ('crisis', 'crisis')):
    for ev in json.load(open(os.path.join(d, f + '.json')))[k]:
        if len(ev['opciones']) == 1: continue          # un aviso, no una decisión
        for o in ev['opciones']:
            if o.get('costo') or o.get('riesgo') or o.get('consecuencia_de'): continue   # costo inmediato, riesgo diferido o consecuencia de una decisión anterior
            if not any(negativo(e) for e in o.get('efectos', [])): malas.append(ev['id'] + '.' + o['id'])
print('opciones sin costo visible:', malas or 'ninguna')
sys.exit(1 if malas else 0)
