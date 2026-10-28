## Texto del tooltip de una magnitud. Recorre lo que dice el espejo, sin lista
## blanca de fuentes conocidas: si el núcleo manda una fuente nueva, aparece.
extends RefCounted


static func numero(s) -> String:
	var v := float(s)
	if is_equal_approx(v, roundf(v)):
		return str(int(roundf(v)))
	return String.num(v, 4)


static func con_signo(s) -> String:
	var v := float(s)
	return ("+" if v >= 0.0 else "") + numero(s)


static func texto(nombre: String, mag: Dictionary) -> String:
	var lineas := ["%s: %s" % [nombre, numero(mag["efectivo"])], "  base %s" % numero(mag["base"])]
	for a in mag["aportes"]:
		var partes := []
		if float(a["sumando"]) != 0.0:
			partes.append(con_signo(a["sumando"]))
		if float(a["porcentaje"]) != 0.0:
			partes.append(con_signo(float(a["porcentaje"]) * 100.0) + " %")
		var linea := "  %s  %s" % [" ".join(partes), a["fuente"]]
		if a["vence"] != null:
			linea += "  (vence el día %d)" % int(a["vence"])
		lineas.append(linea)
	return "\n".join(lineas)


## Un campo como texto, sea del tipo que sea.
static func valor(v: Dictionary) -> String:
	match v.get("t", ""):
		"texto": return str(v["v"])
		"entero": return str(int(v["v"]))
		"fijo": return numero(v["v"])
		"bool": return "sí" if v["v"] else "no"
		"ref": return "%s %d" % [v["v"]["clase"], int(v["v"]["id"])]
		"clave": return str(v["c"])
		"lista": return ", ".join(v["v"].map(func(x): return valor(x)))
		_: return "—"
