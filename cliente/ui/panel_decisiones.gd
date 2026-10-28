## Decisiones que el guion le presenta al jugador (V5, *Actos modulares*).
## Genérico: muestra la situación, su tipo, el plazo y las opciones tal como
## llegan; no sabe nada de sucesiones ni de tributos. Un botón por opción o un
## selector para las preguntas de cantidad. Si el plazo vence, el núcleo aplica
## la primera opción y avisa con "decision_cerrada".
extends VBoxContainer

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
		titulo.text = "%s  [%s]" % [_legible(d["situacion"]), d.get("tipo_situacion", "")]
		titulo.add_theme_font_size_override("font_size", 17)
		add_child(titulo)
		if d.get("plazo") != null:
			var plazo := Label.new()
			plazo.text = "Quedan %d días; si no respondes, se toma «%s»." % [maxi(0, int(d["plazo"]) - hoy), _omision(d["pregunta"])]
			add_child(plazo)
		var p: Dictionary = d["pregunta"]
		if p["tipo"] == "opcion":
			var fila := HFlowContainer.new()
			add_child(fila)
			for o in p["opciones"]:
				var b := Button.new()
				b.text = _legible(o)
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


static func _omision(p: Dictionary) -> String:
	if p["tipo"] == "opcion" and not p["opciones"].is_empty():
		return _legible(p["opciones"][0])
	return str(p.get("min", ""))
