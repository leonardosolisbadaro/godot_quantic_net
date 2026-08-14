## @file quantic_net_autoload.gd
## @path res://addons/quantic_net/src/infrastructure/quantic_net_autoload.gd
##
## @description
## Autoload principal (casca) do QuanticNet.
## Expõe a API pública do plugin (host, join, submit_state)
## para integração plug and play com a Godot Engine.
##
## @created 2026-07-29
## @updated 2026-08-14
##
## @since 0.1.0
## @lastModifiedIn 0.9.0
##
## @author Leonardo S. Badaró (Gemini 3.1 Pro - High)

extends Node

# Sinais públicos (API)
signal connection_state_changed(new_state: int)
signal connection_failed_reason(error: int)

signal peer_joined(id: int)
signal peer_left(id: int)
signal state_received(owner: int, pos: Vector3, rot: Vector3, custom: int)
signal peer_sleep(owner: int)
signal pong_received(rtt: float, offset: float)
signal snapback_received(seq: int, pos: Vector3, rot: Vector3, reason: int, replay_inputs: Array)
signal input_tick(peer_id: int, sequence: int, input_mask: int, look_dir: Vector2)
signal peer_rejected(id: int, reason: String, strikes: int)
signal custom_packet_received(peer_id: int, ptype: int, data: PackedByteArray)

# ==============================================================================
# [1] MODOS DE OPERAÇÃO DA REDE (ARQUITETURA DE SINCRONIZAÇÃO)
# ==============================================================================
## Sincronização clássica orientada a snapshots com interpolação de estados no cliente.
const MODE_STATE_BASED := 0
## Sincronização determinística baseada no envio de comandos de input (Lockstep/RTS/Fighting).
const MODE_COMMAND_BASED := 1

# ==============================================================================
# [2] ESTADOS DE CONEXÃO
# Máquina de estados finitos que rege o ciclo de vida do Peer
# ==============================================================================
enum ConnectionState {
	DISCONNECTED,
	CONNECTING,
	AUTHENTICATING,
	CONNECTED,
	FAILED,
}

# ==============================================================================
# [3] ENROTEAMENTO, CANAIS E IDENTIFICADORES DE PEER (ENET / GODOT)
# ==============================================================================
## Identificador reservado estritamente para a autoridade do servidor pela Godot Engine.
const SERVER_PEER_ID := 1
## Identificador de peer inválido ou nulo (usado quando desconectado).
const INVALID_PEER_ID := 0
## Identificador especial utilizado para broadcast de pacotes para todos os peers conectados.
const BROADCAST_PEER_ID := 0
## Limiar de ID de entidade: IDs < 1000 são avatares de jogadores; IDs >= 1000 são props de ambiente.
const MAX_CLIENT_PEER_ID := 1000
## Canal UDP dedicado exclusivamente para o fluxo de pacotes de estado de entidades.
const CH_STATE := 1
## Modo de transferência não confiável (MultiplayerPeer.TRANSFER_MODE_UNRELIABLE - UDP puro sem ACK).
const TRANSFER_UNRELIABLE := 1
## Capacidade padrão de conexões simultâneas aceitas pelo host caso não especificado.
const DEFAULT_MAX_PEERS := 32

