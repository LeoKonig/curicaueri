## Decisiones que el guion le presenta al jugador (V5, *Actos modulares*).
## Genérico: muestra la situación, su tipo, el plazo y las opciones tal como
## llegan; no sabe nada de sucesiones ni de tributos. Un botón por opción o un
## selector para las preguntas de cantidad. Si el plazo vence, el núcleo aplica
## la primera opción y avisa con "decision_cerrada".
##
## Los textos salen de cliente/textos/es.json por el id de la situación:
## «situacion.<id>» (título), «situacion.<id>.texto», «situacion.<id>.<opción>»
## y «situacion.<id>.<opción>.costo» (el costo visible antes de confirmar).
## Sin texto, se muestra el id legible, como antes.
extends VBoxContainer

const Textos = preload("res://red/textos.gd")

signal respuesta_pedida(decision: int, respuesta: String)

var espejo


func refrescar() -> void:
	for h in get_children():
		h.queue_free()
	if espejo == null or espejo.decisiones.is_empty():
		var vacio := Label.new()
		vacio.text = "No hay decisiones pendientes."
		add_child(vacio)
		return
	var ids: Array = espejo.decisiones.keys()
	ids.sort()
	var hoy := int(espejo.reloj.get("tick", 0))
	for id in ids:
		var d: Dictionary = espejo.decisiones[id]
		var titulo := Label.new()
		titulo.text = "%s  [%s]" % [titulo_de(d), tipo_de(d)]
		titulo.add_theme_font_size_override("font_size", 17)
		add_child(titulo)
		var cuerpo := texto_de(d)
		if cuerpo != "":
			var l := Label.new()
			l.text = cuerpo
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			add_child(l)
		if d.get("plazo") != null:
			var plazo := Label.new()
			plazo.text = "Quedan %d días; si no respondes, se toma «%s»." % [maxi(0, int(d["plazo"]) - hoy), _omision(d)]
			add_child(plazo)
		var p: Dictionary = d["pregunta"]
		if p["tipo"] == "opcion":
			var fila := HFlowContainer.new()
			add_child(fila)
			for o in p["opciones"]:
				var b := Button.new()
				b.text = opcion_de(d, str(o))
				var c := costo_de(d, str(o))
				if c != "":
					b.text += "\n" + c
				b.pressed.connect(func(): respuesta_pedida.emit(int(id), str(o)))
				fila.add_child(b)
		else:
			var fila := HBoxContainer.new()
			add_child(fila)
			var sel := SpinBox.new()
			sel.min_value = float(p["min"])
			sel.max_value = float(p["max"])
			fila.add_child(sel)
			var b := Button.new()
			b.text = "Responder"
			b.pressed.connect(func(): respuesta_pedida.emit(int(id), str(int(sel.value))))
			fila.add_child(b)
		add_child(HSeparator.new())


static func _legible(t: String) -> String:
	return t.replace("_", " ").capitalize() if t != "" else "?"


## El texto de una clave, o el respaldo si no existe.
static func _texto(clave: String, respaldo: String) -> String:
	return Textos.de(clave) if Textos.existe(clave) else respaldo


static func titulo_de(d: Dictionary) -> String:
	return _texto("situacion." + str(d["situacion"]), _legible(str(d["situacion"])))


static func tipo_de(d: Dictionary) -> String:
	var t := str(d.get("tipo_situacion", ""))
	return _texto("tipo_situacion." + t, t)


static func texto_de(d: Dictionary) -> String:
	return _texto("situacion.%s.texto" % d["situacion"], "")


static func opcion_de(d: Dictionary, o: String) -> String:
	return _texto("situacion.%s.%s" % [d["situacion"], o], _legible(o))


static func costo_de(d: Dictionary, o: String) -> String:
	return _texto("situacion.%s.%s.costo" % [d["situacion"], o], "")


static func _omision(d: Dictionary) -> String:
	var p: Dictionary = d["pregunta"]
	if p["tipo"] == "opcion" and not p["opciones"].is_empty():
		return opcion_de(d, str(p["opciones"][0]))
	return str(p.get("min", ""))
