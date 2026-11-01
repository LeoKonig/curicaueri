## Mensajes del cliente al núcleo. Los nombres JSON son los del contrato
## (pruebas_compartidas/protocolo/cliente_*.json); la prueba del protocolo
## comprueba que coinciden.
extends RefCounted

const VERSION := 3


static func hola() -> Dictionary:
	return {"tipo": "hola", "version": VERSION}


static func comando(secuencia: int, cmd: Dictionary) -> Dictionary:
	return {"tipo": "comando", "secuencia": secuencia, "comando": cmd}


static func pausa(valor: bool) -> Dictionary:
	return {"tipo": "control", "accion": "pausa", "valor": valor}


static func velocidad(valor: int) -> Dictionary:
	return {"tipo": "control", "accion": "velocidad", "valor": valor}


static func consulta(secuencia: int, cmd: Dictionary) -> Dictionary:
	return {"tipo": "consulta", "secuencia": secuencia, "comando": cmd}


static func guardar(nombre: String) -> Dictionary:
	return {"tipo": "control", "accion": "guardar", "nombre": nombre}


static func cargar(nombre: String) -> Dictionary:
	return {"tipo": "control", "accion": "cargar", "nombre": nombre}


static func responder(secuencia: int, decision: int, respuesta: String) -> Dictionary:
	return {"tipo": "responder", "secuencia": secuencia, "decision": decision, "respuesta": respuesta}


## Las entidades cuyo detalle se quiere ver (los pops de un altépetl). El
## núcleo responde con cambios: entra el detalle pedido y sale el que se deja.
static func interes(refs: Array) -> Dictionary:
	return {"tipo": "interes", "entidades": refs}