# ==============================================================================
# [4] PARÂMETROS PADRÃO DE HOST, VALIDAÇÃO E SEGURANÇA (FALLBACKS)
# ==============================================================================
## Taxa padrão de processamento e transmissão do loop de rede do servidor em Hz.
const DEFAULT_SERVER_TICK_RATE := 20.0
## Intervalo temporal fixo em milissegundos para o modo de simulação baseado em comandos.
const DEFAULT_TICK_RATE_MS := 50
## Quantidade padrão de ticks consecutivos sem movimento para declarar uma entidade dormente.
const DEFAULT_DORMANCY_TICKS := 60
## Dimensão espacial lateral padrão de cada célula do particionamento espacial (em metros).
const DEFAULT_GRID_CULLING_SIZE := 50.0
## Limite espacial cúbico extremo da simulação em metros para corte de segurança.
const DEFAULT_WORLD_BOUNDS := 500.0
## Tempo limite em segundos de tolerância para conclusão do handshake criptográfico DTLS.
const DEFAULT_AUTH_TIMEOUT := 3.0
## Quantidade máxima de violações permitidas pelo validador antes da desconexão compulsória (Kick).
const DEFAULT_MAX_STRIKES := 5
## Raio de culling espacial padrão em metros assumido para entidades sem perfil explícito.
const DEFAULT_CULL_RADIUS := 250.0
## Largura de aura padrão em metros para detecção e presença de entidade no mapa.
const DEFAULT_ENTITY_AURA := 250.0
## Distância máxima sentinela para consultas de raycast espacial (-1.0 = sem limite).
const DEFAULT_QUERY_MAX_DIST := -1.0
## Timestamp sentinela para consultas de histórico (-1 = snapshot mais recente).
const DEFAULT_QUERY_TIMESTAMP := -1
## Identificador numérico customizado padrão para estados de entidade.
const DEFAULT_CUSTOM_ID := 0
## Timestamp sentinela padrão para atualização de entidades (-1 = tempo atual).
const DEFAULT_TIMESTAMP := -1

# ==============================================================================
# [5] EMULAÇÃO DE REDE (NETEM) E CONVERSÃO DE UNIDADES
# ==============================================================================
## Taxa rápida padrão de perda forçada de pacotes no toggle simples de Netem (10%).
const NETEM_TOGGLE_LOSS := 0.1
## Latência rápida padrão injetada no toggle simples de Netem (100ms).
const NETEM_TOGGLE_LATENCY := 100
## Variância de jitter rápida padrão injetada no toggle simples de Netem (20ms).
const NETEM_TOGGLE_JITTER := 20
## Duplicação rápida padrão no toggle simples de Netem (0%).
const NETEM_TOGGLE_DUP := 0.0

## Porcentagem padrão simulada de perda de pacotes para o modo Netem na inicialização do cliente.
const DEFAULT_NETEM_LOSS := 10.0
## Latência base padrão em milissegundos para o modo Netem na inicialização do cliente.
const DEFAULT_NETEM_LATENCY_MS := 150
## Variância de jitter padrão em milissegundos para o modo Netem na inicialização do cliente.
const DEFAULT_NETEM_JITTER_MS := 50
## Taxa padrão de duplicação simulada de pacotes para o modo Netem na inicialização do cliente.
const DEFAULT_NETEM_DUP := 0.0

## Divisor para conversão de valores percentuais inteiros (ex: 10.0 -> 0.1).
const PERCENT_NORMALIZER := 100.0
## Limiar de corte para normalização percentual automática.
const PERCENT_THRESHOLD := 1.0

# ==============================================================================
# [6] PROTOCOLOS BINÁRIOS, OPCODES E ESTRUTURAS DE PACOTES
# ==============================================================================
## Opcodes de pacotes customizados de gameplay abaixo de 32 são reservados pelo Core C++.
const MIN_CUSTOM_OPCODE := 32
## Tamanho mínimo em bytes para o cabeçalho de qualquer datagrama de rede válido.
const MIN_PACKET_HEADER_SIZE := 1
## Tamanho em bytes de um identificador u32 em buffers binários empacotados.
const PEER_ID_BINARY_SIZE := 4
## Tamanho em bytes da mensagem de resposta de autorização contendo o ID atribuído.
const AUTH_PAYLOAD_SIZE := 4
## Tamanho mínimo em bytes exigido para um payload válido de snapshot de estado.
const STATE_PACKET_MIN_SIZE := 20
## Tamanho total em bytes do pacote de desconexão (1 byte tipo + 4 bytes peer_id).
const PEER_LEFT_PACKET_SIZE := 5
## Deslocamento de byte inicial do ID do peer no pacote de desconexão.
const PEER_LEFT_ID_OFFSET := 1

