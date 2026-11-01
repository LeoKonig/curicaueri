## Pantalla de inicio: el epígrafe del juego, hasta que el jugador pulsa
## «Comenzar». Cubre la ventana; el núcleo sigue conectando por debajo, en pausa.
extends ColorRect

const Textos = preload("res://red/textos.gd")

signal comenzar

var boton := Button.new()


func _ready() -> void:
	color = Color("#2a241c")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var centro := CenterContainer.new()
	centro.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centro)
	var caja := VBoxContainer.new()
	caja.custom_minimum_size = Vector2(620, 0)
	caja.add_theme_constant_override("separation", 22)
	centro.add_child(caja)
	var poema := Label.new()
	poema.text = Textos.de("inicio.epigrafe")
	poema.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	poema.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	poema.add_theme_font_size_override("font_size", 26)
	poema.add_theme_color_override("font_color", Color("#efe7d6"))
	caja.add_child(poema)
	var fuente := Label.new()
	fuente.text = Textos.de("inicio.fuente")
	fuente.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fuente.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fuente.add_theme_font_size_override("font_size", 14)
	fuente.add_theme_color_override("font_color", Color("#b9ad94"))
	caja.add_child(fuente)
	boton.text = Textos.de("inicio.comenzar")
	boton.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	boton.pressed.connect(func():
		comenzar.emit()
		queue_free())
	caja.add_child(boton)
