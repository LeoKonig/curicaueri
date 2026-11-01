## La crónica del reino (V5, *La crónica del reino*): lo que ha pasado, de lo
## más reciente a lo más antiguo, con su fecha. Genérico: cada entrada trae la
## clave de localización que dice cómo contarla y sus parámetros; no sabe qué
## es una fase ni una sucesión. Solo lee el espejo.
extends VBoxContainer

const BarraSuperior = preload("res://ui/barra_superior.gd")
const Textos = preload("res://red/textos.gd")

var espejo


func refrescar() -> void:
	for h in get_children():
		h.queue_free()
	if espejo == null or espejo.cronica.is_empty():
		var vacio := Label.new()
		vacio.text = Textos.de("cronica.vacia")
		add_child(vacio)
		return
	for i in range(espejo.cronica.size() - 1, -1, -1):
		var e: Dictionary = espejo.cronica[i]
		var fecha := Label.new()
		fecha.text = BarraSuperior.texto_fecha(e["fecha"])
		fecha.add_theme_font_size_override("font_size", 13)
		fecha.modulate = Color(1, 1, 1, 0.65)
		add_child(fecha)
		var texto := Label.new()
		texto.text = texto_de(e)
		texto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		texto.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_child(texto)
		add_child(HSeparator.new())


## Cómo se cuenta una entrada: su clave de localización con sus parámetros.
static func texto_de(e: Dictionary) -> String:
	return Textos.de(str(e["clave"]), e.get("params", {}))