## Tamanho total em bytes do pacote de input de comando (13 bytes).
const INPUT_PACKET_SIZE := 13
## Deslocamento de byte do tipo de pacote no datagrama de input.
const INPUT_PACKET_TYPE_OFFSET := 0
## Deslocamento de byte do número de sequência no datagrama de input.
const INPUT_PACKET_SEQ_OFFSET := 1
## Deslocamento de byte da máscara binária de botões no datagrama de input.
const INPUT_PACKET_MASK_OFFSET := 3
## Deslocamento de byte do componente horizontal de rotação no datagrama de input.
const INPUT_PACKET_LOOK_X_OFFSET := 5
## Deslocamento de byte do componente vertical de rotação no datagrama de input.
const INPUT_PACKET_LOOK_Y_OFFSET := 9

## Tamanho do cabeçalho de opcode em pacotes customizados de jogo.
const CUSTOM_PACKET_HEADER_SIZE := 1
## Deslocamento do opcode customizado no pacote de jogo.
const CUSTOM_PACKET_OPCODE_OFFSET := 0
## Deslocamento inicial do payload de dados em pacotes customizados de jogo.
const CUSTOM_PACKET_PAYLOAD_OFFSET := 1

const QNTelemetryAggregator = preload(
	"res://addons/quantic_net/src/domain/qn_telemetry_aggregator.gd"
)

var _state: int = ConnectionState.DISCONNECTED
var _enet: ENetConnection = null
var _hook: Object = null # QNNetHook
var _wire: Object = null # QNWirePeer
var _host_session: RefCounted = null # QNHostSession
var _command_session: RefCounted = null # QNCommandSession
var _client_session: RefCounted = null # QNClientSession
var _secret: String = ""
var _is_server: bool = false
var _netem_on: bool = false
var _server_tick_rate: float = DEFAULT_SERVER_TICK_RATE
var _tick_accumulator: float = 0.0

var _telemetry_map: Dictionary = { }


func get_telemetry(peer_id: int) -> RefCounted:
	return _telemetry_map.get(peer_id)


func get_state() -> int:
	return _state


func is_server() -> bool:
	return _is_server


func get_unique_id() -> int:
	if _is_server:
		return SERVER_PEER_ID
	if _hook != null and _hook.get_base() != null:
		return _hook.get_base().get_unique_id()
	return INVALID_PEER_ID


func _set_state(s: int) -> void:
	if _state != s:
		_state = s
		connection_state_changed.emit(s)


func disconnect_net(is_exiting: bool = false) -> void:
	if _hook and _hook.has_method("close"):
		_hook.close()
	if _wire and _wire.has_method("close"):
		_wire.close()
	if (
		not is_exiting and is_inside_tree() and get_tree().has_method("get_multiplayer")
		and get_tree().get_multiplayer(self.get_path()) == _hook
	):
		get_tree().set_multiplayer(SceneMultiplayer.new(), self.get_path())
	_wire = null
	_enet = null
	_hook = null
	_host_session = null
	_command_session = null
	_client_session = null
	_is_server = false
	_secret = ""
	_set_state(ConnectionState.DISCONNECTED)


