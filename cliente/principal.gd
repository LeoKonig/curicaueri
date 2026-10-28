## Escena principal: arma la interfaz, conecta con el núcleo y reparte los
## mensajes. Argumentos (después de "--" en la línea de órdenes de Godot):
##   --puerto N           puerto del núcleo (4646 por omisión)
##   --lanzar-nucleo RUTA arranca el ejecutable del núcleo antes de conectar
extends Control

const Conexion = preload("res://red/conexion.gd")
const Espejo = preload("res://red/espejo.gd")
const LienzoMapa = preload("res://mapa/lienzo_mapa.gd")
const BarraSuperior = preload("res://ui/barra_superior.gd")
const PanelEntidad = preload("res://ui/panel_entidad.gd")
const PanelComandos = preload("res://ui/panel_comandos.gd")
const PanelDecisiones = preload("res://ui/panel_decisiones.gd")

var espejo = Espejo.new()
var conexion
var barra
var lienzo
var panel
var comandos
var decisiones
var estado := Label.new()
var informe := Label.new()      # informe de veintena, no modal
var pestanas: TabContainer
var _numeros_veintena := {}     # valores al empezar la veintena anterior
var _veintena_actual := -1
# Vigilar que no se sienta por turnos (V5): cuánto tiempo pasa el jugador en pausa.
var segundos_en_pausa := 0.0
var segundos_jugando := 0.0
var depurar := true            # recalcula cada valor efectivo y avisa si no cuadra


func _ready() -> void:
	var args := _argumentos()
	conexion = Conexion.new()
	conexion.puerto = int(args.get("puerto", "4646"))
	if args.has("lanzar-nucleo"):
		var pid := OS.create_process(args["lanzar-nucleo"], ["--puerto", str(conexion.puerto)])
		estado.text = "núcleo lanzado (pid %d)" % pid
	add_child(conexion)
	conexion.mensaje.connect(_al_recibir)
	conexion.estado_cambiado.connect(func(t): estado.text = t)
	_armar_interfaz()


func _armar_interfaz() -> void:
	var fondo := ColorRect.new()
	fondo.color = Color("#efe7d6")
	fondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(fondo)
	# Texto oscuro sobre el fondo claro (el tema por omisión de Godot es claro sobre oscuro).
	var tema := Theme.new()
	tema.set_color("font_color", "Label", Color("#2a241c"))
	theme = tema
	var raiz := VBoxContainer.new()
	raiz.set_anchors_preset(Control.PRESET_FULL_RECT)
	raiz.add_theme_constant_override("separation", 6)
	add_child(raiz)

	barra = BarraSuperior.new()
	barra.pausa_pedida.connect(func(v): conexion.enviar(preload("res://red/protocolo.gd").pausa(v)))
	barra.velocidad_pedida.connect(func(v): conexion.enviar(preload("res://red/protocolo.gd").velocidad(v)))
	barra.guardar_pedido.connect(func(n): conexion.enviar(preload("res://red/protocolo.gd").guardar(n)))
	barra.cargar_pedido.connect(func(n): conexion.enviar(preload("res://red/protocolo.gd").cargar(n)))
	raiz.add_child(barra)

	var cuerpo := HSplitContainer.new()
	cuerpo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	raiz.add_child(cuerpo)

	lienzo = LienzoMapa.new()
	lienzo.espejo = espejo
	lienzo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lienzo.seleccion.connect(func(c): panel.mostrar(c))
	cuerpo.add_child(lienzo)

	# A la derecha, pestañas: así cada panel tiene toda la altura.
	var lateral := VBoxContainer.new()
	lateral.custom_minimum_size = Vector2(440, 0)
	cuerpo.add_child(lateral)
	pestanas = TabContainer.new()
	pestanas.tab_changed.connect(func(i):
		if i == 2: pestanas.set_tab_title(2, "Informe")
		if i == 3: pestanas.set_tab_title(3, "Decisiones"))
	pestanas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lateral.add_child(pestanas)

	var desplazamiento_panel := ScrollContainer.new()
	desplazamiento_panel.name = "Entidad"
	desplazamiento_panel.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pestanas.add_child(desplazamiento_panel)
	panel = PanelEntidad.new()
	panel.espejo = espejo
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desplazamiento_panel.add_child(panel)
	panel.refrescar()

	var desplazamiento_comandos := ScrollContainer.new()
	desplazamiento_comandos.name = "Comandos"
	desplazamiento_comandos.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pestanas.add_child(desplazamiento_comandos)
	comandos = PanelComandos.new()
	comandos.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	comandos.comando_pedido.connect(func(cmd): comandos.enviado(conexion.enviar_comando(cmd), cmd))
	comandos.consulta_pedida.connect(func(cmd): comandos.consultado(conexion.enviar_consulta(cmd), cmd))
	desplazamiento_comandos.add_child(comandos)

	var desplazamiento_informe := ScrollContainer.new()
	desplazamiento_informe.name = "Informe"
	desplazamiento_informe.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pestanas.add_child(desplazamiento_informe)
	informe.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	informe.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	informe.text = "El informe de cada veintena aparecerá aquí, sin detener el juego."
	desplazamiento_informe.add_child(informe)

	var desplazamiento_decisiones := ScrollContainer.new()
	desplazamiento_decisiones.name = "Decisiones"
	desplazamiento_decisiones.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pestanas.add_child(desplazamiento_decisiones)
	decisiones = PanelDecisiones.new()
	decisiones.espejo = espejo
	decisiones.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	decisiones.respuesta_pedida.connect(func(d, r): conexion.enviar_respuesta(d, r))
	desplazamiento_decisiones.add_child(decisiones)
	decisiones.refrescar()

	var partida := VBoxContainer.new()
	partida.name = "Partida"
	pestanas.add_child(partida)
	partida.add_child(barra.controles_partida())
	lateral.add_child(estado)


