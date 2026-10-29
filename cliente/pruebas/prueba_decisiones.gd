## Decisiones de punta a punta con el núcleo real, lanzado con un guion que
## presenta una situación enseguida:
##   nucleo --puerto 4791 --guion pruebas_compartidas/guion_integracion.json &
##   godot --headless --path cliente --script res://pruebas/prueba_decisiones.gd -- --puerto 4791
## Espera la decisión, guarda la partida con la decisión pendiente, la carga
## y comprueba que el núcleo vuelve a mandar esa misma decisión. Después manda
## una respuesta inválida (debe volver un error con su secuencia), luego una
## válida, y espera "decision_cerrada".
extends SceneTree

const Conexion = preload("res://red/conexion.gd")
const Espejo = preload("res://red/espejo.gd")
const Protocolo = preload("res://red/protocolo.gd")

var conexion
var espejo = Espejo.new()
var tiempo := 0.0
var decision := {}
var sec_invalida := -1
var sec_valida := -1
var errores := []
var cerrada := false
var hechos := []
var fase := "inicial"
var id_guardada := -1
var reenviada := false


func _init() -> void:
	conexion = Conexion.new()
	var a := OS.get_cmdline_user_args()
	var i := a.find("--puerto")
	conexion.puerto = int(a[i + 1]) if i != -1 and i + 1 < a.size() else 4646
	root.add_child(conexion)
	conexion.mensaje.connect(_al_recibir)


func _al_recibir(m: Dictionary) -> void:
	espejo.recibir(m)
	match m["tipo"]:
		"instantanea":
			if fase == "inicial":
				conexion.enviar(Protocolo.velocidad(5))
				conexion.enviar(Protocolo.pausa(false))
			elif fase == "cargando":
				fase = "cargando_decision"
		"decision":
			if fase == "inicial":
				decision = m
				id_guardada = int(m["id"])
				conexion.enviar(Protocolo.guardar("decisiones"))
				fase = "guardando"
			elif fase == "cargando_decision" and int(m["id"]) == id_guardada:
				reenviada = true
				sec_invalida = conexion.enviar_respuesta(int(m["id"]), "no_existe")
				sec_valida = conexion.enviar_respuesta(int(m["id"]), str(m["pregunta"]["opciones"][1]))
				conexion.enviar(Protocolo.pausa(false))
				fase = "respondiendo"
		"aviso":
			if fase == "guardando" and m["texto"].begins_with("partida guardada"):
				conexion.enviar(Protocolo.cargar("decisiones"))
				fase = "cargando"
		"error":
			errores.append(m)
		"decision_cerrada":
			if not decision.is_empty() and int(m["id"]) == int(decision["id"]):
				cerrada = true
		"cambios":
			for h in m["hechos"]:
				if h["tipo"] in ["situacion", "situacion_resuelta"]:
					hechos.append(h["tipo"])


func _process(delta: float) -> bool:
	tiempo += delta
	if cerrada or tiempo > 20.0:
		_terminar()
	return false


func _terminar() -> void:
	var fallos := []
	if decision.is_empty():
		fallos.append("no llegó ninguna decisión en 20 s")
	else:
		if int(decision["id"]) != id_guardada:
			fallos.append("la decisión reenviada tiene otro id")
		if not reenviada:
			fallos.append("la decisión pendiente no se reenvió tras cargar la partida")
		if decision["tipo_situacion"] != "prueba":
			fallos.append("tipo de situación inesperado: %s" % decision["tipo_situacion"])
		if not errores.any(func(e): return e["secuencia"] != null and int(e["secuencia"]) == sec_invalida):
			fallos.append("la respuesta inválida no volvió como error con su secuencia")
		if errores.any(func(e): return e["secuencia"] != null and int(e["secuencia"]) == sec_valida):
			fallos.append("la respuesta válida fue rechazada")
		if not cerrada:
			fallos.append("no llegó decision_cerrada tras responder")
		if not espejo.decisiones.is_empty() and espejo.decisiones.has(int(decision["id"])):
			fallos.append("la decisión sigue en el espejo")
		if not "situacion_resuelta" in hechos:
			fallos.append("no llegó el hecho situacion_resuelta")
	for f in fallos:
		print("  ✘ ", f)
	if fallos.is_empty():
		print("  ✔ llegó la decisión «%s» con sus opciones %s" % [decision["situacion"], decision["pregunta"]["opciones"]])
		print("  ✔ la decisión pendiente se reenvió tras guardar y cargar la partida")
		print("  ✔ la respuesta inválida se rechazó con su secuencia; la válida se aceptó")
		print("  ✔ decision_cerrada la quitó del espejo y llegó el hecho situacion_resuelta")
	print("decisiones: %d fallos" % fallos.size())
	quit(1 if not fallos.is_empty() else 0)
