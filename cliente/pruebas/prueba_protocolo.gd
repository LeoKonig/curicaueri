## Archivos dorados del protocolo, del lado del cliente:
## - los mensajes del núcleo se leen sin error y llenan el espejo;
## - los mensajes que arma el cliente coinciden con los dorados.
##   godot --headless --path cliente --script res://pruebas/prueba_protocolo.gd
extends SceneTree

const Espejo = preload("res://red/espejo.gd")
const Protocolo = preload("res://red/protocolo.gd")
const BarraSuperior = preload("res://ui/barra_superior.gd")
const PanelComandos = preload("res://ui/panel_comandos.gd")
const PanelDecisiones = preload("res://ui/panel_decisiones.gd")
const PanelCronica = preload("res://ui/panel_cronica.gd")
const PantallaInicio = preload("res://ui/pantalla_inicio.gd")
const PantallaFinal = preload("res://ui/pantalla_final.gd")
const Textos = preload("res://red/textos.gd")
const Comun = preload("res://pruebas/comun.gd")

var fallos := 0


func _comprobar(nombre: String, ok: bool) -> void:
	print(("  ✔ " if ok else "  ✘ ") + nombre)
	if not ok:
		fallos += 1


func _init() -> void:
	var dir := Comun.ruta_compartidas().path_join("protocolo")
	var leer = func(n): return Comun.leer_json(dir.path_join(n))
	var espejo = Espejo.new()
	for n in ["hola.json", "catalogo.json", "mapa.json", "instantanea.json", "cambios.json", "reloj.json", "error.json", "aviso.json", "prediccion.json", "decision.json", "decision_cantidad.json", "cronica.json"]:
		var m = leer.call(n)
		_comprobar("se lee " + n, m is Dictionary and m.has("tipo"))
		if m is Dictionary:
			espejo.recibir(m)
	_comprobar("el catálogo trae magnitudes y comandos", espejo.magnitudes.size() > 0 and espejo.comandos.size() > 0)
	_comprobar("el mapa trae ancho × alto celdas", espejo.mapa["celdas"].size() == int(espejo.mapa["ancho"]) * int(espejo.mapa["alto"]))
	_comprobar("el espejo tiene entidades tras instantánea y cambios", espejo.entidades.size() > 0)
	# reloj.json es el tick 365: 1 de enero de 1476, primer día de la veintena 1.
	var texto: String = BarraSuperior.texto_reloj(leer.call("reloj.json")["reloj"], espejo.calendario)
	var otro: String = BarraSuperior.texto_reloj(leer.call("reloj.json")["reloj"], {"nombre_periodo": "mes"})
	_comprobar("con otro calendario, la barra nombra sus periodos: " + otro, otro.contains("mes 1, día 1"))
	_comprobar("la barra entiende el reloj: " + texto, texto.contains("1 de enero de 1476") and texto.contains("veintena 1, día 1"))

	var panel = PanelComandos.new()
	root.add_child(panel)
	panel.construir(espejo.comandos)
	_comprobar("el formulario de comandos se arma desde el catálogo", panel.get_child_count() >= espejo.comandos.size())

	var redondo = func(m): return JSON.parse_string(JSON.stringify(m))
	_comprobar("hola coincide con el dorado", Comun.igual(redondo.call(Protocolo.hola()), leer.call("cliente_hola.json")))
	_comprobar("comando coincide con el dorado", Comun.igual(
		redondo.call(Protocolo.comando(7, {"tipo": "subir_impuesto", "aldea": 1, "valor": 5})), leer.call("cliente_comando.json")))
	_comprobar("pausa coincide con el dorado", Comun.igual(redondo.call(Protocolo.pausa(false)), leer.call("cliente_pausa.json")))
	_comprobar("velocidad coincide con el dorado", Comun.igual(redondo.call(Protocolo.velocidad(5)), leer.call("cliente_velocidad.json")))
	_comprobar("consulta coincide con el dorado", Comun.igual(
		redondo.call(Protocolo.consulta(8, {"tipo": "subir_impuesto", "aldea": 1, "valor": 5})), leer.call("cliente_consulta.json")))
	_comprobar("guardar coincide con el dorado", Comun.igual(redondo.call(Protocolo.guardar("partida1")), leer.call("cliente_guardar.json")))
	_comprobar("cargar coincide con el dorado", Comun.igual(redondo.call(Protocolo.cargar("partida1")), leer.call("cliente_cargar.json")))
	_comprobar("interés coincide con el dorado", Comun.igual(
		redondo.call(Protocolo.interes([Espejo.ref_de("aldea:1")])), leer.call("cliente_interes.json")))
	_comprobar("el catálogo trae las cinco velocidades", espejo.velocidades.size() == 5)
	_comprobar("el catálogo trae los ejes activos del escenario", espejo.ejes.size() == 2 and espejo.ejes[1]["id"] == "fe")
	var por_tipo := {}
	for c in espejo.comandos:
		por_tipo[c["tipo"]] = c
	_comprobar("el requisito por omisión no se muestra", PanelComandos.texto_requisito(por_tipo["subir_impuesto"]) == "")
	_comprobar("un requisito con eje se muestra con su clase: " + PanelComandos.texto_requisito(por_tipo["celebrar_fiesta"]),
		PanelComandos.texto_requisito(por_tipo["celebrar_fiesta"]).contains("fe") and PanelComandos.texto_requisito(por_tipo["celebrar_fiesta"]).contains("concurrente"))
	var pred = leer.call("prediccion.json")
	panel.consultado(8, {"tipo": "subir_impuesto"})
	panel.prediccion(pred, espejo)
	_comprobar("la predicción se muestra con el nombre de la entidad y el cambio", panel._resultado.text.contains("aldea 1") and panel._resultado.text.contains("52 → 57"))
	_comprobar("responder coincide con el dorado", Comun.igual(
		redondo.call(Protocolo.responder(9, 3, "resistir")), leer.call("cliente_responder.json")))
	_comprobar("el espejo guarda las dos decisiones pendientes", espejo.decisiones.size() == 2)
	var pd = PanelDecisiones.new()
	pd.espejo = espejo
	root.add_child(pd)
	pd.refrescar()
	var botones := pd.find_children("*", "Button", true, false)
	var selectores := pd.find_children("*", "SpinBox", true, false)
	_comprobar("el panel muestra un botón por opción y un selector para la cantidad", botones.size() == 3 and selectores.size() == 1)
	var pedidas := []
	pd.respuesta_pedida.connect(func(d, r): pedidas.append([d, r]))
	botones[0].pressed.emit()
	_comprobar("pulsar una opción pide responder con su id", pedidas.size() == 1 and pedidas[0][0] == 3 and pedidas[0][1] == "resistir")
	espejo.recibir(leer.call("decision_cerrada.json"))
	_comprobar("decision_cerrada la quita del espejo", espejo.decisiones.size() == 1 and espejo.decisiones.has(4))
	_probar_cronica_y_fin(leer, espejo)
	print("protocolo: %d fallos" % fallos)
	quit(1 if fallos > 0 else 0)


