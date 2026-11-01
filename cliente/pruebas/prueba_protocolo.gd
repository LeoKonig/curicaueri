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
	for n in ["hola.json", "catalogo.json", "mapa.json", "instantanea.json", "cambios.json", "reloj.json", "error.json", "aviso.json", "prediccion.json", "decision.json", "decision_cantidad.json"]:
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
	print("protocolo: %d fallos" % fallos)
	quit(1 if fallos > 0 else 0)
