## Utilidades de las pruebas sin interfaz gráfica.
extends RefCounted


static func ruta_compartidas() -> String:
	return ProjectSettings.globalize_path("res://").path_join("../pruebas_compartidas").simplify_path()


static func leer_json(ruta: String):
	var f := FileAccess.open(ruta, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


static func archivos(dir: String) -> Array:
	var r := []
	var d := DirAccess.open(dir)
	if d == null:
		return r
	for n in d.get_files():
		if n.ends_with(".json"):
			r.append(n)
	r.sort()
	return r


## Igualdad estructural sin depender del orden de las claves ni de int/float.
static func igual(a, b) -> bool:
	return JSON.stringify(a, "", true) == JSON.stringify(b, "", true)