func host(
	port: int,
	secret: String,
	bind_ip: String = "*",
	max_peers: int = DEFAULT_MAX_PEERS,
	config: Dictionary = { },
) -> Error:
	disconnect_net()
	_is_server = true
	_secret = secret
	var err_out := [OK]
	_enet = QNDTLSBootstrap.host(port, bind_ip, max_peers, err_out)
	if _enet == null:
		_set_state(ConnectionState.FAILED)
		connection_failed_reason.emit(err_out[0])
		return err_out[0]

	_wire = QNWirePeer.new()
	_wire.initialize(_enet, true)
	_hook = QNNetHook.new()
	_hook.get_base().multiplayer_peer = _wire
	_hook.get_base().server_relay = true

	var net_mode = config.get("network_mode", MODE_STATE_BASED)
	if net_mode == MODE_COMMAND_BASED:
		_command_session = preload("res://addons/quantic_net/src/use_cases/qn_command_session.gd").new()
		_command_session.init(
			Callable(self, "_on_host_packet_ready"),
			config.get("tick_rate_ms", DEFAULT_TICK_RATE_MS),
		)
		_command_session.input_tick.connect(
			func(id: int, seq: int, mask: int, dir: Vector2) -> void:
				input_tick.emit(id, seq, mask, dir)
		)
		_command_session.peer_rejected.connect(
			func(id: int, r: String, s: int) -> void:
				peer_rejected.emit(id, r, s)
				if s >= config.get("max_strikes", DEFAULT_MAX_STRIKES):
					_hook.get_base().disconnect_peer(id)
		)
	else:
		_host_session = QNHostSession.new()
		_server_tick_rate = config.get("server_tick_rate", DEFAULT_SERVER_TICK_RATE)
		_host_session.set_dormancy_threshold(
			config.get("dormancy_threshold_ticks", DEFAULT_DORMANCY_TICKS)
		)
		_host_session.set_sync_adjacent_grids(config.get("sync_adjacent_grids", true))
		_host_session.set_default_cull_radius(
			config.get("default_cull_radius", DEFAULT_CULL_RADIUS)
		)
		_host_session.set_default_entity_aura(
			config.get("default_entity_aura", DEFAULT_ENTITY_AURA)
		)

		# Repassa as configurações para o QNSpatialGrid (C++)
		var grid = _host_session.get_grid()
		if grid:
			grid.set_cell_size(config.get("grid_culling_size", DEFAULT_GRID_CULLING_SIZE))
			var bounds_val = config.get("world_bounds", DEFAULT_WORLD_BOUNDS)
			grid.set_world_bounds(Vector3(bounds_val, bounds_val, bounds_val), true)

		var validator = preload("res://addons/quantic_net/src/domain/qn_server_validator.gd").new()
		validator.configure(config)
		_host_session.set_validator(validator)
		_host_session.snapback_requested.connect(_on_host_snapback_requested)
		_host_session.packet_ready.connect(_on_host_packet_ready)
		_host_session.peer_rejected.connect(
			func(id: int, r: String, s: int) -> void:
				peer_rejected.emit(id, r, s)
				if s >= config.get("max_strikes", DEFAULT_MAX_STRIKES):
					_hook.get_base().disconnect_peer(id)
		)

	_hook.custom_packet.connect(_on_custom_packet)

	_hook.get_base().auth_timeout = config.get("auth_timeout", DEFAULT_AUTH_TIMEOUT)
	_hook.get_base().allow_object_decoding = false
	_hook.get_base().auth_callback = Callable(self, "_on_auth_callback")
	_hook.peer_connected.connect(
		func(id: int) -> void:
			if _is_server:
				_telemetry_map[id] = QNTelemetryAggregator.new()
				peer_joined.emit(id)
	)
	_hook.peer_disconnected.connect(
		func(id: int) -> void:
			if _is_server:
				if _host_session and _host_session.has_method("on_peer_disconnected"):
					_host_session.on_peer_disconnected(id)
				if _command_session and _command_session.has_method("on_peer_disconnected"):
					_command_session.on_peer_disconnected(id)

				var pkt := PackedByteArray([QNSerializer.TYPE_PEER_LEFT])
				var id_bytes := PackedByteArray()
				id_bytes.resize(PEER_ID_BINARY_SIZE)
				id_bytes.encode_u32(0, id)
				pkt.append_array(id_bytes)
				_hook.send_custom(
					BROADCAST_PEER_ID,
					pkt,
					CH_STATE,
					MultiplayerPeer.TRANSFER_MODE_RELIABLE,
				)

			peer_left.emit(id)
	)

	get_tree().set_multiplayer(_hook, self.get_path())
	_set_state(ConnectionState.CONNECTED)
	return OK


