## Corpus dorado del espejo (V5, prueba 2): los casos que genera la suite de
## Haskell, aplicados con el código real del cliente.
##   godot --headless --path cliente --script res://pruebas/prueba_espejo.gd
extends SceneTree

const Espejo = preload("res://red/espejo.gd")
const Desglose = preload("res://ui/desglose.gd")
const Comun = preload("res://pruebas/comun.gd")


func _init() -> void:
	var dir := Comun.ruta_compartidas().path_join("espejo")
	var casos := Comun.archivos(dir)
	var fallos := 0
	var catalogo = Comun.leer_json(Comun.ruta_compartidas().path_join("protocolo/catalogo.json"))
	for n in casos:
		var caso = Comun.leer_json(dir.path_join(n))
		var espejo = Espejo.new()
		espejo.recibir(catalogo)
		espejo.instantanea(caso["instantanea"])
		espejo.aplicar_cambios(caso["cambios"])
		var esperado := {}
		for e in caso["esperado"]["entidades"]:
			esperado[Espejo.clave(e["ref"])] = e
		var problemas := []
		if not Comun.igual(espejo.entidades, esperado):
			problemas.append("las entidades no coinciden con las esperadas")
		if not Comun.igual(espejo.reloj, caso["esperado"]["reloj"]):
			problemas.append("el reloj no coincide")
		for e in espejo.entidades.values():
			problemas.append_array(espejo.verificar(e))
			# Prueba del tooltip (V5, prueba 4): el texto contiene todas las fuentes.
			for nombre in e["magnitudes"].keys():
				var texto := Desglose.texto(nombre, e["magnitudes"][nombre])
				for a in e["magnitudes"][nombre]["aportes"]:
					if not texto.contains(a["fuente"]):
						problemas.append("el tooltip de %s.%s no muestra la fuente %s" % [Espejo.clave(e["ref"]), nombre, a["fuente"]])
		if problemas.is_empty():
			print("  ✔ ", n)
		else:
			fallos += 1
			print("  ✘ ", n)
			for p in problemas:
				print("      ", p)
	print("espejo: %d casos, %d fallos" % [casos.size(), fallos])
	quit(1 if fallos > 0 or casos.is_empty() else 0)