func _probar_cronica_y_fin(leer: Callable, espejo) -> void:
	_comprobar("«cronica» añade sus entradas al espejo", espejo.cronica.size() == 1 and espejo.cronica[0]["clave"] == "c.fase")
	espejo.recibir(leer.call("cronica.json"))
	_comprobar("una segunda «cronica» se añade a las anteriores", espejo.cronica.size() == 2)
	_comprobar("mientras se juega, el espejo no tiene fin", espejo.fin.is_empty())
	var panel = PanelCronica.new()
	panel.espejo = espejo
	root.add_child(panel)
	panel.refrescar()
	var etiquetas := panel.find_children("*", "Label", true, false)
	_comprobar("el panel muestra la fecha de cada entrada", etiquetas.any(func(l): return l.text.contains("1 de enero de 1476")))
	_comprobar("una clave sin texto se muestra con sus parámetros: " + PanelCronica.texto_de(espejo.cronica[0]),
		PanelCronica.texto_de(espejo.cronica[0]).contains("c.fase") and PanelCronica.texto_de(espejo.cronica[0]).contains("fase=frontera"))
	espejo.recibir(leer.call("fin.json"))
	_comprobar("«fin» guarda la razón y sustituye la crónica por la completa", espejo.fin.get("razon", "") == "fecha" and espejo.cronica.size() == 1)
	var inst = leer.call("instantanea.json")
	espejo.recibir(inst)
	_comprobar("una instantánea nueva borra la crónica y el fin (se cargó otra partida)", espejo.cronica.is_empty() and espejo.fin.is_empty())

	# Textos: el epígrafe y la apertura del libro son los que se pidieron.
	_comprobar("el epígrafe es el poema de Nezahualcóyotl",
		Textos.de("inicio.epigrafe").begins_with("¡En buen tiempo vinimos a vivir,") and Textos.de("inicio.epigrafe").ends_with("que se viva!"))
	_comprobar("la apertura del libro es la del Quijote",
		Textos.de("libro.apertura").begins_with("En un lugar de la Mancha") and Textos.de("libro.apertura").ends_with("más cierta en el mundo."))
	_comprobar("las plantillas sustituyen sus parámetros", Textos.formatear("{a} y {b}", {"a": 1, "b": "dos"}) == "1 y dos")

	# Pantalla de inicio: el epígrafe y un botón que la cierra y avisa.
	var inicio = PantallaInicio.new()
	root.add_child(inicio)
	inicio.construir()
	var comenzo := []
	inicio.comenzar.connect(func(): comenzo.append(true))
	_comprobar("la pantalla de inicio muestra el epígrafe",
		inicio.find_children("*", "Label", true, false).any(func(l): return l.text.contains("En buen tiempo vinimos a vivir")))
	inicio.boton.pressed.emit()
	_comprobar("«Comenzar» avisa y quita la pantalla", comenzo.size() == 1 and inicio.is_queued_for_deletion())

	# Pantalla final: sin el libro, no hay botón; con él, «Abrir» muestra el párrafo.
	var espejo_fin = Espejo.new()
	espejo_fin.recibir(leer.call("fin.json"))
	var sin_libro = PantallaFinal.new()
	sin_libro.espejo = espejo_fin
	root.add_child(sin_libro)
	sin_libro.construir()
	_comprobar("sin la copia en la crónica, la pantalla final no ofrece el libro", sin_libro.boton_abrir == null and not sin_libro.tiene_libro())
	_comprobar("el resumen dice la fecha y las entradas: " + sin_libro.resumen(),
		sin_libro.resumen().contains("1 de enero de 1476") and sin_libro.resumen().contains("1 entradas"))
	var cargas := []
	sin_libro.cargar_pedido.connect(func(): cargas.append(true))
	var botones_fin := sin_libro.find_children("*", "Button", true, false)
	botones_fin[0].pressed.emit()
	_comprobar("la pantalla final pide cargar una partida", botones_fin.size() == 1 and cargas.size() == 1)

	espejo_fin.cronica.append({"tick": 400, "fecha": {"anio": 1607, "mes": 12, "dia": 1, "calendario": "juliano"},
		"tipo": "copia_pedida", "entidades": [], "clave": "cronica.copia_pedida", "params": {}})
	var con_libro = PantallaFinal.new()
	con_libro.espejo = espejo_fin
	root.add_child(con_libro)
	con_libro.construir()
	_comprobar("con la copia en la crónica, ofrece abrir el libro", con_libro.boton_abrir != null and con_libro.tiene_libro())
	_comprobar("el libro empieza cerrado", not con_libro.texto_libro.visible)
	con_libro.boton_abrir.pressed.emit()
	_comprobar("abrirlo muestra el párrafo del Quijote",
		con_libro.texto_libro.visible and con_libro.texto_libro.text.begins_with("En un lugar de la Mancha"))
