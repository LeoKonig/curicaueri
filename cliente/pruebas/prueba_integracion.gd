## Prueba de punta a punta con el núcleo real, que debe estar escuchando:
##   nucleo --puerto 4790 &
##   godot --headless --path cliente --script res://pruebas/prueba_integracion.gd -- --puerto 4790
## Saluda, recibe catálogo, mapa e instantánea, quita la pausa a la velocidad
## máxima, manda un comando válido y uno inválido, y espera a la veintena 2.
extends SceneTree

const Conexion = preload("res://red/conexion.gd")
const Espejo = preload("res://red/espejo.gd")
const Protocolo = preload("res://red/protocolo.gd")

var conexion
var espejo = Espejo.new()
var tiempo := 0.0
var fase := "conectando"
var sec_invalido := -1
var rechazos := []
var discrepancias := []
var vistos := {}
var sec_consulta := -1
var prediccion := {}
var avisos := []
var tick_guardado := -1
var instantaneas := 0


func _init() -> void:
	conexion = Conexion.new()
	var a := OS.get_cmdline_user_args()
	var i := a.find("--puerto")
	conexion.puerto = int(a[i + 1]) if i != -1 and i + 1 < a.size() else 4646
	root.add_child(conexion)
	conexion.mensaje.connect(_al_recibir)


func _al_recibir(m: Dictionary) -> void:
	espejo.recibir(m)
	vistos[m["tipo"]] = true
	match m["tipo"]:
		"instantanea":
			instantaneas += 1
			if fase == "conectando":
				fase = "corriendo"
				sec_consulta = conexion.enviar_consulta({"tipo": "fijar_impuesto_interno", "valor": 5})
				conexion.enviar_comando({"tipo": "fijar_impuesto_interno", "valor": 5})
				sec_invalido = conexion.enviar_comando({"tipo": "fijar_impuesto_interno", "valor": 9})
				conexion.enviar(Protocolo.velocidad(5))
				conexion.enviar(Protocolo.pausa(false))
		"cambios":
			for e in m["actualizadas"]:
				discrepancias.append_array(espejo.verificar(e))
		"error":
			rechazos.append(m)
		"prediccion":
			if int(m["secuencia"]) == sec_consulta:
				prediccion = m
		"aviso":
			avisos.append(m["texto"])
			if m["texto"].begins_with("partida guardada"):
				conexion.enviar(Protocolo.cargar("integracion"))
		"reloj":
			if fase == "guardando" and m["reloj"]["pausado"]:
				tick_guardado = int(m["reloj"]["tick"])
				conexion.enviar(Protocolo.guardar("integracion"))


func _process(delta: float) -> bool:
	tiempo += delta
	if fase == "corriendo" and int(espejo.reloj.get("periodo", 0)) >= 2:
		fase = "guardando"
		conexion.enviar(Protocolo.pausa(true))
	var listo: bool = fase == "guardando" and avisos.any(func(a): return a.begins_with("partida cargada"))
	if listo or tiempo > 25.0:
		_terminar(listo)
	return false


func _terminar(listo: bool) -> void:
	var fallos := []
	if not listo:
		fallos.append("no se completó el recorrido en 25 s (fase: %s, avisos: %s)" % [fase, avisos])
	for t in ["hola", "catalogo", "mapa", "instantanea", "cambios", "reloj"]:
		if not vistos.has(t):
			fallos.append("no llegó el mensaje " + t)
	if espejo.de_clase("altepetl").size() != 3:
		fallos.append("se esperaban 3 altépetl en el espejo")
	if not rechazos.any(func(r): return r["secuencia"] != null and int(r["secuencia"]) == sec_invalido):
		fallos.append("el comando inválido no fue rechazado con su secuencia")
	if prediccion.is_empty():
		fallos.append("no llegó la predicción de la consulta")
	elif not prediccion["diferencias"].any(func(d): return d["nombre"] == "agravio"):
		fallos.append("la predicción de subir el impuesto no muestra el agravio")
	if instantaneas < 2:
		fallos.append("cargar la partida no envió una instantánea nueva")
	if int(espejo.reloj.get("tick", -1)) != tick_guardado:
		fallos.append("tras cargar, el reloj está en %s y se guardó en %d" % [espejo.reloj.get("tick"), tick_guardado])
	if rechazos.size() != 1:
		fallos.append("se esperaba exactamente 1 rechazo, hubo %d" % rechazos.size())
	fallos.append_array(discrepancias)
	for f in fallos:
		print("  ✘ ", f)
	if fallos.is_empty():
		print("  ✔ catálogo, mapa e instantánea recibidos; 3 altépetl en el espejo")
		print("  ✔ el comando inválido fue rechazado con su secuencia; el válido no")
		print("  ✔ el reloj llegó a la veintena 2 (%s)" % JSON.stringify(espejo.reloj["fecha"]))
		print("  ✔ el espejo recalcula cada valor efectivo igual que el núcleo")
		print("  ✔ la consulta predijo %d cambios hasta el día %d" % [prediccion["diferencias"].size(), int(prediccion["horizonte"])])
		print("  ✔ guardar en pausa y cargar devuelven la partida al día %d" % tick_guardado)
	print("integración: %d fallos" % fallos.size())
	quit(1 if not fallos.is_empty() else 0)