func join(ip: String, port: int, secret: String, netem: bool = false, config: Dictionary = { }) -> int:
	disconnect_net()
	_is_server = false
	_secret = secret
	_set_state(ConnectionState.CONNECTING)
	var err_out := [OK]
	_enet = QNDTLSBootstrap.join(ip, port, "quanticnet", err_out)
	if _enet == null:
		_set_state(ConnectionState.FAILED)
		connection_failed_reason.emit(err_out[0])
		return err_out[0]

	_wire = QNWirePeer.new()
	_wire.initialize(_enet, false)
	if netem:
		var loss = config.get("netem_loss", DEFAULT_NETEM_LOSS)
		var lat = config.get("netem_latency", DEFAULT_NETEM_LATENCY_MS)
		var jit = config.get("netem_jitter", DEFAULT_NETEM_JITTER_MS)
		var dup = config.get("netem_dup", DEFAULT_NETEM_DUP)
		_wire.set_netem_config(
			true,
			loss / PERCENT_NORMALIZER if loss > PERCENT_THRESHOLD else loss,
			lat,
			jit,
			dup,
		)

	_hook = QNNetHook.new()
	_hook.get_base().multiplayer_peer = _wire
	_hook.get_base().auth_timeout = config.get("auth_timeout", DEFAULT_AUTH_TIMEOUT)
	_hook.get_base().allow_object_decoding = false

	_client_session = QNClientSession.new()
	_client_session.init(Callable(self, "_on_client_submit_packet"))
	_client_session.pong_received.connect(
		func(rtt: float, off: float) -> void:
			var my_id = _hook.get_base().get_unique_id()
			if _telemetry_map.has(my_id):
				_telemetry_map[my_id].push_rtt(rtt)
			pong_received.emit(rtt, off)
	)
	_client_session.remote_state_received.connect(
		func(owner: int, pos: Vector3, rot: Vector3, custom: int) -> void:
			state_received.emit(owner, pos, rot, custom)
	)
	_client_session.peer_sleep.connect(func(owner: int) -> void:
			peer_sleep.emit(owner))
	_client_session.snapback_received.connect(
		func(seq: int, pos: Vector3, rot: Vector3, reason: int, replay: Array) -> void:
			snapback_received.emit(seq, pos, rot, reason, replay)
	)

	_hook.get_base().auth_callback = _on_client_auth_callback

	_hook.custom_packet.connect(_on_custom_packet)
	_hook.connected_to_server.connect(
		func() -> void:
			var my_id: int = _hook.get_base().get_unique_id()
			_client_session.set_local_id(my_id)
			_telemetry_map[my_id] = QNTelemetryAggregator.new()
			_set_state(ConnectionState.CONNECTED)
			peer_joined.emit(my_id)
	)
	_hook.peer_connected.connect(
		func(id: int) -> void:
			if _is_server:
				_telemetry_map[id] = QNTelemetryAggregator.new()
			else:
				# Even on clients, we must populate the map so get_active_peers() sees them
				_telemetry_map[id] = QNTelemetryAggregator.new()
			if id != SERVER_PEER_ID:
				peer_joined.emit(id)
	)
	_hook.peer_disconnected.connect(
		func(id: int) -> void:
			_telemetry_map.erase(id)
			if _client_session:
				_client_session.cleanup_entity(id)
			peer_left.emit(id)
			if id == SERVER_PEER_ID:
				_set_state(ConnectionState.DISCONNECTED)
	)

	get_tree().set_multiplayer(_hook, self.get_path())
	return OK


func _process(delta: float) -> void:
	if _hook == null:
		return
	if _is_server and _state == ConnectionState.CONNECTED:
		_tick_accumulator += delta
		var tick_time = 1.0 / _server_tick_rate
		while _tick_accumulator >= tick_time:
			_tick_accumulator -= tick_time
			if _host_session:
				_host_session.tick_broadcast(Time.get_ticks_msec())
			if _command_session:
				_command_session.tick_broadcast(Time.get_ticks_msec())
	elif not _is_server:
		if (
			_hook.get_base().get_multiplayer_peer().get_connection_status()
			== MultiplayerPeer.CONNECTION_CONNECTED
			and _state == ConnectionState.CONNECTING
		):
			_set_state(ConnectionState.AUTHENTICATING)
			_hook.get_base().send_auth(SERVER_PEER_ID, _secret.to_utf8_buffer())


