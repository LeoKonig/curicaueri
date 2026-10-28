## Panel genérico de una entidad: sus campos, sus magnitudes con el desglose en
## el tooltip y las entidades que la referencian. No sabe qué es un altépetl ni
## un pop: dibuja lo que el espejo trae, así que una magnitud o un campo nuevos
## aparecen sin código nuevo.
extends VBoxContainer

const Espejo = preload("res://red/espejo.gd")
const Desglose = preload("res://ui/desglose.gd")

var espejo
var clave_actual := ""


func mostrar(clave: String) -> void:
	clave_actual = clave
	refrescar()


func refrescar() -> void:
	for h in get_children():
		h.queue_free()
	if espejo == null or not espejo.entidades.has(clave_actual):
		_etiqueta("Selecciona un altépetl en el mapa.", false)
		return
	var e: Dictionary = espejo.entidades[clave_actual]
	var titulo := _etiqueta(_nombre(e), false)
	titulo.add_theme_font_size_override("font_size", 20)
	_entidad(e, "")
	var relacionadas: Array = espejo.que_referencian(clave_actual)
	if not relacionadas.is_empty():
		add_child(HSeparator.new())
		_etiqueta("Relacionadas (%d)" % relacionadas.size(), false)
		for r in relacionadas:
			_etiqueta(_nombre(r), false).add_theme_font_size_override("font_size", 15)
			_entidad(r, "    ")


func _entidad(e: Dictionary, sangria: String) -> void:
	for campo in e["campos"].keys():
		var v: Dictionary = e["campos"][campo]
		if v.get("t", "") == "ref" and Espejo.clave(v["v"]) == clave_actual:
			continue
		_etiqueta("%s%s: %s" % [sangria, campo, Desglose.valor(v)], false)
	for nombre in e["magnitudes"].keys():
		var mag: Dictionary = e["magnitudes"][nombre]
		var l := _etiqueta("%s%s: %s ⓘ" % [sangria, nombre, Desglose.numero(mag["efectivo"])], true)
		l.tooltip_text = Desglose.texto(nombre, mag)


func _nombre(e: Dictionary) -> String:
	var campos: Dictionary = e["campos"]
	if campos.has("nombre"):
		return Desglose.valor(campos["nombre"])
	var partes := [e["ref"]["clase"], str(int(e["ref"]["id"]))]
	for c in ["identidad", "estrato"]:
		if campos.has(c):
			partes.append(Desglose.valor(campos[c]))
	return " ".join(partes)


func _etiqueta(texto: String, con_tooltip: bool) -> Label:
	var l := Label.new()
	l.text = texto
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(380, 0)
	if con_tooltip:
		l.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(l)
	return l
