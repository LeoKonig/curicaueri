## Pantalla del fin de la partida: la razón, el resumen, la crónica completa y,
## si la crónica cuenta que llegó el libro, el libro con la opción de abrirlo.
## Lee el espejo; lo único que puede pedir es cargar otra partida.
extends ColorRect

const BarraSuperior = preload("res://ui/barra_superior.gd")
const PanelCronica = preload("res://ui/panel_cronica.gd")
const Textos = preload("res://red/textos.gd")

signal cargar_pedido

## La entrada de la crónica que cuenta la llegada del libro.
const CLAVE_LIBRO := "cronica.copia_obtenida"

var _construida := false
var espejo
var boton_abrir: Button = null
var texto_libro := Label.new()


func _ready() -> void:
	construir()


## Arma la pantalla (una sola vez). Se llama sola al entrar al árbol; las
## pruebas sin escena la llaman a mano.
func construir() -> void:
	if _construida:
		return
	_construida = true
	color = Color("#efe7d6")   # opaco: el texto hereda el tema oscuro sobre claro de la escena
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var margen := MarginContainer.new()
	margen.set_anchors_preset(Control.PRESET_FULL_RECT)
	for lado in ["left", "right", "top", "bottom"]:
		margen.add_theme_constant_override("margin_" + lado, 40)
	add_child(margen)
	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 12)
	margen.add_child(caja)

	var titulo := _linea(Textos.de("fin.titulo"))
	titulo.add_theme_font_size_override("font_size", 30)
	caja.add_child(titulo)
	caja.add_child(_linea(Textos.de("fin.razon." + str(espejo.fin.get("razon", "")))))
	caja.add_child(_linea(resumen()))

	if tiene_libro():
		caja.add_child(HSeparator.new())
		caja.add_child(_linea(Textos.de("libro.titulo")))
		boton_abrir = Button.new()
		boton_abrir.text = Textos.de("libro.abrir")
		boton_abrir.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		boton_abrir.pressed.connect(_abrir_libro)
		caja.add_child(boton_abrir)
		texto_libro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		texto_libro.visible = false
		caja.add_child(texto_libro)

	caja.add_child(HSeparator.new())
	caja.add_child(_linea(Textos.de("fin.cronica")))
	var desplazamiento := ScrollContainer.new()
	desplazamiento.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	desplazamiento.size_flags_vertical = Control.SIZE_EXPAND_FILL
	caja.add_child(desplazamiento)
	var cronica := PanelCronica.new()
	cronica.espejo = espejo
	cronica.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desplazamiento.add_child(cronica)
	cronica.refrescar()

	var cargar := Button.new()
	cargar.text = Textos.de("fin.cargar")
	cargar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	cargar.pressed.connect(func(): cargar_pedido.emit())
	caja.add_child(cargar)


func _linea(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func resumen() -> String:
	var r: Dictionary = espejo.reloj
	return Textos.de("fin.resumen", {
		"fecha": BarraSuperior.texto_fecha(r["fecha"]) if r.has("fecha") else "?",
		"dias": int(r.get("tick", 0)),
		"entradas": espejo.cronica.size()})


func tiene_libro() -> bool:
	for e in espejo.cronica:
		if e["clave"] == CLAVE_LIBRO:
			return true
	return false


func _abrir_libro() -> void:
	texto_libro.text = Textos.de("libro.apertura") + "\n\n" + Textos.de("libro.cierre")
	texto_libro.visible = true
	boton_abrir.disabled = true
