## El mapa: una malla hexagonal (ArrayMesh, colores planos por terreno) y los
## altépetl encima. El núcleo da el grafo y los terrenos; la geometría es del
## cliente. Hexágonos con punta arriba y filas impares desplazadas a la
## derecha, la misma convención que el proveedor hexagonal del núcleo.
extends Control

signal seleccion(clave: String)

const COLORES := {
	"llano": Color("#c9b97a"), "bosque": Color("#5f7f4a"),
	"sierra": Color("#8a7d6b"), "lago": Color("#4f7fa8"),
}

var espejo
var tam := 24.0                 # radio del hexágono en píxeles
var seleccionado := ""
var _malla: ArrayMesh
var _margen := Vector2(30, 30)
var zoom := 1.0                 # rueda del ratón
var desplazamiento := Vector2.ZERO   # arrastrar con el botón derecho o el central
var celdas_dibujadas := 0


func centro_celda(id: int) -> Vector2:
	var ancho := int(espejo.mapa["ancho"])
	var col := id % ancho
	var fila := id / ancho
	var x := tam * sqrt(3.0) * (col + 0.5 * (fila & 1))
	var y := tam * 1.5 * fila
	return _margen + Vector2(x, y)


func _ready() -> void:
	resized.connect(_ajustar)


## Elige el tamaño del hexágono para que el mapa llene el espacio disponible.
func _ajustar() -> void:
	if espejo == null or espejo.mapa.is_empty():
		return
	var ancho := int(espejo.mapa["ancho"])
	var alto := int(espejo.mapa["alto"])
	var util := size - _margen * 2
	var nuevo := minf(util.x / (sqrt(3.0) * (ancho + 0.5)), util.y / (1.5 * alto + 0.5))
	if nuevo > 4.0 and absf(nuevo - tam) > 0.5:
		tam = nuevo
		construir()


func construir() -> void:
	var vertices := PackedVector2Array()
	var colores := PackedColorArray()
	for c in espejo.mapa["celdas"]:
		var centro := centro_celda(int(c["id"]))
		var color: Color = COLORES.get(c["terreno"], Color.MAGENTA)
		for k in 6:
			var a := deg_to_rad(60.0 * k - 30.0)
			var b := deg_to_rad(60.0 * (k + 1) - 30.0)
			vertices.append_array([centro, centro + Vector2(cos(a), sin(a)) * (tam - 1.0), centro + Vector2(cos(b), sin(b)) * (tam - 1.0)])
			colores.append_array([color, color.darkened(0.06), color.darkened(0.06)])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colores
	_malla = ArrayMesh.new()
	_malla.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	celdas_dibujadas = espejo.mapa["celdas"].size()
	queue_redraw()


func _draw() -> void:
	if espejo == null or _malla == null:
		return
	# Toda la malla en una sola llamada de dibujo, con la transformación del zoom.
	draw_set_transform(desplazamiento, 0.0, Vector2(zoom, zoom))
	draw_mesh(_malla, null)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	# Los altépetl y sus nombres se dibujan en coordenadas de pantalla, para que
	# sigan legibles con cualquier zoom.
	var fuente := ThemeDB.fallback_font
	for e in espejo.de_clase("altepetl"):
		var campos: Dictionary = e["campos"]
		if not campos.has("celda"):
			continue
		var p := a_pantalla(centro_celda(int(campos["celda"]["v"])))
		var clave: String = espejo.clave(e["ref"])
		var radio := maxf(tam * zoom * 0.45, 7.0)
		if clave == seleccionado:
			draw_circle(p, radio + 4.0, Color.WHITE)
		draw_circle(p, radio, Color("#7a2e1f"))
		var nombre: String = campos["nombre"]["v"] if campos.has("nombre") else clave
		var ancho_texto := fuente.get_string_size(nombre, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var base := p + Vector2(-ancho_texto / 2.0, radio + 18.0)
		draw_string_outline(fuente, base, nombre, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(1, 1, 1, 0.8))
		draw_string(fuente, base, nombre, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#2a241c"))


func a_pantalla(p: Vector2) -> Vector2:
	return desplazamiento + p * zoom


func _gui_input(evento: InputEvent) -> void:
	if evento is InputEventMouseButton and evento.pressed and evento.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		# Zoom alrededor del cursor: el punto bajo el ratón se queda quieto.
		var factor := 1.15 if evento.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15
		var nuevo := clampf(zoom * factor, 0.5, 8.0)
		desplazamiento = evento.position - (evento.position - desplazamiento) * (nuevo / zoom)
		zoom = nuevo
		queue_redraw()
		accept_event()
		return
	if evento is InputEventMouseMotion and (evento.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE)) != 0:
		desplazamiento += evento.relative
		queue_redraw()
		accept_event()
		return
	if evento is InputEventMouseButton and evento.pressed and evento.button_index == MOUSE_BUTTON_LEFT:
		var mejor := ""
		var distancia := maxf(tam * zoom, 10.0)
		for e in espejo.de_clase("altepetl"):
			if not e["campos"].has("celda"):
				continue
			var d: float = a_pantalla(centro_celda(int(e["campos"]["celda"]["v"]))).distance_to(evento.position)
			if d < distancia:
				distancia = d
				mejor = espejo.clave(e["ref"])
		if mejor != "":
			seleccionado = mejor
			queue_redraw()
			seleccion.emit(mejor)