func _on_auth_callback(id: int, data: PackedByteArray) -> void:
	if _is_server:
		_on_server_auth_callback(id, data)
	else:
		_on_client_auth_callback(id, data)


func _on_server_auth_callback(id: int, data: PackedByteArray) -> void:
	if data == _secret.to_utf8_buffer():
		if _host_session:
			_host_session.on_peer_authenticated(id)
		if _command_session:
			_command_session.on_peer_authenticated(id)
		var b = PackedByteArray()
		b.resize(AUTH_PAYLOAD_SIZE)
		b.encode_u32(0, id)
		_hook.get_base().send_auth(id, b)
		_hook.get_base().complete_auth(id)
	else:
		_hook.get_base().disconnect_peer(id)


func _on_client_auth_callback(id: int, data: PackedByteArray) -> void:
	if data.size() >= AUTH_PAYLOAD_SIZE:
		var assigned_id = data.decode_u32(0)
		_wire.set_client_id(assigned_id)
	_hook.get_base().complete_auth(id)


func _on_custom_packet(peer_id: int, data: PackedByteArray, _channel: int = 1) -> void:
	if data.size() >= MIN_PACKET_HEADER_SIZE and data[0] >= MIN_CUSTOM_OPCODE:
		custom_packet_received.emit(peer_id, data[0], data.slice(1))
		return

	if _is_server:
		if (
			_host_session and data.size() >= STATE_PACKET_MIN_SIZE
			and data[0] == QNSerializer.TYPE_STATE
		):
			_host_session.on_client_snapshot(peer_id, data.slice(1), Time.get_ticks_msec())
		elif (
			_command_session and data.size() >= MIN_PACKET_HEADER_SIZE
			and data[0] == QNSerializer.TYPE_INPUT
		):
			_command_session.on_client_input(peer_id, data, Time.get_ticks_msec())
	else:
		if data.size() >= MIN_PACKET_HEADER_SIZE:
			if data[0] == QNSerializer.TYPE_PEER_LEFT and data.size() >= PEER_LEFT_PACKET_SIZE:
				var left_id = data.decode_u32(PEER_LEFT_ID_OFFSET)
				if _client_session:
					_client_session.cleanup_entity(left_id)
				peer_left.emit(left_id)
			else:
				_client_session.handle_packet(data, Time.get_ticks_msec())
				if data[0] == QNSerializer.TYPE_INPUT_SNAPSHOT:
					var my_id = _hook.get_base().get_unique_id()
					if _telemetry_map.has(my_id):
						_telemetry_map[my_id].push_loss(_client_session.loss_of(SERVER_PEER_ID))


func _on_host_snapback_requested(peer_id: int, pkt: PackedByteArray) -> void:
	if not _hook.get_base().get_peers().has(peer_id):
		return
	var body := PackedByteArray([QNSerializer.TYPE_SNAPBACK])
	body.append_array(pkt)
	_hook.send_custom(peer_id, body, CH_STATE, TRANSFER_UNRELIABLE)


## Retorna o milissegundo atual da engine (Time.get_ticks_msec())
func get_local_time() -> int:
	return Time.get_ticks_msec()


## Retorna a estimativa do tempo atual do Servidor (compensando RTT e Offset)
func get_server_time() -> int:
	if _client_session == null:
		return get_local_time()
	return _client_session.server_time(get_local_time())


func _on_host_packet_ready(peer_id: int, data: PackedByteArray) -> void:
	if not _hook.get_base().get_peers().has(peer_id):
		return
	_hook.send_custom(peer_id, data, CH_STATE, TRANSFER_UNRELIABLE)


func _on_client_submit_packet(to: int, data: PackedByteArray, ch: int, mode: int) -> void:
	_hook.send_custom(to, data, ch, mode)


