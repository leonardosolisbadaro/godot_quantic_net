# QuanticNet: API Pública

Bem-vindo à documentação da API Pública do **QuanticNet**.
O QuanticNet é um plugin de netcode autoritativo para **Godot 4.7**, desenvolvido seguindo rígidos padrões de **Code-First**, **TDD (Test-Driven Development)** e **Clean Architecture**. Ele fornece DTLS, codec binário compacto, clock-sync avançado, predição de cliente, reconciliação (snapback) e simulação nativa de redes instáveis (Netem).

Esta documentação é voltada para desenvolvedores de jogos **3D** na Godot que irão consumir o plugin como uma caixa preta (plug and play), interagindo **apenas** através do Autoload. Nenhuma lógica visual (Mesh, UI, InputMap) vaza do plugin para a sua Engine.

---

## 🛠 Instalação e Ativação

1. Copie o diretório `addons/quantic_net/` para a raiz do seu projeto.
2. Acesse `Project` → `Project Settings` → `Plugins` e ative o **QuanticNet**.
3. O Autoload `QuanticNet` será registrado automaticamente. Este Singleton é o seu ponto único de contato (Single-Point of Entry) com todo o ecossistema.

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

## ⏱️ EntityProfiles (Tick Híbrido)

O motor do QuanticNet não envia snapshots unificados. Diferentes entidades são atualizadas em frequências assimétricas para comprimir o uso da banda (Hybrid Ticking).
A classe imutável `QuanticNet.EntityProfile` (exposta diretamente pelo Autoload) rege a cadência, definindo `tick_rate_hz`, `priority_weight` e `culling_radius`.

### Presets de Fábrica

Você deve repassar o profile durante a vida útil das entidades.

* `QuanticNet.EntityProfile.preset_high_frequency()`: 60Hz. Uso obrigatório para jogadores e projéteis rápidos.
* `QuanticNet.EntityProfile.preset_standard()`: 20Hz. Padrão MMO para monstros e NPCs comuns.
* `QuanticNet.EntityProfile.preset_low_frequency()`: 5Hz. Para Props móveis de baixo impacto (plataformas).
* `QuanticNet.EntityProfile.preset_static()`: Event-Driven. Só transmite a banda ao sofrer mutação.

---

## 💻 Funções Públicas (Comandos)

As seguintes assinaturas orquestram o Casos de Uso. O QuanticNet blinda sua `SceneTree` gerenciando todas as Extensões de Multiplayer internamente.

### `host(port: int, secret: String, bind_ip: String = "*", max_peers: int = 32) -> int`

Sobe o servidor autoritativo em background. As chaves DTLS (RSA) são geradas em runtime para desenvolvimento ou importadas de `res://certs/` se encontradas.

* **Retorna:** Código `Error` da Godot (`OK` se sucesso).

### `join(ip: String, port: int, secret: String, netem: bool = false) -> int`

Lança um socket assíncrono contra o Host.

* `netem`: Ativa a infraestrutura de distúrbios da rede (*Jitter, Delay, Loss* simulados), ideal para provar o sistema preditivo do seu jogo durante o *debug* em localhost.

### `submit_state(pos: Vector3, rot: Vector3, custom: int, dt: float) -> void`

Envia o frame preditivo do jogador local para o servidor (geralmente despachado do seu `_physics_process`).

* O servidor processa o Delta Time (`dt`), audita a validade (Anti-Speedhack) e insere no buffer de broadcast.

### `remote_state(owner_id: int) -> Dictionary`

Recupera o estado matematicamente interpolado no passado (com mitigação do Jitter Buffer) de um peer distante. Use este método para atualizar os seus *Meshes* visuais que representam os outros jogadores no seu mapa.

* **Retorna:** `{"pos": Vector3, "rot": Vector3, "custom": int}` ou dicionário vazio se aguardando dados.

### `register_entity(id: int, is_player: bool, is_local: bool, profile: QNEntityProfile = null) -> void`

Registra manualmente uma entidade no registro autoritativo da sessão (ex: Props criados no servidor). No cliente, o QuanticNet registra os peers remotos automaticamente.

### `unregister_entity(id: int) -> void`

Remove a entidade do registro, parando o broadcast e liberando o acumulador de prioridade.

### `get_telemetry(peer_id: int) -> QNTelemetryAggregator`

Obtém o objeto matemático de telemetria da conexão para a extração de Packet Loss, RTT Max/Avg, etc. (Usado no painel da demo).
No cliente, `peer_id` costuma ser `1` (Servidor).

### `disconnect_net(is_exiting: bool = false) -> void`

Expurga a máquina de estados, rompe o cache de referências nativas do `MultiplayerAPIExtension` e desativa o interceptador com total higiene de memória. Use sempre que quiser fechar o jogo para o Menu Principal.
*Nota:* Se o jogo estiver fechando pelo OS, passe `is_exiting = true` para que ele não tente sobrepor a `SceneTree` do motor em pleno colapso.

### `toggle_netem() -> void`

Ativa ou desativa a simulação de caos UDP em runtime no cliente.

---

## 📡 Sinais Públicos (Event-Driven)

Para respeitar as diretrizes de Clean Architecture, não embuta Singletons da Godot na sua interface. Deixe que sua lógica escute aos sinais.

### `connection_state_changed(new_state: int)`

Despachado a cada transição no handshake mbedTLS ou Godot.

### `connection_failed_reason(error: int)`

Avisa o momento de destruição do socket.

### `peer_joined(id: int)` / `peer_left(id: int)`

A infraestrutura garante que esses sinais só sejam emitidos *após* um cliente confirmar a sua identidade e ID ao servidor (Autenticação limpa) e processa a propagação transparente.

### `state_received(owner: int, pos: Vector3, rot: Vector3, custom: int)`

Broadcast do servidor. Muito consumido em arquitecturas reativas em vez do tradicional *polling* via `remote_state()`.

### `snapback_received(seq: int, pos: Vector3, rot: Vector3, reason: int, replay_inputs: Array)`

A correção autoritativa final. Se este sinal apitar no cliente local, a sua simulação foi cassada pelo Host. O seu avatar deverá ser "teletransportado" imediatamente para `pos` e `rot` confirmados, e os inputs do array reaplicados massivamente para mascarar a percepção do atraso.

### `pong_received(rtt_ms: float, offset_ms: float)`

Emitido toda vez que o QuanticNet sincroniza seu relógio NTP com o servidor. Fornece dados crus de Ping e descasamento de tempo.

---

## 🧪 Boas Práticas e Prevenção de Vazamento (TDD)

O plugin é coberto por +100 testes utilizando **bitwes/Gut**. Caso venha a escrever testes que importem componentes core (ex: simuladores em headless), invoque `disconnect_net()` rigorosamente ao fim de cada escopo ou teste.

As referências circulares em extensões de C++ da Godot (como a `MultiplayerAPI`) seguram hard-references. O `disconnect_net()` efetua um *graceful teardown* evitando que a console engula *ObjectDB Leaks* ou acuse o famigerado `ERR_INVALID_PARAMETER` ao fechar instâncias consecutivas.
