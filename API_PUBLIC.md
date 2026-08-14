# 📚 QuanticNet — Referência Completa da API Pública (v0.9.0)

O **QuanticNet** é uma extensão de rede autoritativa de altíssimo desempenho desenvolvida em **C++ (GDExtension)** para a **Godot Engine 4.7+**.

A arquitetura foi projetada para suportar desde jogos competitivos rápidos (FPS/Fighting) até ecossistemas massivos (*3D Open World MMO*). O motor isola a infraestrutura pesada (sockets UDP, criptografia DTLS, serialização binária com bit-packing, culling espacial e compensação de lag) no silício do C++, expondo uma interface limpa, tipada e declarativa no **GDScript** através do Singleton global `QuanticNet`.

---

## 📑 Sumário

1. [Sinais Públicos (Event-Driven API)](#-sinais-públicos-event-driven-api)
2. [Constantes Globais e Enums](#-constantes-globais-e-enums)
3. [Ciclo de Vida e Inicialização de Rede](#-ciclo-de-vida-e-inicialização-de-rede)
4. [Sincronização de Relógio e Telemetria Temporal](#-sincronização-de-relógio-e-telemetria-temporal)
5. [Gerenciamento de Entidades e Perfis Dinâmicos (Server-Side)](#-gerenciamento-de-entidades-e-perfis-dinâmicos-server-side)
6. [Submissão de Movimento e Predição (Client-Side)](#-submissão-de-movimento-e-predição-client-side)
7. [Validação Autoritativa e Anti-Cheat (Server-Side)](#-validação-autoritativa-e-anti-cheat-server-side)
8. [Lag Compensation e Consultas no Passado (Rollback)](#-lag-compensation-e-consultas-no-passado-rollback)
9. [Mensageria Customizada de Gameplay (OpCodes)](#-mensageria-customizada-de-gameplay-opcodes)
10. [Emulação de Condições Adversas de Rede (NetEmul)](#-emulação-de-condições-adversas-de-rede-netemul)

---

## 📡 Sinais Públicos (Event-Driven API)

O `QuanticNet` opera sob uma arquitetura orientada a eventos. Conecte estes sinais para reagir a mudanças de rede de forma desacoplada:

```gdscript
# Exemplo de conexão no _ready() do seu GameManager:
func _ready() -> void:
    QuanticNet.connection_state_changed.connect(_on_connection_state_changed)
    QuanticNet.peer_joined.connect(_on_peer_joined)
    QuanticNet.peer_left.connect(_on_peer_left)
    QuanticNet.state_received.connect(_on_state_received)
    QuanticNet.snapback_received.connect(_on_snapback_received)
    QuanticNet.custom_packet_received.connect(_on_custom_packet_received)
```

### `signal connection_state_changed(new_state: int)`

Emitido sempre que o cliente ou servidor muda seu estado na máquina de estados de conexão.

* **`new_state`**: Valor do enum `QuanticNet.ConnectionState` (`DISCONNECTED`, `CONNECTING`, `AUTHENTICATING`, `CONNECTED`, `FAILED`).

### `signal connection_failed_reason(error: int)`

Emitido quando a inicialização do host ou a tentativa de conexão do cliente falha.

* **`error`**: Código de erro padrão da Godot (`Error.ERR_CANT_CREATE`, `Error.ERR_UNAUTHORIZED`, etc.).

### `signal peer_joined(id: int)`

Emitido quando um novo peer conclui com sucesso a autenticação segura (DTLS/Handshake) e é integrado à simulação.

* **`id`**: Identificador numérico único do jogador (1 = Host/Servidor; 2..999 = Clientes).

### `signal peer_left(id: int)`

Emitido quando um jogador se desconecta (voluntariamente ou por timeout/kick).

* **`id`**: Identificador do peer que deixou o mundo.

### `signal state_received(owner: int, pos: Vector3, rot: Vector3, custom: int)`

*(Apenas Clientes)* Emitido imediatamente quando um snapshot de estado de entidade é recebido e validado pelo Core C++.

* **`owner`**: ID da entidade dona do estado.
* **`pos`**: Posição tridimensional oficial enviada pelo servidor.
* **`rot`**: Rotação em ângulos de Euler (Yaw/Pitch/Roll).
* **`custom`**: Tag/OpCode de estado customizado de 8 bits ($0 \dots 255$).

### `signal peer_sleep(owner: int)`

*(Apenas Clientes)* Notifica que uma entidade remota entrou em estado de *Dormancy* (repouso prolongado sem movimentação), economizando tráfego de rede.

* **`owner`**: ID da entidade adormecida.

### `signal pong_received(rtt: float, offset: float)`

*(Apenas Clientes)* Emitido a cada ciclo de medição de relógio contendo os valores calculados pelo algoritmo de sincronização temporal nativo.

* **`rtt`**: Tempo de ida e volta do pacote em milissegundos (*Round-Trip Time*).
* **`offset`**: Defasagem matemática do relógio local em relação ao relógio oficial do servidor (em ms).

### `signal snapback_received(seq: int, pos: Vector3, rot: Vector3, reason: int, replay_inputs: Array)`

*(Apenas Clientes)* Emitido quando o servidor rejeita ou corrige a predição local do cliente (Anti-Cheat / Reconciliação Física).

* **`seq`**: Número de sequência do input/estado que divergiu.
* **`pos`**: Posição autoritativa corrigida para a qual o cliente deve se ajustar.
* **`rot`**: Rotação autoritativa corrigida.
* **`reason`**: Código semântico de motivo (ex: `1` = *Clamp por Velocidade*, `2` = *Reject Fora dos Limites*).
* **`replay_inputs`**: Array contendo os comandos pendentes que o cliente deve re-simular a partir da nova posição.

### `signal input_tick(peer_id: int, sequence: int, input_mask: int, look_dir: Vector2)`

*(Apenas Servidor — Modo Command-Based)* Emitido no servidor a cada frame físico determinístico quando inputs de um cliente são processados pelo *Dynamic Jitter Buffer*.

* **`peer_id`**: ID do cliente autor do comando.
* **`sequence`**: Sequenciador numérico de 16 bits do input.
* **`input_mask`**: Máscara binária de botões pressionados.
* **`look_dir`**: Vetor bidimensional de direção de mira/câmera.

### `signal peer_rejected(id: int, reason: String, strikes: int)`

*(Apenas Servidor)* Emitido quando um pacote de cliente viola regras de validação (ex: teletransporte, atravessar chão, speedhack).

* **`id`**: ID do peer infrator.
* **`reason`**: Descrição textual da infração matemática detectada.
* **`strikes`**: Quantidade acumulada de advertências do peer (ao atingir `max_strikes`, o cliente é expulso).

### `signal custom_packet_received(peer_id: int, ptype: int, data: PackedByteArray)`

Emitido na recepção de pacotes customizados de gameplay (OpCodes $\ge 32$).

* **`peer_id`**: ID do remetente (1 se veio do servidor, ou ID do cliente se recebido no servidor).
* **`ptype`**: OpCode do pacote (byte de $32$ a $255$).
* **`data`**: Payload binário puro do pacote.

---

## 🎛️ Constantes Globais e Enums

### `enum ConnectionState`

```gdscript
enum ConnectionState {
    DISCONNECTED,   # Sem conexão ativa
    CONNECTING,     # Abrindo socket UDP / Handshake inicial
    AUTHENTICATING, # Trocando tokens de segurança DTLS
    CONNECTED,      # Conectado e operando no loop de simulação
    FAILED,         # Falha na inicialização ou recusa do host
}
```

### Modos de Operação

* `QuanticNet.MODE_STATE_BASED` (`0`): Sincronização orientada a estados com predição no cliente e interpolação contínua (ideal para MMOs, RPGs e jogos de mundo aberto).
* `QuanticNet.MODE_COMMAND_BASED` (`1`): Sincronização determinística baseada no envio de máscaras de input processadas no servidor (ideal para jogos competitivos rápidos e RTS).

---

## 🌐 Ciclo de Vida e Inicialização de Rede

### `host(port: int, secret: String, bind_ip: String = "*", max_peers: int = 32, config: Dictionary = {}) -> Error`

Inicializa o servidor autoritativo QuanticNet.

* **`port`**: Porta UDP de escuta (ex: `4242`).
* **`secret`**: Token compartilhado de autorização DTLS.
* **`bind_ip`**: Endereço IP de escuta (`"*"` para todas as interfaces de rede).
* **`max_peers`**: Limite máximo de jogadores simultâneos.
* **`config`**: Dicionário de configuração de domínio:
    * `"server_tick_rate"`: Taxa de transmissão da simulação em Hz (padrão: `20.0`).
    * `"grid_culling_size"`: Dimensão lateral de cada célula do `QNSpatialGrid` em metros (padrão: `50.0`).
    * `"world_bounds"`: Limite cúbico total da simulação em metros (padrão: `500.0`).
    * `"dormancy_threshold_ticks"`: Ticks sem movimento para ativar dormancy (padrão: `60`).
    * `"max_strikes"`: Violações toleradas antes do kick (padrão: `5`).
    * `"navigation_map"`: RID do mapa de navegação Godot para validação geométrica de NavMesh.
* **Retorno**: `OK` (0) em caso de sucesso, ou código de `Error`.

### `join(ip: String, port: int, secret: String, netem: bool = false, config: Dictionary = {}) -> int`

Conecta o cliente a um servidor QuanticNet.

* **`ip`**: Endereço IP do servidor.
* **`port`**: Porta UDP.
* **`secret`**: Token de segurança correspondente ao host.
* **`netem`**: Se `true`, ativa imediatamente o emulador de condições adversas de rede.
* **`config`**: Dicionário com configurações opcionais de NetEmul (`netem_loss`, `netem_latency`, etc.).

### `disconnect_net(is_exiting: bool = false) -> void`

Encerra a sessão de rede atual, fecha os sockets com segurança e restaura o estado para `DISCONNECTED`.

### Métodos de Inspeção

* `get_state() -> int`: Retorna o estado atual (`ConnectionState`).
* `is_server() -> bool`: Retorna `true` se a instância local for o Host/Servidor.
* `get_unique_id() -> int`: Retorna o ID único atribuído a esta instância (1 para o Servidor, $\ge 2$ para Clientes).
* `get_active_peers() -> Array`: Retorna a lista de IDs de todos os peers conectados no momento.

---

## ⏱️ Sincronização de Relógio e Telemetria Temporal

O QuanticNet implementa um algoritmo de filtragem estatística e convergência de relógio (*Clock Synchronization*) totalmente em C++:

### `is_clock_synced() -> bool`

Retorna `true` se o cliente já calculou amostras suficientes de RTT para estabelecer uma estimativa estável do relógio do servidor.

### `clock_rtt() -> float`

Retorna o tempo de ida e volta da rede em milissegundos (*Round-Trip Time*), filtrado e amortecido contra ruídos instantâneos.

### `clock_offset() -> float`

Retorna a diferença temporal em milissegundos entre o relógio da máquina local e o servidor ($T_{\text{server}} - T_{\text{local}}$).

### `server_time(now: int = -1) -> int`

Converte um timestamp local (em ms) para a estimativa precisa do tempo no servidor. Se nenhum argumento for passado, usa `Time.get_ticks_msec()`.

### `get_local_time() -> int`

Atalho para `Time.get_ticks_msec()`.

---

## 🏛️ Gerenciamento de Entidades e Perfis Dinâmicos (Server-Side)

### `QNEntityProfile`

Classe de configuração que define a prioridade de rede de uma entidade:

```gdscript
var profile = QNEntityProfile.new()
# init(tick_rate_hz: float, base_priority: float, spatial_culling_radius: float)
profile.init(20.0, 1.0, 100.0)
```

* **`tick_rate_hz`**: Frequência máxima de atualização de snapshots para esta entidade (ex: 60Hz para jogadores ativos, 5Hz para monstros distantes).
* **`base_priority`**: Peso do acumulador de prioridade (`QNPriorityAccumulator`).
* **`spatial_culling_radius`**: Raio de visibilidade em metros ao redor da entidade.

### `register_entity(entity_id: int, is_peer: bool, has_initial_state: bool, profile: RefCounted = null) -> void`

Registra uma entidade no particionamento espacial (`QNSpatialGrid`) e no histórico de mundo.

* **`entity_id`**: ID numérico da entidade (IDs $< 1000$ são jogadores; IDs $\ge 1000$ são NPCs/Props).
* **`is_peer`**: `true` se a entidade for controlada por um jogador conectado.
* **`has_initial_state`**: `true` se já possuir posição e rotação válidas no registro.
* **`profile`**: Instância de `QNEntityProfile`.

### `unregister_entity(entity_id: int) -> void`

Remove a entidade da simulação espacial e notifica os clientes que ela deixou o mundo.

### `update_entity_state(entity_id: int, pos: Vector3, rot: Vector3, custom_id: int = 0, ts: int = -1) -> void`

Atualiza a posição física oficial de uma entidade no servidor (usado para mover NPCs, monstros e objetos do ambiente).

### `change_entity_profile(entity_id: int, new_profile: RefCounted) -> void`

Altera dinamicamente o perfil de rede de uma entidade em tempo de execução (ex: reduzir a taxa de transmissão de um jogador que abriu o menu de inventário).

---

## 🕹️ Submissão de Movimento e Predição (Client-Side)

### `submit_state(pos: Vector3, rot: Vector3, custom: int, dt: float) -> void`

*(Modo State-Based)* Envia a predição local do avatar para o servidor assinar e rotear.

* **`pos`**: Posição predita pelo cliente no mundo 3D.
* **`rot`**: Rotação predita em ângulos de Euler.
* **`custom`**: Identificador customizado de estado (8 bits: $0 \dots 255$, ex: `0 = Idle`, `1 = Run`, `2 = Jump`).
* **`dt`**: Delta time do frame de física.

### `submit_input(sequence: int, input_mask: int, look_dir: Vector2) -> void`

*(Modo Command-Based)* Envia a máscara binária de comandos para processamento autoritativo no servidor.

### `remote_state(owner_id: int) -> Dictionary`

Consulta o `QNInterpBuffer` nativo para obter a posição e rotação interpoladas suaves de uma entidade remota no momento presente.

* **Retorno**: Dicionário contendo `{"pos": Vector3, "rot": Vector3, "custom": int}` ou `{}` caso não haja dados suficientes.

---

## 🛡️ Validação Autoritativa e Anti-Cheat (Server-Side)

### `set_server_validator(validator: RefCounted) -> void`

Injeta uma instância personalizada de validador de movimento no `QNHostSession`. Por padrão, o QuanticNet utiliza o `QNServerValidator` integrado, que verifica:

* **Velocidade Máxima e Aceleração:** Detecta *Speedhacks* e aplica correção elástica (*Clamp*) ou rejeição rígida (*Reject*).
* **Limites do Mundo:** Impede coordenadas fora da simulação.
* **Validação Geométrica de NavMesh:** Compara se a coordenada $(X, Z)$ está sobre a malha de navegação autorizada.

### `kick(peer_id: int) -> void`

Desconecta compulsoriamente um cliente da sessão.

---

## 🎯 Lag Compensation e Consultas no Passado (Rollback)

O servidor mantém um histórico contínuo dos últimos 60 frames físicos em memória contígua (`QNWorldHistoryBuffer`). Isto permite retroceder a cena no tempo exato em que o jogador disparou para validar colisões com *Zero Latency Feel*:

```gdscript
# Exemplo: Processando um tiro de Hitscan no Servidor
func process_hitscan(shooter_id: int, origin: Vector3, dir: Vector3, client_timestamp: int) -> void:
    var hit = QuanticNet.query_raycast(origin, dir, 100.0, client_timestamp)
    if not hit.is_empty():
        var target_id = hit["entity_id"]
        var hit_point = hit["position"]
        apply_damage(target_id, 25.0)
```

### `query_raycast(origin: Vector3, direction: Vector3, max_dist: float = -1.0, timestamp: int = -1) -> Dictionary`

Executa um teste de raio contra as caixas delimitadoras de todas as entidades rebobinadas para o `timestamp` especificado.

* **Retorno**: `{"entity_id": int, "position": Vector3}` ou `{}` se não houver impacto.

### `query_box(center: Vector3, extents: Vector3, timestamp: int = -1) -> Array`

Consulta todas as entidades presentes dentro de um volume cúbico no passado.

### `query_sphere(center: Vector3, radius: float, timestamp: int = -1) -> Array`

Consulta todas as entidades presentes dentro de uma esfera no passado.

---

## 📦 Mensageria Customizada de Gameplay (OpCodes)

Para trafegar eventos de jogo (dano, feitiços, inventário, troca de itens, chat) sem poluir o pipeline UDP de posição:

```gdscript
const OP_ATTACK = 33
const OP_CHAT = 34

# Enviando dano para um alvo específico (Confiável / Reliable)
var payload = PackedByteArray()
payload.encode_u32(0, target_id)
payload.encode_float(4, damage_amount)
QuanticNet.send_game_packet(target_id, OP_ATTACK, payload, true)

# Enviando para todos os jogadores conectados (Broadcast)
QuanticNet.send_game_packet(0, OP_CHAT, chat_bytes, true)
```

### `send_game_packet(to_peer: int, ptype: int, data: PackedByteArray = PackedByteArray(), reliable: bool = true) -> void`

* **`to_peer`**: ID do destinatário (use `0` para broadcast para todos).
* **`ptype`**: OpCode do pacote (deve ser $\ge 32$, pois opcodes $< 32$ são reservados internamente pelo Core).
* **`data`**: Bytes do payload.
* **`reliable`**: Se `true`, utiliza canal confiável garantido com confirmação de entrega; se `false`, envia em alta velocidade via UDP puro.

---

## 🧪 Emulação de Condições Adversas de Rede (NetEmul)

Permite simular conexões de internet de má qualidade diretamente em ambiente local de desenvolvimento para validar a resiliência da física e do Client-Side Prediction:

### `set_netem_config(loss_pct: float, latency_ms: int, jitter_ms: int, dup_pct: float = 0.0) -> void`

* **`loss_pct`**: Porcentagem de pacotes descartados propositalmente (ex: `10.0` para 10%).
* **`latency_ms`**: Latência artificial adicionada em milissegundos (ex: `150`).
* **`jitter_ms`**: Variação randômica de latência (ex: `30`).
* **`dup_pct`**: Porcentagem de pacotes duplicados.

### `toggle_netem() -> void`

Alterna rapidamente o emulador entre ligado (com valores padrão de estresse) e desligado.