func submit_state(pos: Vector3, rot: Vector3, custom: int, dt: float) -> void:
	if not _is_server and _client_session:
		_client_session.submit_state(pos, rot, custom, dt, Time.get_ticks_msec())


func submit_input(sequence: int, input_mask: int, look_dir: Vector2) -> void:
	if not _is_server and _client_session:
		var pkt := PackedByteArray()
		pkt.resize(INPUT_PACKET_SIZE)
		pkt.encode_u8(
			INPUT_PACKET_TYPE_OFFSET,
			QNSerializer.TYPE_INPUT,
		)
		pkt.encode_u16(INPUT_PACKET_SEQ_OFFSET, sequence)
		pkt.encode_u16(INPUT_PACKET_MASK_OFFSET, input_mask)
		pkt.encode_float(INPUT_PACKET_LOOK_X_OFFSET, look_dir.x)
		pkt.encode_float(INPUT_PACKET_LOOK_Y_OFFSET, look_dir.y)
		_hook.send_custom(SERVER_PEER_ID, pkt, CH_STATE, TRANSFER_UNRELIABLE)


func get_remote_state(entity_id: int) -> Dictionary:
	if not _is_server and _client_session:
		return _client_session.remote_state(entity_id, Time.get_ticks_msec())
	return { }


func get_server_grid() -> Object:
	if _is_server and _host_session:
		return _host_session.get_grid()
	return null


func set_server_validator(validator: RefCounted) -> void:
	if _is_server and _host_session:
		_host_session.set_validator(validator)


func cleanup_entity(entity_id: int) -> void:
	if not _is_server and _client_session:
		_client_session.cleanup_entity(entity_id)


func query_raycast(
	origin: Vector3,
	direction: Vector3,
	max_dist: float = DEFAULT_QUERY_MAX_DIST,
	timestamp: int = DEFAULT_QUERY_TIMESTAMP,
) -> Dictionary:
	if _is_server and _host_session:
		return _host_session.query_raycast(origin, direction, max_dist, timestamp)
	return { }


func query_box(center: Vector3, extents: Vector3, timestamp: int = DEFAULT_QUERY_TIMESTAMP) -> Array:
	if _is_server and _host_session:
		return _host_session.query_box(center, extents, timestamp)
	return []


func query_sphere(center: Vector3, radius: float, timestamp: int = DEFAULT_QUERY_TIMESTAMP) -> Array:
	if _is_server and _host_session:
		return _host_session.query_sphere(center, radius, timestamp)
	return []


func remote_state(owner_id: int) -> Dictionary:
	if not _is_server and _client_session:
		return _client_session.remote_state(owner_id, Time.get_ticks_msec())
	return { }


func loss_of(owner_id: int) -> float:
	if not _is_server and _client_session:
		return _client_session.loss_of(owner_id)
	return 0.0


func is_clock_synced() -> bool:
	if not _is_server and _client_session:
		return _client_session.is_clock_synced()
	return false


func clock_rtt() -> float:
	if not _is_server and _client_session:
		return _client_session.clock_rtt()
	return 0.0


func clock_offset() -> float:
	if not _is_server and _client_session:
		return _client_session.clock_offset()
	return 0.0


func server_time(now: int = -1) -> int:
	if now < 0:
		now = Time.get_ticks_msec()
	if not _is_server and _client_session:
		return _client_session.server_time(now)
	return now


func get_registry() -> Dictionary:
	if _is_server and _host_session:
		return _host_session.get_registry()
	elif not _is_server and _client_session:
		return _client_session.get_registry()
	return { }


func get_registry_keys() -> Array:
	if _is_server and _host_session:
		return _host_session.get_registry_keys()
	elif not _is_server and _client_session:
		return _client_session.get_registry_keys()
	return []


func get_entity_position(entity_id: int) -> Vector3:
	if _is_server and _host_session:
		return _host_session.get_entity_position(entity_id)
	elif _client_session:
		var reg = _client_session.get_registry()
		if reg.has(entity_id):
			return reg[entity_id].get("pos", Vector3.ZERO)
	return Vector3.ZERO


