## Criterio de rendimiento del hito 2: el mapa de ~2 700 hexágonos a 60 FPS.
## Necesita un renderizador real (no --headless) y el núcleo con el mapa grande:
##   nucleo --puerto 4791 --mapa 60x45 &
##   godot --path cliente --script res://pruebas/prueba_rendimiento.gd -- --puerto 4791
## Corre la partida a la velocidad máxima, sin vsync, con zoom y desplazamiento
## cada fotograma (el peor caso: se redibuja todo), y mide 8 segundos.
extends SceneTree

var principal
var t := 0.0
var midiendo := false
var tiempos := PackedFloat64Array()
var t_construir := 0.0
var inicio_us := 0
var redibujados := 0


func _init() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	principal = load("res://principal.tscn").instantiate()
	root.add_child(principal)


func _process(delta: float) -> bool:
	t += delta
	var lienzo = principal.lienzo
	if not midiendo and lienzo != null and lienzo.celdas_dibujadas > 0 and t > 1.5:
		var t0 := Time.get_ticks_usec()
		lienzo.construir()
		t_construir = (Time.get_ticks_usec() - t0) / 1000.0
		principal.conexion.enviar(preload("res://red/protocolo.gd").velocidad(5))
		principal.conexion.enviar(preload("res://red/protocolo.gd").pausa(false))
		midiendo = true
		inicio_us = Time.get_ticks_usec()
	elif midiendo:
		tiempos.append(delta * 1000.0)
		lienzo.zoom = 1.0 + 0.5 * sin(t)
		lienzo.desplazamiento = Vector2(20.0 * cos(t), 20.0 * sin(t))
		lienzo.queue_redraw()
		redibujados += 1
		if (Time.get_ticks_usec() - inicio_us) > 8000000:
			_informar()
	if t > 30.0:
		print("  ✘ no llegó el mapa del núcleo")
		quit(1)
	return false


func _informar() -> void:
	var orden := tiempos.duplicate()
	orden.sort()
	var media := 0.0
	for x in tiempos:
		media += x
	media /= tiempos.size()
	var p99: float = orden[int(orden.size() * 0.99)]
	var celdas: int = principal.lienzo.celdas_dibujadas
	var fps := 1000.0 / media
	print("  celdas: %d · fotogramas: %d · tick final: %d" % [celdas, tiempos.size(), int(principal.espejo.reloj["tick"])])
	print("  construir la malla: %.1f ms" % t_construir)
	print("  fotograma medio: %.2f ms (%.0f FPS) · percentil 99: %.2f ms" % [media, fps, p99])
	print("  renderizador: %s" % RenderingServer.get_video_adapter_name())
	var ok := celdas >= 2700 and p99 <= 1000.0 / 60.0
	print(("  ✔ " if ok else "  ✘ ") + "criterio: ≥ 2 700 celdas y el 99 % de los fotogramas en menos de 16,7 ms")
	quit(0 if ok else 1)
