## Conexión con el núcleo: TCP local, una línea de JSON por mensaje.
## Reintenta mientras el núcleo arranca o si se cae; al reconectar vuelve a
## saludar y el núcleo responde con una instantánea completa.
extends Node

const Protocolo = preload("res://red/protocolo.gd")

signal mensaje(m: Dictionary)
signal estado_cambiado(texto: String)

var host := "127.0.0.1"
var puerto := 4646

var _tcp := StreamPeerTCP.new()
var _buffer := PackedByteArray()
var _secuencia := 0
var _conectado := false
var _espera := 0.0


func _process(delta: float) -> void:
	_tcp.poll()
	match _tcp.get_status():
		StreamPeerTCP.STATUS_CONNECTED:
			if not _conectado:
				_conectado = true
				estado_cambiado.emit("conectado a %s:%d" % [host, puerto])
				enviar(Protocolo.hola())
			_leer()
		StreamPeerTCP.STATUS_CONNECTING:
			pass
		_:
			if _conectado:
				_conectado = false
				estado_cambiado.emit("desconectado; reintentando…")
			_espera -= delta
			if _espera <= 0.0:
				_espera = 1.0
				_buffer.clear()
				_tcp = StreamPeerTCP.new()
				_tcp.connect_to_host(host, puerto)


func conectado() -> bool:
	return _conectado


func enviar(m: Dictionary) -> void:
	if _conectado:
		_tcp.put_data((JSON.stringify(m) + "\n").to_utf8_buffer())


## Envía un comando del juego y devuelve su número de secuencia, con el que el
## núcleo identificará un posible rechazo.
func enviar_comando(cmd: Dictionary) -> int:
	_secuencia += 1
	enviar(Protocolo.comando(_secuencia, cmd))
	return _secuencia


## Pide la predicción de un comando sin aplicarlo. Comparte la numeración con
## los comandos, así que un rechazo se reconoce por su secuencia.
func enviar_consulta(cmd: Dictionary) -> int:
	_secuencia += 1
	enviar(Protocolo.consulta(_secuencia, cmd))
	return _secuencia


func _leer() -> void:
	var disponibles := _tcp.get_available_bytes()
	if disponibles > 0:
		var r := _tcp.get_data(disponibles)
		if r[0] == OK:
			_buffer.append_array(r[1])
	var fin := _buffer.find(10)
	while fin != -1:
		var linea := _buffer.slice(0, fin).get_string_from_utf8()
		_buffer = _buffer.slice(fin + 1)
		var m = JSON.parse_string(linea)
		if m is Dictionary:
			mensaje.emit(m)
		else:
			push_warning("línea inválida del núcleo: " + linea)
		fin = _buffer.find(10)


## Responde a una decisión del guion. Devuelve la secuencia, como los comandos:
## si la respuesta llega tarde o no vale, el error trae esta secuencia.
func enviar_respuesta(decision: int, respuesta: String) -> int:
	_secuencia += 1
	enviar(Protocolo.responder(_secuencia, decision, respuesta))
	return _secuencia