func _process(delta: float) -> void:
	if espejo.reloj.is_empty() or not conexion.conectado():
		return
	if espejo.reloj["pausado"]:
		segundos_en_pausa += delta
	else:
		segundos_jugando += delta


func porcentaje_en_pausa() -> float:
	var total := segundos_en_pausa + segundos_jugando
	return 0.0 if total <= 0.0 else 100.0 * segundos_en_pausa / total


func _al_recibir(m: Dictionary) -> void:
	espejo.recibir(m)
	match m.get("tipo", ""):
		"hola":
			estado.text = "núcleo listo (protocolo v%d)" % int(m["version"])
		"catalogo":
			comandos.construir(espejo.comandos)
			barra.velocidades = espejo.velocidades
			barra.calendario = espejo.calendario
		"mapa":
			lienzo.construir()
			lienzo._ajustar()
		"instantanea", "cambios":
			barra.actualizar(espejo.reloj)
			lienzo.queue_redraw()
			if m["tipo"] == "instantanea" or not m["actualizadas"].is_empty() or not m["eliminadas"].is_empty():
				panel.refrescar()
			if depurar:
				_verificar(m)
			_informe_de_veintena(m["tipo"] == "instantanea")
			if m["tipo"] == "instantanea":
				decisiones.refrescar()
		"reloj":
			barra.actualizar(espejo.reloj)
		"error":
			comandos.rechazado(m["secuencia"], m["motivo"])
		"prediccion":
			comandos.prediccion(m, espejo)
		"aviso":
			estado.text = m["texto"]
		"decision", "decision_cerrada":
			decisiones.refrescar()
			# Como el informe: se marca la pestaña, no se detiene el juego.
			if m["tipo"] == "decision" and pestanas.current_tab != 3:
				pestanas.set_tab_title(3, "Decisiones •")


## Al cerrar una veintena, resume lo que cambió desde la anterior: los mayores
## cambios de magnitudes y campos numéricos. No detiene el juego (V5, *Informe
## de veintena no modal*). Es genérico: no sabe qué es el tesoro ni el agravio.
func _informe_de_veintena(reinicio: bool) -> void:
	var r: Dictionary = espejo.reloj
	var v := -1 if r["fuera_de_periodo"] else int(r["periodo"])
	if reinicio:
		_numeros_veintena = espejo.numeros()
		_veintena_actual = v
		return
	if v == _veintena_actual or v == -1:
		return
	var ahora: Dictionary = espejo.numeros()
	var cambios := []
	for k in ahora.keys():
		if _numeros_veintena.has(k) and not is_equal_approx(ahora[k], _numeros_veintena[k]):
			cambios.append([absf(ahora[k] - _numeros_veintena[k]), k, _numeros_veintena[k], ahora[k]])
	cambios.sort_custom(func(a, b): return a[0] > b[0])
	var lineas := ["Informe de la %s %d (%d cambios) · en esta sesión, %d %% del tiempo en pausa:" % [espejo.calendario.get("nombre_periodo", "periodo"), _veintena_actual if _veintena_actual > 0 else int(espejo.calendario.get("periodos_por_anio", 0)), cambios.size(), int(porcentaje_en_pausa())]]
	for c in cambios.slice(0, 6):
		var partes: PackedStringArray = c[1].split("|")
		lineas.append("  %s · %s: %s → %s" % [espejo.nombre(partes[0]), partes[1], String.num(c[2], 1), String.num(c[3], 1)])
	informe.text = "\n".join(lineas)
	# Avisa sin interrumpir: la pestaña se marca hasta que el jugador la mira.
	if pestanas.current_tab != 2:
		pestanas.set_tab_title(2, "Informe •")
	_numeros_veintena = ahora
	_veintena_actual = v


func _verificar(m: Dictionary) -> void:
	var lista: Array = m["entidades"] if m["tipo"] == "instantanea" else m["actualizadas"]
	for e in lista:
		for error in espejo.verificar(e):
			push_warning("espejo: " + error)


func _argumentos() -> Dictionary:
	var r := {}
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		if a[i].begins_with("--"):
			var nombre: String = a[i].substr(2)
			if i + 1 < a.size() and not a[i + 1].begins_with("--"):
				r[nombre] = a[i + 1]
				i += 1
			else:
				r[nombre] = "sí"
		i += 1
	return r
