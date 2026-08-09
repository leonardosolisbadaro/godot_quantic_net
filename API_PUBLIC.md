# QuanticNet: API Pública e Documentação

Bem-vindo à documentação da API Pública do **QuanticNet**.
O QuanticNet é um plugin de netcode autoritativo para **Godot 4.7**, desenvolvido seguindo rígidos padrões de **Code-First**, **TDD (Test-Driven Development)** e **Clean Architecture**. Ele fornece DTLS, codec binário compacto, clock-sync avançado, predição de cliente, reconciliação (snapback) e simulação nativa de redes instáveis (Netem).

Esta documentação é voltada para desenvolvedores de jogos **3D** na Godot que irão consumir o plugin como uma caixa preta (plug and play), interagindo **apenas** através do Autoload. Nenhuma lógica visual (Mesh, UI, InputMap) vaza do plugin para a sua Engine.

---

## 🛠 Instalação e Ativação

1. Copie o diretório `addons/quantic_net/` para a raiz do seu projeto.
2. Acesse `Project` → `Project Settings` → `Plugins` e ative o **QuanticNet**.
3. O Autoload `QuanticNet` será registrado automaticamente. Este Singleton é o seu ponto único de contato (Single-Point of Entry) com todo o ecossistema.

---

## 🛡️ Homologação Cross-Platform Absoluta

> [!TIP]
> **Por que confiar na estabilidade do QuanticNet em C++?**
> A versão **0.6.0** mitigou com sucesso falhas clássicas de *Undefined Evaluation Order* (um bug obscuro de leitura de bytes no compilador MSVC do Windows que causava inversão silenciosa de eixos). Toda a nossa desserialização agora é rigidamente sequenciada de forma imperativa. Isso atesta que os pacotes do QuanticNet não sofrerão corrupção de matrizes independente do sistema operacional ou compilador utilizado na sua build final (GCC, Clang ou MSVC). O transporte é agnóstico e determinístico.

---

## 🌐 Máquina de Estados de Conexão

O status do roteamento de rede é monitorado em tempo real via enum `QuanticNet.ConnectionState`:

* `DISCONNECTED`: Nenhuma conexão ativa. O modo padrão de repouso.
* `CONNECTING`: Tentando transpor os soquetes e criptografia DTLS ao servidor (Cliente).
* `AUTHENTICATING`: Fase de handshake da Godot 4, validação do `secret` e injeção do Client ID (Cliente).
* `CONNECTED`: Conectado e autenticado com sucesso. Pronto para submissão de pacotes.
* `FAILED`: Falha crítica (verificar sinal `connection_failed_reason`).

**Transições Naturais:**

* Servidor (`host()`): Ao concluir o bind da porta e certificados, salta direto para `CONNECTED`.
* Cliente (`join()`): Evolui obrigatoriamente pelo funil `CONNECTING` → `AUTHENTICATING` → `CONNECTED`.

### `get_state() -> int`

Retorna o estado atual mapeado pelo enum.

### `is_server() -> bool`

Retorna `true` se a instância atual assumiu a autoridade de host.

---

## 💻 Funções Públicas (Comandos)

As seguintes assinaturas orquestram o Casos de Uso. O QuanticNet blinda sua `SceneTree` gerenciando todas as Extensões de Multiplayer internamente.

### `host(port: int, secret: String, bind_ip: String = "*", max_peers: int = 32, config: Dictionary = {}) -> int`

Sobe o servidor autoritativo em background. As chaves DTLS (RSA) são geradas em runtime para desenvolvimento ou importadas de `res://certs/` se encontradas.

* O `config` aceita parâmetros de calibração do validador (ex: `max_speed`, `hard_cap`).
* **Retorna:** Código `Error` da Godot (`OK` se sucesso).

### `join(ip: String, port: int, secret: String, netem: bool = false, config: Dictionary = {}) -> int`

Lança um socket assíncrono contra o Host.