func register_entity(
	entity_id: int,
	is_peer: bool,
	has_initial_state: bool,
	profile: RefCounted = null,
) -> void:
	if _is_server and _host_session:
		_host_session.register_entity(entity_id, is_peer, has_initial_state, profile)


func unregister_entity(entity_id: int) -> void:
	if _is_server and _host_session:
		_host_session.unregister_entity(entity_id)

		# Dispara TYPE_PEER_LEFT apenas para clientes reais (id < 1000)
		# Não inundar a rede mandando exclusão de centenas de props ao mesmo tempo,
		# pois a ausência deles já provoca culling natural no cliente.
		if entity_id < MAX_CLIENT_PEER_ID:
			var pkt := PackedByteArray([QNSerializer.TYPE_PEER_LEFT])
			var id_bytes := PackedByteArray()
			id_bytes.resize(PEER_ID_BINARY_SIZE)
			id_bytes.encode_u32(0, entity_id)
			pkt.append_array(id_bytes)

			for peer in _hook.get_base().get_peers():
				if peer != entity_id:
					_hook.send_custom(peer, pkt, CH_STATE, MultiplayerPeer.TRANSFER_MODE_RELIABLE)


func update_entity_state(
	entity_id: int,
	pos: Vector3,
	rot: Vector3,
	custom_id: int = DEFAULT_CUSTOM_ID,
	ts: int = DEFAULT_TIMESTAMP,
) -> void:
	if _is_server and _host_session:
		_host_session.update_entity_state(entity_id, pos, rot, custom_id, ts)


func change_entity_profile(entity_id: int, new_profile: RefCounted) -> void:
	if _is_server and _host_session:
		_host_session.change_entity_profile(entity_id, new_profile)


func add_region(region_id: int, center: Vector3, extents: Vector3) -> void:
	if _is_server and _host_session:
		_host_session.add_region(region_id, center, extents)


func remove_region(region_id: int) -> void:
	if _is_server and _host_session:
		_host_session.remove_region(region_id)


func clear_regions() -> void:
	if _is_server and _host_session:
		_host_session.clear_regions()


func kick(peer_id: int) -> void:
	if _is_server and _hook:
		_hook.get_base().disconnect_peer(peer_id)


func toggle_netem() -> void:
	if _wire:
		_netem_on = not _netem_on
		_wire.set_netem_config(
			_netem_on,
			NETEM_TOGGLE_LOSS,
			NETEM_TOGGLE_LATENCY,
			NETEM_TOGGLE_JITTER,
			NETEM_TOGGLE_DUP,
		)
		print("[QuanticNet] Netem: ", "ON" if _netem_on else "OFF")


func set_netem_config(loss_pct: float, latency_ms: int, jitter_ms: int, dup_pct: float = 0.0) -> void:
	if _wire:
		# Se todos os parâmetros forem 0, interpretamos que o Netem deve ser completamente desligado.
		var should_enable = (loss_pct > 0.0 or latency_ms > 0 or jitter_ms > 0 or dup_pct > 0.0)
		_netem_on = should_enable
		_wire.set_netem_config(
			should_enable,
			loss_pct / PERCENT_NORMALIZER if loss_pct > PERCENT_THRESHOLD else loss_pct,
			latency_ms,
			jitter_ms,
			dup_pct,
		)


func _exit_tree() -> void:
	disconnect_net(true)


func get_active_peers() -> Array:
	return _telemetry_map.keys()


func send_game_packet(
	to_peer: int,
	ptype: int,
	data: PackedByteArray = PackedByteArray(),
	reliable: bool = true,
) -> void:
	if ptype < MIN_CUSTOM_OPCODE:
		push_error("Game OpCodes must be >= MIN_CUSTOM_OPCODE. Reserved OpCode used: %d" % ptype)
		return
	if _hook == null:
		return

	var pkt := PackedByteArray([ptype])
	if not data.is_empty():
		pkt.append_array(data)

	var mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE
	_hook.send_custom(to_peer, pkt, CH_STATE, mode)
