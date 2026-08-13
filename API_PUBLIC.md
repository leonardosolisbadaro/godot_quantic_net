# 📚 QuanticNet - Referência da API Pública (v0.9.0-beta)

O **QuanticNet** é uma extensão C++ (GDExtension) de Netcode Autoritativo projetada para a Godot Engine 4.7+.
Sua arquitetura foi desenvolvida para orquestrar mundos dinâmicos complexos (MMO, Battle Royales) eliminando Jitter, poupando a banda de rede (*Delta Encoding*, *Spatial Culling*, *NavMesh Validation*) e resolvendo lógicas de combate instantaneamente com *Lag Compensation* (Rollback).

Esta documentação serve como referência completa para a utilização do Singleton **`QuanticNet`**.

---

## 📡 Sinais (Event-Driven API)

### `connection_state_changed(new_state: int)`
* **Parâmetros**: `new_state` (`ConnectionState.CONNECTING`, `CONNECTED`, `DISCONNECTED`).

### `connection_failed_reason(error: int)`
* **Parâmetros**: `error` - O `Error` padrão da Godot.

### `peer_joined(id: int)` / `peer_left(id: int)`
* **Descrição**: O servidor validou a entrada/saída segura de um jogador.

### `peer_rejected(id: int, reason: String, strikes: int)`
* **Descrição**: *(Servidor)*. Emite quando um peer enviou um pacote inválido (reprovado pelo validador híbrido de NavMesh/Speed).

### `state_received(owner: int, pos: Vector3, rot: Vector3, custom: int)`
* **Descrição**: *(Cliente)* Emitido no instante em que o cliente recebe um pacote do servidor (raw data).

### `peer_sleep(owner: int)`
* **Descrição**: Notifica que uma entidade entrou no *Dormancy State* (parou de transmitir dados).

### `pong_received(rtt_ms: float, offset_ms: float)`
* **Descrição**: Expõe a Sincronização de Relógios (RTT e desvio).

### `snapback_received(seq: int, pos: Vector3, rot: Vector3, reason: int, replay_inputs: Array)`
* **Descrição**: *(Cliente)* Penalização máxima (Command-Based). A sua simulação de "Client-Side Prediction" divergiu e o Servidor forçou uma correção. 
* **Parâmetros**: `seq` (número do input falho), `pos` (coordenada validada para onde você deve se teletransportar).

### `input_tick(peer_id: int, sequence: int, input_mask: int, look_dir: Vector2)`
* **Descrição**: *(Servidor)* O servidor recebeu um Frame de Comando puro de um cliente.

### `custom_packet_received(peer_id: int, ptype: int, data: PackedByteArray)`
* **Descrição**: Onde os *OpCodes* de gameplay chegam (tiros, inventário, dano).

---

## 🌐 Conexão e Ciclo de Vida

### `host(port: int, secret: String, bind_ip: String = "*", max_peers: int = 32, config: Dictionary = {}) -> int`
* **Parâmetros Mágicos no Config:** `navigation_map` (RID para validação Server-Side), `auth_timeout`, `dormancy_threshold_ticks`.

### `join(ip: String, port: int, secret: String, netem: bool = false, config: Dictionary = {}) -> int`
### `disconnect_net(is_exiting: bool = false) -> void`

* `get_state() -> int`
* `is_server() -> bool`
* `get_unique_id() -> int`
* `get_local_time() -> int`
* `get_server_time() -> int`

---

## 🏛️ Gestão Espacial e de Entidades (Server)

### `QNEntityProfile`
* `tick_rate` (Hz), `priority_weight`, `culling_radius`.

### `register_entity(entity_id: int, is_peer: bool, has_initial_state: bool, profile: RefCounted = null) -> void`
### `unregister_entity(entity_id: int) -> void`
### `update_entity_state(entity_id: int, pos: Vector3, rot: Vector3, custom_id: int = 0, ts: int = -1) -> void`
### `change_entity_profile(entity_id: int, new_profile: RefCounted) -> void`
### `set_server_validator(validator: RefCounted) -> void`
Substitui a regra matemática de aprovação/rejeição das coordenadas dos clientes. (Usado no paradigma Híbrido com o NavMesh).

---

## 🕹️ Input e Sincronização (Cliente -> Servidor)

### `submit_state(pos: Vector3, rot: Vector3, custom: int, dt: float) -> void`
(Paradigma *State-Based Prediction*).

### `submit_input(sequence: int, input_mask: int, look_dir: Vector2) -> void`
(Paradigma *Command-Based*).

### `get_remote_state(owner_id: int) -> Dictionary`
Lê o `QNInterpBuffer` para movimentação lisa.

### `send_game_packet(to_peer: int, opcode: int, data: PackedByteArray, reliable: bool = true) -> void`
Despacha dados arbitrários (OpCodes) blindados pelo ENet. Se `to_peer` for 0, espalha para todos.

---

## 🎯 Lag Compensation e Queries no Passado (Server)

O Servidor usa o `QNWorldHistoryBuffer` para viajar no tempo e resolver conflitos:

### `query_raycast(origin: Vector3, direction: Vector3, max_dist: float = -1.0, timestamp: int = -1) -> Dictionary`
### `query_box(center: Vector3, extents: Vector3, timestamp: int = -1) -> Array`
### `query_sphere(center: Vector3, radius: float, timestamp: int = -1) -> Array`

---

## 🧪 Engenharia do Caos e Netem

### `toggle_netem()`
### `set_netem_config(loss_pct: float, latency_ms: int, jitter_ms: int, dup_pct: float = 0.0) -> void`