* `netem`: Ativa a infraestrutura de distúrbios da rede (*Jitter, Delay, Loss* simulados), ideal para provar o sistema preditivo do seu jogo durante o *debug* em localhost.

### `submit_state(pos: Vector3, rot: Vector3, custom: int, dt: float) -> void`

Envia o frame preditivo do jogador local para o servidor (geralmente despachado do seu `_physics_process`).

* O servidor processa o Delta Time (`dt`), audita a validade (Anti-Speedhack) e insere no buffer de broadcast.

### `submit_input(sequence: int, input_mask: int, look_dir: Vector2) -> void`

**(Paradigma Command-Based):** Envia os comandos direcionais do jogador local (bits e direção visual) para o servidor de forma determinística.

* Deve ser disparado a cada iteração do seu laço físico local.
* O servidor acumulará estes pacotes num *Dynamic Jitter Buffer* e os drenará em passo fixo, blindando a simulação contra instabilidades de rede (jitter).

### `get_remote_state(owner_id: int) -> Dictionary`

Recupera o estado matematicamente interpolado no passado (com mitigação do Jitter Buffer) de um peer distante. Use este método para atualizar os seus *Meshes* visuais que representam os outros jogadores no seu mapa (em seu `_process`).

* **Retorna:** `{"pos": Vector3, "rot": Vector3, "custom_id": int}` ou dicionário vazio se aguardando dados.

### `get_registry() -> Dictionary`

Utilizado estritamente pelo Servidor (ou Monitor do Servidor). Retorna a cópia autoritativa atual de todos os peers conhecidos e validados, saltando o buffer de interpolação do cliente.

### `update_entity_state(entity_id: int, pos: Vector3, rot: Vector3, custom_id: int, ts: int) -> void`

Usado no Servidor para transmutar estados de NPCs e Props, notificando instantaneamente a rede.

### `disconnect_net(is_exiting: bool = false) -> void`

Expurga a máquina de estados, rompe o cache de referências nativas e desativa o interceptador com total higiene de memória. Use sempre que quiser fechar o jogo para o Menu Principal.

---

## 📡 Sinais Públicos (Event-Driven)

Para respeitar as diretrizes de Clean Architecture, não embuta Singletons da Godot na sua interface. Deixe que sua lógica escute aos sinais.

### `connection_state_changed(new_state: int)`

Despachado a cada transição no handshake mbedTLS ou Godot.

### `peer_joined(id: int)` / `peer_left(id: int)`

Garantido apenas *após* um cliente confirmar a sua identidade e ID ao servidor (Autenticação limpa).

### `peer_rejected(id: int, reason: String, strikes: int)`

Emitido no Servidor quando um pacote de um cliente é barrado pela validação anti-cheat (Speedhack, formatação inválida, spoofing de sequence). Se os `strikes` ultrapassarem o limite configurado (`max_strikes`), o cliente é imediatamente banido da sessão.

### `state_received(owner: int, pos: Vector3, rot: Vector3, custom: int)`

Broadcast contínuo disparado quando um pacote P-Frame / I-Frame novo chega do socket (antes de ser filtrado pela interpolação).

### `snapback_received(seq: int, pos: Vector3, rot: Vector3, reason: int, replay_inputs: Array)`

A correção autoritativa final. Se este sinal apitar no cliente local, a sua simulação preditiva foi cassada pelo Host. O seu avatar deverá ser "teletransportado" imediatamente para a `pos` confirmada.

### `pong_received(rtt_ms: float, offset_ms: float)`

Fornece dados crus de Ping (Round Trip Time) e descasamento de tempo do relógio sincronizado.

### `input_tick(peer_id: int, sequence: int, input_mask: int, look_dir: Vector2)`

Exclusivo do servidor no paradigma **Command-Based**. Emitido quando o *Dynamic Jitter Buffer* do servidor decide drenar os comandos pendentes deste `peer_id`, no exato momento que a física deve processá-los.
