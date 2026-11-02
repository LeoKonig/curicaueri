## Barra superior: fecha europea, veintena, días que faltan, velocidad y pausa.
extends HBoxContainer

signal pausa_pedida(valor: bool)
signal velocidad_pedida(valor: int)
signal guardar_pedido(nombre: String)
signal cargar_pedido(nombre: String)

const MESES := ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio",
	"agosto", "septiembre", "octubre", "noviembre", "diciembre"]

var _fecha := Label.new()
var _estado := Label.new()
var _boton_pausa := Button.new()
var _reloj := {}
var _progreso := ProgressBar.new()
var _nombre_partida := LineEdit.new()
var velocidades := []      # ms por día, del catálogo
var calendario := {}       # nombres y longitudes de los periodos, del catálogo


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	_fecha.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fecha.text = "esperando al núcleo…"
	add_child(_fecha)
	# El día se ve pasar: la barra avanza cada día hacia la siguiente veintena.
	_progreso.custom_minimum_size = Vector2(120, 0)
	_progreso.max_value = 20
	_progreso.show_percentage = false
	_progreso.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_progreso.tooltip_text = "días de la veintena en curso"
	add_child(_progreso)
	add_child(_estado)
	var lenta := Button.new()
	lenta.text = "−"
	lenta.tooltip_text = "más lento"
	lenta.pressed.connect(func(): _cambiar_velocidad(-1))
	add_child(lenta)
	_boton_pausa.text = "▶"
	_boton_pausa.custom_minimum_size = Vector2(40, 0)
	_boton_pausa.pressed.connect(func(): pausa_pedida.emit(not _reloj.get("pausado", true)))
	add_child(_boton_pausa)
	var rapida := Button.new()
	rapida.text = "+"
	rapida.tooltip_text = "más rápido"
	rapida.pressed.connect(func(): _cambiar_velocidad(1))
	add_child(rapida)


## Controles para guardar y cargar, que la escena coloca donde quepan (la
## pestaña "Partida"); emiten las señales de esta barra.
func controles_partida() -> Control:
	var caja := HBoxContainer.new()
	_nombre_partida.text = "partida1"
	_nombre_partida.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_nombre_partida.tooltip_text = "nombre de la partida (letras, dígitos, - y _)"
	caja.add_child(_nombre_partida)
	var guardar := Button.new()
	guardar.text = "Guardar"
	guardar.pressed.connect(func(): guardar_pedido.emit(_nombre_partida.text))
	caja.add_child(guardar)
	var cargar := Button.new()
	cargar.text = "Cargar"
	cargar.pressed.connect(func(): cargar_pedido.emit(_nombre_partida.text))
	caja.add_child(cargar)
	return caja


func _cambiar_velocidad(d: int) -> void:
	velocidad_pedida.emit(clampi(int(_reloj.get("velocidad", 3)) + d, 1, 5))


func actualizar(reloj: Dictionary) -> void:
	_reloj = reloj
	_fecha.text = texto_reloj(reloj, calendario)
	var v := int(reloj["velocidad"])
	var segundos := ""
	if v >= 1 and v <= velocidades.size():
		var dias := float(calendario.get("dias_por_periodo", 20))
		segundos = " (%s s por %s)" % [String.num(dias * float(velocidades[v - 1]) / 1000.0, 0), calendario.get("nombre_periodo", "periodo")]
	_estado.text = "velocidad %d%s%s" % [v, segundos, " · en pausa" if reloj["pausado"] else ""]
	_progreso.max_value = int(calendario.get("dias_fuera", 5)) if reloj["fuera_de_periodo"] else int(calendario.get("dias_por_periodo", 20))
	_progreso.value = int(reloj["dia"])
	_boton_pausa.text = "▶" if reloj["pausado"] else "⏸"


## «1 de enero de 1476 (juliano)», a partir de la fecha del protocolo.
static func texto_fecha(f: Dictionary) -> String:
	return "%d de %s de %d (%s)" % [int(f["dia"]), MESES[int(f["mes"]) - 1], int(f["anio"]), f["calendario"]]


## El calendario viene del catálogo: "veintena" y "nemontemi" en el prototipo,
## "mes" o "semana" en otra época, sin cambiar este código.
static func texto_reloj(reloj: Dictionary, calendario: Dictionary = {}) -> String:
	var fecha := texto_fecha(reloj["fecha"])
	var periodo: String
	if reloj["fuera_de_periodo"]:
		periodo = "%s, día %d" % [calendario.get("nombre_fuera", "fuera de periodo"), int(reloj["dia"])]
	else:
		periodo = "%s %d, día %d" % [calendario.get("nombre_periodo", "periodo"), int(reloj["periodo"]), int(reloj["dia"])]
	var faltan := int(reloj["dias_para_periodo"])
	return "%s · %s · %s" % [fecha, periodo, "falta 1 día" if faltan == 1 else "faltan %d días" % faltan]
