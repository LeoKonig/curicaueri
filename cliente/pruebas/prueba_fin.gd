## Fin de partida de punta a punta con el núcleo real, lanzado con un guion que
## termina la partida el día 10:
##   nucleo --puerto 4792 --guion pruebas_compartidas/guion_fin.json &
##   godot --headless --path cliente --script res://pruebas/prueba_fin.gd -- --puerto 4792
## Corre hasta que llega «fin» (con su crónica y el reloj pausado), intenta
## reanudar (la partida terminada no avanza), guarda y carga la partida, y
## comprueba que el núcleo vuelve a avisar el fin, una sola vez por carga.
extends SceneTree

const Conexion = preload("res://red/conexion.gd")
const Espejo = preload("res://red/espejo.gd")
const Protocolo = preload("res://red/protocolo.gd")

var conexion
var espejo = Espejo.new()
var tiempo := 0.0
var fase := "inicial"
var fines := []             # una entrada por mensaje «fin»: razón, tick y claves de la crónica
var ticks_tras_fin := []
var tiempo_extra := 0.0


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
		"fin":
			var claves := []
			for e in m["cronica"]:
				claves.append(e["clave"])
			fines.append({"razon": m["razon"], "tick": int(m["reloj"]["tick"]), "pausado": m["reloj"]["pausado"], "claves": claves})
			if fines.size() == 1:
				# Intenta reanudar y guardar: la partida terminada no debe avanzar.
				conexion.enviar(Protocolo.pausa(false))
				conexion.enviar(Protocolo.guardar("fin_partida"))
				fase = "guardando"
			else:
				fase = "recargada"
		"aviso":
			if fase == "guardando" and m["texto"].begins_with("partida guardada"):
				conexion.enviar(Protocolo.cargar("fin_partida"))
				fase = "cargando"
		"cambios", "reloj":
			if not fines.is_empty():
				ticks_tras_fin.append(int(m["reloj"]["tick"]))


func _process(delta: float) -> bool:
	tiempo += delta
	if fase == "recargada":
		tiempo_extra += delta
	if tiempo_extra > 1.5 or tiempo > 25.0:
		_terminar()
	return false


func _terminar() -> void:
	var fallos := []
	if fines.is_empty():
		fallos.append("no llegó «fin» en 25 s")
	else:
		var f: Dictionary = fines[0]
		if f["razon"] != "fecha":
			fallos.append("la razón del fin es «%s», no «fecha»" % f["razon"])
		if not f["pausado"]:
			fallos.append("el reloj del fin no viene pausado")
		if not "cronica.fin" in f["claves"]:
			fallos.append("la crónica del fin no incluye la entrada del fin: %s" % [f["claves"]])
		if ticks_tras_fin.any(func(t): return t != f["tick"]):
			fallos.append("la partida terminada siguió avanzando: %s" % [ticks_tras_fin.slice(0, 5)])
		if fines.size() != 2:
			fallos.append("se esperaban 2 avisos de fin (uno al terminar, otro al cargar) y llegaron %d" % fines.size())
		elif fines[1]["tick"] != f["tick"] or fines[1]["claves"] != f["claves"]:
			fallos.append("la partida cargada no vuelve a terminar igual")
		if espejo.fin.get("razon", "") != "fecha":
			fallos.append("el espejo no tiene el fin")
		if espejo.cronica.size() != f["claves"].size():
			fallos.append("la crónica del espejo no es la del fin")
	for x in fallos:
		print("  ✘ ", x)
	if fallos.is_empty():
		print("  ✔ llegó «fin» por fecha, con el reloj pausado y la entrada del fin en la crónica")
		print("  ✔ la partida terminada no avanzó aunque se pidió reanudar")
		print("  ✔ al cargar la partida terminada, el fin se avisó otra vez, una sola vez")
	print("fin: %d fallos" % fallos.size())
	quit(1 if not fallos.is_empty() else 0)
