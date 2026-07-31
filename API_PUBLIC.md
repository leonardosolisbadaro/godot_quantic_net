# QuanticNet: API Pública

Bem-vindo à documentação da API Pública do **QuanticNet**.
O QuanticNet é um plugin de netcode autoritativo para **Godot 4.7**, desenvolvido seguindo rígidos padrões de **Code-First**, **TDD (Test-Driven Development)** e **Clean Architecture**. Ele fornece DTLS, codec binário compacto (19 Bytes), clock-sync, predição de cliente, reconciliação (snapback) e simulação de redes instáveis (Netem).

Esta documentação é voltada para desenvolvedores de jogos **3D** na Godot que irão consumir o plugin como uma caixa preta (plug and play), interagindo **apenas** através do Autoload.

## Instalação e Ativação

1. Copie o diretório `addons/quantic_net/` para a raiz do seu projeto.
2. Acesse `Project` → `Project Settings` → `Plugins` e ative o **QuanticNet**.
3. O Autoload `QuanticNet` será registrado automaticamente, atuando como o ponto único de entrada (Single-Point of Entry) da API.

---

## Estados de Conexão

A máquina de estados da conexão de rede é representada pelo enum `QuanticNet.ConnectionState`:

* `DISCONNECTED`: Sem conexão ativa.
* `CONNECTING`: Tentando se conectar ao servidor (Cliente).
* `AUTHENTICATING`: Negociando o `secret` (Cliente).
* `CONNECTED`: Conectado e autenticado com sucesso.
* `FAILED`: Falha na conexão (verificar sinal de razão).

**Transições:**

* O servidor (`host`) vai imediatamente para `CONNECTED` após iniciar com sucesso.
* O cliente (`join`) transita sequencialmente: `CONNECTING` → `AUTHENTICATING` → `CONNECTED` (ou `FAILED`).

### `get_state() -> int`

Retorna o estado atual da conexão.

### `is_server() -> bool`

Retorna `true` se a instância atual estiver operando como servidor (host).

---

## Funções Públicas

As seguintes funções expõem os Casos de Uso do plugin. Todas as dependências internas (ex.: `QNHostSession`, `QNWirePeer`) estão encapsuladas na Infraestrutura, em conformidade com a Clean Architecture. Use **apenas** o Autoload.

### `host(port: int, secret: String, bind_ip: String = "*", max_peers: int = 32) -> int`

Inicia um servidor DTLS na porta informada. Retorna `OK` em caso de sucesso.

* `secret`: Chave compartilhada para autorizar conexões de clientes.

### `join(ip: String, port: int, secret: String, netem: bool = false) -> int`

Conecta um cliente a um servidor DTLS. Retorna `OK` em caso de sucesso.

* `netem`: Se `true`, ativa a simulação interna de problemas de rede (jitter, loss) definida no plugin.

### `submit_state(pos: Vector3, rot: Vector3, custom: int, dt: float) -> void`

Envia o estado atual do cliente (player predito) para o servidor. Este estado vai para um buffer local para possível replay em caso de *snapback*.

* O servidor recebe e processa (valida a predição).
* Deve ser chamado periodicamente (ex.: dentro do `_process` ou `_physics_process`).

### `remote_state(owner_id: int) -> Dictionary`

Recupera o estado interpolado mais recente de um peer remoto. Útil para aplicar sobre os avatares (cubos/jogadores) controlados pelos outros peers.

* Retorna um dicionário `{"pos": Vector3, "rot": Vector3, "custom": int}` ou vazio se não houver dados.

### `loss_of(owner_id: int) -> float`

Retorna a porcentagem de perda de pacotes de um cliente específico. (Válido apenas para peers autenticados).

### `is_clock_synced() -> bool`

Verifica se o relógio do cliente concluiu o passo inicial de sincronização com o servidor.

### `get_registry() -> Dictionary`

Retorna o registro (registry) com dados conhecidos das conexões (apenas válido no servidor).

### `kick(peer_id: int) -> void`

(Servidor) Desconecta forçadamente um peer.

### `toggle_netem() -> void`

(Cliente) Ativa/Desativa dinamicamente a emulação de atrasos e jitter (Netem).

---

## Sinais Públicos

Os sinais são usados para orquestrar as instâncias nativas da cena reagindo aos eventos de rede, evitando forte acoplamento (UI-Bound Logic).

### `connection_state_changed(new_state: int)`

Emitido sempre que a conexão evolui (ex.: `CONNECTING` → `AUTHENTICATING`).

