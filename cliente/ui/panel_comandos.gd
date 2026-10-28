## Formulario de comandos armado desde el catálogo: un control por parámetro
## (entero o lista de opciones) y un botón. Un comando nuevo en el núcleo
## aparece aquí sin código nuevo. Los reservados se muestran desactivados.
extends VBoxContainer

signal comando_pedido(cmd: Dictionary)
signal consulta_pedida(cmd: Dictionary)

const Desglose = preload("res://ui/desglose.gd")

var _resultado := Label.new()
var _pendientes := {}      # secuencia -> tipo de comando


func construir(comandos: Array) -> void:
	for h in get_children():
		if h != _resultado:
			h.queue_free()
	var titulo := Label.new()
	titulo.text = "Comandos"
	titulo.add_theme_font_size_override("font_size", 18)
	add_child(titulo)
	for c in comandos:
		add_child(_fila(c))
	if _resultado.get_parent() == null:
		add_child(_resultado)
	else:
		move_child(_resultado, get_child_count() - 1)
	_resultado.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_resultado.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_resultado.custom_minimum_size = Vector2(380, 0)


static func texto_requisito(c: Dictionary) -> String:
	var r: Dictionary = c.get("requiere", {})
	var eje := str(r.get("eje", "todo"))
	if eje == "todo":
		return ""
	var clase := "exclusivo: un solo titular" if r.get("clase", "exclusivo") == "exclusivo" else "concurrente: cualquier titular"
	return "Requiere autoridad de %s (%s)" % [eje, clase]


func _fila(c: Dictionary) -> Control:
	var fila := HBoxContainer.new()
	var nombre := Label.new()
	nombre.text = c["tipo"]
	nombre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# El requisito de autoridad solo se muestra si no es el de omisión, que el
	# soberano siempre cumple (V5, *Permiso y capacidad*).
	var req := texto_requisito(c)
	if req != "":
		nombre.text += " ◆"
		nombre.tooltip_text = req
		nombre.mouse_filter = Control.MOUSE_FILTER_PASS
	fila.add_child(nombre)
	var controles := {}
	for p in c["parametros"]:
		if p["tipo"] == "entero":
			var s := SpinBox.new()
			s.min_value = p["min"]
			s.max_value = p["max"]
			s.value = p["min"]
			s.allow_greater = true      # para poder probar que el núcleo rechaza
			s.allow_lesser = true
			s.tooltip_text = "%s (%d a %d)" % [p["nombre"], int(p["min"]), int(p["max"])]
			controles[p["nombre"]] = s
			fila.add_child(s)
		else:
			var o := OptionButton.new()
			for opcion in p["opciones"]:
				o.add_item(opcion)
			o.tooltip_text = p["nombre"]
			controles[p["nombre"]] = o
			fila.add_child(o)
	var consultar := Button.new()
	consultar.text = "?"
	consultar.tooltip_text = "ver el efecto hasta la siguiente veintena, sin aplicarlo"
	consultar.disabled = not c["implementado"]
	consultar.pressed.connect(func(): consulta_pedida.emit(_comando(c["tipo"], controles)))
	fila.add_child(consultar)
	var boton := Button.new()
	boton.text = "Enviar"
	boton.disabled = not c["implementado"]
	if not c["implementado"]:
		boton.tooltip_text = "reservado: aún no implementado"
	boton.pressed.connect(func(): comando_pedido.emit(_comando(c["tipo"], controles)))
	fila.add_child(boton)
	return fila


func _comando(tipo: String, controles: Dictionary) -> Dictionary:
	var cmd := {"tipo": tipo}
	for nombre in controles.keys():
		var ctl = controles[nombre]
		cmd[nombre] = int(ctl.value) if ctl is SpinBox else ctl.get_item_text(ctl.selected)
	return cmd


func enviado(secuencia: int, cmd: Dictionary) -> void:
	_pendientes[secuencia] = cmd["tipo"]
	_resultado.text = "enviado #%d: %s (se aplica en el siguiente día)" % [secuencia, cmd["tipo"]]


func rechazado(secuencia, motivo: String) -> void:
	var cual := "" if secuencia == null else " #%d %s" % [int(secuencia), _pendientes.get(int(secuencia), "")]
	_resultado.text = "rechazado%s: %s" % [cual, motivo]


func consultado(secuencia: int, cmd: Dictionary) -> void:
	_pendientes[secuencia] = cmd["tipo"]
	_resultado.text = "consultando %s…" % cmd["tipo"]


## Muestra la predicción: qué cambia, comparado con no dar el comando, al
## llegar a la siguiente veintena.
func prediccion(m: Dictionary, espejo) -> void:
	var tipo: String = _pendientes.get(int(m["secuencia"]), "")
	var lineas := ["%s, hasta el día %d:" % [tipo, int(m["horizonte"])]]
	if m["diferencias"].is_empty():
		lineas.append("  sin efecto visible")
	for d in m["diferencias"]:
		var antes: String = Desglose.valor(d["antes"]) if d["antes"] != null else "—"
		var despues: String = Desglose.valor(d["despues"]) if d["despues"] != null else "—"
		lineas.append("  %s · %s: %s → %s" % [espejo.nombre(espejo.clave(d["ref"])), d["nombre"], antes, despues])
	_resultado.text = "\n".join(lineas)
