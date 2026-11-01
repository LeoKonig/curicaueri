#!/bin/bash
timeout 120 node voz.js "$1" "$2" "$3" | python3 -c "
import json,sys; d=json.load(sys.stdin)
if d['pendiente']:
  print(d['anio'],'V',d['veintena'],'|',d['titulo']); print(d['cuerpo']); print(d['desc'])
  for o in d['opciones']: print(' -',o['id'],':',o['titulo'],'|',o['costo'],'' if o['disponible'] else '(NO: '+o['por_que_no']+')')
  e=d['estado']; print('tesoro',e['tesoro'],'pre',e['prestigio'],'ej',e['ejercito'],'neto',e['ingresoNeto'],'tasas',e['tasas']); [print('  ',a['n'],'lea',a['lealtad'],'agr',a['agravio'],'indep' if a['indep'] else '','gob',a['gob']) for a in e['altepetl']]; print('diario',d['diario'][-6:])
else:
  print('FIN puntos',d['puntos'],'caída',d['capitalCaida'],d['m'],'decisiones',d['decisiones'],'rumbo',d['deRumbo']); print('\n'.join(d['diario'])); print('---'); print('\n'.join(d['cronica']))"