### `connection_failed_reason(error: int)`

Emitido se o `host` ou `join` falhar, passando o código de erro (`Error` do Godot).

### `peer_joined(id: int)`

Emitido quando um peer se conecta (após ser completamente autenticado no servidor).

* No servidor: emite para cada cliente validado.
* No cliente: emite quando a instância de rede toma conhecimento de um novo jogador no mundo.

### `peer_left(id: int)`

Emitido quando um peer se desconecta.

### `state_received(owner: int, pos: Vector3, rot: Vector3, custom: int)`

Emitido ao processar pacotes customizados contendo estados do mundo.

* No servidor: dispara a cada estado recebido de clientes (onde ocorre a validação).
* No cliente: estado interpolado chegando via broadcast do servidor. É mais comum consumir a função `remote_state(owner)` no cliente, mas o sinal atende event-driven archs.

### `pong_received(rtt_ms: float, offset_ms: float)`

Emitido no cliente durante o processo de sincronização de relógio (RTT - *Round Trip Time*).

### `snapback_received(seq: int, pos: Vector3, rot: Vector3, reason: int, replay_inputs: Array)`

Emitido no cliente quando o servidor rejeita a predição local e exige uma correção forçada de estado (snapback).

* `replay_inputs`: Array de inputs (do `QNInputBuffer` local) para reaplicar na simulação.

---

## Padrões de Uso (Bare Metal)

Para garantir flexibilidade máxima para a árvore de cenas, o QuanticNet não amarra objetos 3D automaticamente. Abaixo um esqueleto de consumo do plugin, derivado do `demo_main.gd`.

### Exemplo Base (Servidor e Cliente unificado)

```gdscript
extends Node3D

var cubes := {} # peer_id -> MeshInstance3D

func _ready() -> void:
    # 1. Registrar eventos ANTES de conectar.
    QuanticNet.peer_joined.connect(_on_peer_joined)
    QuanticNet.peer_left.connect(_on_peer_left)
    QuanticNet.state_received.connect(_on_state)
    QuanticNet.snapback_received.connect(_on_snapback)

    # 2. Iniciar Host ou Join
    if "--server" in OS.get_cmdline_user_args():
        QuanticNet.host(4242, "secret")
    else:
        QuanticNet.join("127.0.0.1", 4242, "secret")

func _on_peer_joined(id: int) -> void:
    var cube = MeshInstance3D.new()
    cube.mesh = BoxMesh.new()
    add_child(cube)
    cubes[id] = cube

func _on_peer_left(id: int) -> void:
    if cubes.has(id):
        cubes[id].queue_free()
        cubes.erase(id)

func _process(delta: float) -> void:
    if QuanticNet.is_server():
        return

    # Submeter predição do jogador local
    var my_id = multiplayer.get_unique_id()
    if cubes.has(my_id):
        var move = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
        cubes[my_id].position += Vector3(move.x, 0, move.y) * 2.0 * delta
        QuanticNet.submit_state(cubes[my_id].position, cubes[my_id].rotation, 0, delta)

    # Aplicar estados remotos (interpolados pelo plugin) aos outros avatares
    for id in cubes.keys():
        if id != my_id:
            var s = QuanticNet.remote_state(id)
            if not s.is_empty():
                cubes[id].position = s["pos"]
                cubes[id].rotation = s["rot"]

func _on_state(owner: int, pos: Vector3, rot: Vector3, _custom: int) -> void:
    # No servidor, o estado recém validado altera o cubo na memória
    if QuanticNet.is_server() and cubes.has(owner):
        cubes[owner].position = pos
        cubes[owner].rotation = rot

func _on_snapback(seq: int, pos: Vector3, rot: Vector3, reason: int, replay: Array) -> void:
    print("Correção forçada do servidor. (Replay inputs: %d)" % replay.size())
```

---

## Integração com TDD (bitwes/Gut)

O QuanticNet é projetado via **TDD (Test-Driven Development)**, e seu projeto cliente deve continuar essa tradição. Se você estiver escrevendo scripts (`Controllers` ou cenas) que dependem do QuanticNet, utilize mocks do `bitwes/Gut`.

* **Regra de Ouro**: Instancie ou simule a camada QuanticNet sem subir um servidor de rede real, controlando as dependências.
* **Referência Viva**: Para visualizar fluxos completos (como os estados mudam e afetam os peers), consulte os testes de integração do plugin: `tests/integration/test_quantic_net_api.gd` e `tests/integration/test_server_two_clients.gd`.
