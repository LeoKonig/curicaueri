## Textos visibles por clave de localización (V5, *Data-driven en JSON*).
## Se leen de res://textos/es.json. Una clave que falta se muestra tal cual,
## con sus parámetros, para que un texto sin traducir se note en pantalla sin
## romper nada. Las plantillas llevan {nombre} donde entra un parámetro.
extends RefCounted

const RUTA := "res://textos/es.json"

static var _tabla: Dictionary = {}
static var _cargada: bool = false


static func tabla() -> Dictionary:
	if not _cargada:
		_cargada = true
		var f := FileAccess.open(RUTA, FileAccess.READ)
		if f != null:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_tabla = d
	return _tabla


## El texto de una clave, con los parámetros sustituidos.
static func de(clave: String, params: Dictionary = {}) -> String:
	var t: Dictionary = tabla()
	if t.has(clave):
		return formatear(str(t[clave]), params)
	if params.is_empty():
		return clave
	var partes := []
	var nombres: Array = params.keys()
	nombres.sort()
	for k in nombres:
		partes.append("%s=%s" % [k, params[k]])
	return "%s (%s)" % [clave, ", ".join(partes)]


static func existe(clave: String) -> bool:
	return tabla().has(clave)


static func formatear(plantilla: String, params: Dictionary) -> String:
	var r := plantilla
	for k in params.keys():
		r = r.replace("{%s}" % k, str(params[k]))
	return r
