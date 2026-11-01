## Copia de solo lectura del estado visible (V5, *Espejo en el cliente*).
##
## Se reconstruye entera con cada instantánea y después se actualiza
## REEMPLAZANDO las entidades que llegan en los cambios: nunca se fusiona nada.
## Incluye los modificadores activos de cada magnitud, así que los tooltips de
## desglose se arman aquí, sin preguntar al núcleo.
extends RefCounted

var entidades := {}        # "clase:id" -> entidad (diccionario del protocolo)
var reloj := {}
var magnitudes := {}       # id de magnitud -> declaración del catálogo
var comandos := []
var velocidades := []      # milisegundos por día, de la velocidad 1 a la 5
var calendario := {}       # calendario interno del escenario: nombres y longitudes de los periodos
var mapa := {}
var ejes := []             # ejes de poder activos del escenario (puede ser vacío)
var decisiones := {}       # id -> mensaje "decision" del núcleo, mientras espera respuesta


static func clave(ref: Dictionary) -> String:
	return "%s:%d" % [ref["clase"], int(ref["id"])]


## La referencia del protocolo a partir de la clave «clase:id».
static func ref_de(clave_entidad: String) -> Dictionary:
	var i := clave_entidad.rfind(":")
	return {"clase": clave_entidad.substr(0, i), "id": int(clave_entidad.substr(i + 1))}


func recibir(m: Dictionary) -> void:
	match m.get("tipo", ""):
		"catalogo":
			magnitudes.clear()
			for d in m["magnitudes"]:
				magnitudes[d["id"]] = d
			comandos = m["comandos"]
			velocidades = m.get("velocidades", [])
			calendario = m.get("calendario", {})
			ejes = m.get("ejes", [])
		"mapa":
			mapa = m
		"instantanea":
			instantanea(m)
		"cambios":
			aplicar_cambios(m)
		"reloj":
			reloj = m["reloj"]
		"decision":
			decisiones[int(m["id"])] = m
		"decision_cerrada":
			decisiones.erase(int(m["id"]))


func instantanea(m: Dictionary) -> void:
	entidades.clear()
	# El núcleo vuelve a mandar las decisiones pendientes tras cada instantánea.
	decisiones.clear()
	for e in m["entidades"]:
		entidades[clave(e["ref"])] = e
	reloj = m["reloj"]


func aplicar_cambios(m: Dictionary) -> void:
	for r in m["eliminadas"]:
		entidades.erase(clave(r))
	for e in m["actualizadas"]:
		entidades[clave(e["ref"])] = e
	reloj = m["reloj"]


func de_clase(c: String) -> Array:
	var r := []
	for k in entidades.keys():
		if entidades[k]["ref"]["clase"] == c:
			r.append(entidades[k])
	return r


## Entidades que tienen un campo de tipo referencia que apunta a esta.
## Genérico: así un panel muestra los pops de un altépetl sin saber qué es un pop.
func que_referencian(clave_entidad: String) -> Array:
	var r := []
	for k in entidades.keys():
		for valor in entidades[k]["campos"].values():
			if valor.get("t", "") == "ref" and clave(valor["v"]) == clave_entidad:
				r.append(entidades[k])
				break
	return r


## Modo de depuración: recalcula cada valor efectivo desde la base y los
## aportes del espejo y avisa si no coincide con el que mandó el núcleo.
## Devuelve las discrepancias (vacío si todo cuadra).
func verificar(e: Dictionary) -> Array:
	var errores := []
	for nombre in e["magnitudes"].keys():
		var mag: Dictionary = e["magnitudes"][nombre]
		var suma := float(mag["base"])
		var pct := 0.0
		for a in mag["aportes"]:
			suma += float(a["sumando"])
			pct += float(a["porcentaje"])
		var v := suma * (1.0 + pct)
		if magnitudes.has(nombre):
			v = clampf(v, float(magnitudes[nombre]["min"]), float(magnitudes[nombre]["max"]))
		if absf(v - float(mag["efectivo"])) > 0.0002 * maxf(1.0, absf(v)):
			errores.append("%s.%s: el espejo calcula %s, el núcleo dice %s" % [clave(e["ref"]), nombre, v, mag["efectivo"]])
	return errores


## Nombre legible de una entidad, sea cual sea su clase.
func nombre(clave_entidad: String) -> String:
	if not entidades.has(clave_entidad):
		return clave_entidad
	var e: Dictionary = entidades[clave_entidad]
	var campos: Dictionary = e["campos"]
	if campos.has("nombre"):
		return str(campos["nombre"]["v"])
	var partes := [str(e["ref"]["clase"]), str(int(e["ref"]["id"]))]
	for c in ["identidad", "estrato"]:
		if campos.has(c) and campos[c].get("t", "") == "texto":
			partes.append(str(campos[c]["v"]))
	var padre := ""
	for v in campos.values():
		if v.get("t", "") == "ref":
			padre = nombre(clave(v["v"]))
			break
	return " ".join(partes) + (" de " + padre if padre != "" else "")


## Valores numéricos visibles (magnitudes efectivas y campos numéricos), para
## comparar dos momentos: el informe de veintena usa esto.
func numeros() -> Dictionary:
	var r := {}
	for k in entidades.keys():
		var e: Dictionary = entidades[k]
		for n in e["magnitudes"].keys():
			r[k + "|" + n] = float(e["magnitudes"][n]["efectivo"])
		for n in e["campos"].keys():
			var v: Dictionary = e["campos"][n]
			if v.get("t", "") in ["entero", "fijo"]:
				r[k + "|" + n] = float(v["v"])
	return r
