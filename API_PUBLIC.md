# 📚 QuanticNet - Referência da API Pública

O **QuanticNet** é uma extensão C++ (GDExtension) de Netcode Autoritativo projetada para a Godot Engine 4.7+.
Sua arquitetura foi desenvolvida para orquestrar mundos dinâmicos complexos (MMO, Battle Royales ou jogos competitivos) eliminando Jitter, poupando a banda de rede (*Delta Encoding*, *Spatial Culling*) e resolvendo lógicas de combate instantaneamente com *Lag Compensation* (Rollback).

Esta documentação serve como referência completa para a utilização do Singleton **`QuanticNet`**, a única porta de entrada (*Single-Point of Entry*) que você precisará para se comunicar com todo o motor interno em C++.

---

## 📡 Sinais (Event-Driven API)

O QuanticNet é desenhado para não bloquear a Godot. Quando algo importante acontece nas entranhas do C++, um sinal será emitido no Autoload. Conecte-se a eles (`QuanticNet.sinal.connect(meu_metodo)`) para injetar lógicas.

### `connection_state_changed(new_state: int)`

* **Descrição**: Emitido sempre que a máquina de estados interna muda.
* **Parâmetros**:
    * `new_state`: O valor atual da conexão (ex: `ConnectionState.CONNECTING`, `CONNECTED`, `DISCONNECTED`).
* **Sugestão de uso**: Atualizar as telas de loading UI para informar ao usuário que o jogo está "Conectando...", "Autenticando..." ou "Conectado".

### `connection_failed_reason(error: int)`

* **Descrição**: Disparado se a rede falhar de forma drástica antes ou durante uma conexão (ex: Porta bloqueada, timeout severo, erro de certificado DTLS).
* **Parâmetros**: `error` - O `Error` padrão da Godot.

### `peer_joined(id: int)`

* **Descrição**: Um novo jogador se conectou **e foi autenticado com sucesso** (passou pelo crivo do *secret*).
* **Parâmetros**: `id` - O ID único da Godot para o peer (`1` para o Servidor).
* **Sugestão de uso**: Usado no Servidor para inicializar os dados daquele jogador no banco de dados e instanciar sua Entidade base no Mundo (invocando `QuanticNet.register_entity`).

### `peer_left(id: int)`

* **Descrição**: O servidor confirmou que um jogador desconectou ou perdeu a conexão fatalmente. O QuanticNet já apaga o rastro deste jogador internamente, não se preocupe com vazamentos.
* **Parâmetros**: `id` - O ID único do peer que foi embora.
* **Sugestão de uso**: Limpar o `Mesh` do jogador instanciado no seu cenário (`queue_free()`) e removê-lo de listas de party/squad.

### `peer_rejected(id: int, reason: String, strikes: int)`

* **Descrição**: *(Apenas Servidor)*. Emite quando um peer enviou um input fisicamente impossível ou inválido, reprovado pelo validador.
* **Parâmetros**:
    * `id`: O Infrator.
    * `reason`: Mensagem interna de qual regra foi quebrada (Ex: *"Speedhack detectado"*).
    * `strikes`: A contagem de penalidades que este jogador acumulou. (Ao estourar o limite, o plugin desconecta-o à força).
* **Sugestão de uso**: Enviar uma mensagem silenciosa via Discord Webhook para administradores relatando cheaters passivos.

### `state_received(owner: int, pos: Vector3, rot: Vector3, custom: int)`

* **Descrição**: *(Apenas Cliente)* Emitido no instante em que o cliente recebe um pacote novo do servidor, *antes* da interpolação suave, contendo dados não mascarados (raw).
* **Parâmetros**:
    * `owner`: De quem é esse estado.
    * `pos` / `rot`: Transform cru oficial daquele frame.
    * `custom`: Um inteiro pequeno (8-bits) que viaja na banda mínima para animar o personagem (Ex: Estado de correr, atirar, deitar).
* **Sugestão de uso**: Utilizar o `custom` para repassar à StateMachine de Animação (AnimationTree) do inimigo, para que o inimigo atire visualmente.

### `snapback_received(seq: int, pos: Vector3, rot: Vector3, reason: int, replay_inputs: Array)`

* **Descrição**: *(Apenas Cliente)* Penalização máxima. A sua simulação de "Client-Side Prediction" (fazer seu avatar se mover liso sem esperar a rede) ficou completamente divergente do Servidor Autoritativo.
* **Parâmetros**:
    * `seq`: O sequence_number em que o erro ocorreu.
    * `pos` / `rot`: As posições REAIS e autoritativas que você deve assumir imediatamente.
* **Sugestão de uso**: Sobrescrever o `global_position` do seu `CharacterBody3D` instantaneamente (puxando o jogador de volta) para consertar a dessincronia.

### `pong_received(rtt_ms: float, offset_ms: float)`

* **Descrição**: Evento contínuo que expõe os cálculos internos da máquina de Clock Sync (Sincronização de Relógios).
* **Parâmetros**:
    * `rtt_ms`: O Round Trip Time estabilizado.
    * `offset_ms`: A diferença matemática de tempo que separa o hardware do cliente do relógio atômico do servidor.
* **Sugestão de uso**: Ler o RTT para injetar o "Ping: 45ms" no canto da tela do jogador local.

---

## 🌐 Conexão e Ciclo de Vida

Métodos para gerenciar o estado global da rede.

### `host(port: int, secret: String, bind_ip: String = "*", max_peers: int = 32, config: Dictionary = {}) -> int`

Sobe o servidor e abre a porta para o mundo. Prepara toda a topologia base do QuanticNet em background.

* **Parâmetros:**
    * `port`: A porta UDP (ex: `4242`).
    * `secret`: String secreta (Handshake token). Jogadores tentando conectar precisam enviar exatamente essa string para não serem silenciados no socket (Anti-DDoS base).
    * `bind_ip`: Por padrão `"*"`. Especifique se estiver roteando subredes complexas.
    * `max_peers`: Limite rígido da engine.
    * `config`: Dicionário extenso de customizações (ex: `auth_timeout`).
* **Retorno:** A flag `OK` (0) se a porta abriu com sucesso.
* **Sugestão de uso:** Amarrado a um botão "Criar Servidor" ou inicializado via chamadas *Headless* (CLI) em provedores de Cloud.

### `join(ip: String, port: int, secret: String, netem: bool = false, config: Dictionary = {}) -> int`

Abre uma conexão para interligar-se com um Host.

* **Parâmetros:**
    * `ip` / `port`: Credenciais de roteamento.
    * `secret`: O Token que autoriza você a passar pela porta.
    * `netem`: Parâmetro exclusivo para debugar. Se `true`, a Engine C++ injeta latência forçada sobre o seu roteamento UDP (para você testar se o *Prediction* e o *InterpBuffer* funcionam com conexões precárias).
* **Sugestão de uso:** O botão "Entrar" na sua UI principal.

### `disconnect_net(is_exiting: bool = false) -> void`

Encerra tudo de modo seguro, deletando a cache alocada na memória RAM, interrompendo as instâncias de Jitter Buffer e limpando os Nodes da Godot (limpeza higiênica).

* **Parâmetros:** `is_exiting` impede que o Tree mude os Singletons se você já fechou o software por completo (quit).
* **Sugestão de uso:** Ao apertar "Voltar para o Menu Principal", execute essa função para garantir que não haja sobras se conectar a outro Host na mesma janela.

### Funções Auxiliares Comuns

* `get_state() -> int`: Enumera o estágio atual da conexão (ex: Autenticando...).

* `is_server() -> bool`: Verifica se você é a Autoridade.
* `get_unique_id() -> int`: Retorna o seu ID mágico no multiplayer.
* `get_local_time() -> int`: Atalho para `Time.get_ticks_msec()`.
* `get_server_time() -> int`: O milissegundo real do servidor.

---

## 🏛️ Gestão Espacial e de Entidades (Server)

O servidor precisa saber quem existe no universo 3D, para decidir quem deve enviar para quem. Isso otimiza o uso da banda de rede em mundos massivos (Culling).
Todas estas funções só devem ser chamadas se `is_server() == true`.

### O `QNEntityProfile`

Antes de registrar qualquer item, você cria perfis. Um perfil diz à engine C++ como um grupo de Entidades deve se comportar na rede:

```gdscript
var prop_profile = QNEntityProfile.new()
# (tick_rate: Hz, priority_weight: float, culling_radius: float)
prop_profile.init(5.0, 0.5, 20.0)
```

* `tick_rate`: 5 vezes ao segundo o servidor vai atualizar a posição desse baú.

* `priority`: Um baú caindo importa menos (0.5) que o tiro (3.0) do jogador adversário.
* `culling`: Apenas jogadores num raio de `20.0m` recebem pacotes de movimentação desse prop.

### `register_entity(entity_id: int, is_peer: bool, has_initial_state: bool, profile: RefCounted = null) -> void`

Grava uma identidade autoritativa na memória do servidor.

* **Parâmetros**:
    * `entity_id`: O ID do jogador remetente, ou um ID gerado proceduralmente (> 1000) caso seja um prop.
    * `is_peer`: `true` se for um "Humano" (Cliente com conexão). Isso diz ao QuanticNet que deve esperar *Inputs* desse ID. Se `false` o QuanticNet espera que o próprio servidor mexa esse cara via `update_entity_state()`.
    * `profile`: A estipulação técnica da entidade (`QNEntityProfile`).
* **Sugestão de Uso**: Chamar no callback `peer_joined` do Servidor, ou logo após invocar `instantiate()` num Monstro recém spawnado.

### `unregister_entity(entity_id: int) -> void`

Mata a entidade. Interrompe envios e tira do Grid de Colisões Históricas (Spatial Grid). O Servidor propaga imediatamente um `TYPE_PEER_LEFT` notificando todos os clientes num raio válido a destruírem a visualização desse ID.

### `change_entity_profile(entity_id: int, new_profile: RefCounted) -> void`

Transmuta a hierarquia de atualização da entidade na base de dados.

* **Sugestão de uso:** Se o Monstro entrar em combate (Aggro), mude o profile dele de `Idle_Profile` (5Hz) para `Aggro_Profile` (30Hz) para movimentação suave; economizando banda enquanto o monstro vagava em paz.

### `update_entity_state(entity_id: int, pos: Vector3, rot: Vector3, custom_id: int = 0, ts: int = -1) -> void`

O método que o Servidor usa para dizer *"Ei, o monstro de ID 5055 acabou de andar para o Node (X,Y,Z)"*. Ao preencher este campo, no próximo "Tick", o Host enviará via Delta Encoding essa alteração minúscula e suavizada para os clientes.

---

## 🏔️ Culling por Regiões

Jogos como MMOs não usam apenas o `culling_radius`. Eles usam ilhas e calabouços paralelos.

### `add_region(region_id: int, center: Vector3, extents: Vector3) -> void`

Cria um "Cubo Invisível" Axis-Aligned no mundo. Toda entidade dentro dele recebe e transmite dados exclusivistas, isolando a rede de uma dungeon do mundo exterior.

### `remove_region(region_id: int) -> void`

Deleta a regra de isolamento da ilha.

---

## 🕹️ Input e Sincronização de Estado (Cliente -> Servidor)

Como os clientes movem o jogo.

### `submit_state(pos: Vector3, rot: Vector3, custom: int, dt: float) -> void`

Utilizado no paradigma de *State-Based Prediction*.
O cliente resolve a colisão dele instantaneamente com `move_and_slide()` e então dispara um `submit_state` ao servidor avisando onde ele acha que deveria estar. O servidor rodará os validadores.

* **Parâmetros**: `custom` pode transportar status binários velozes (bits de animação/estado).
* **Sugestão de uso**: Usar rigorosamente no seu `_physics_process` local para cada frame renderizado.

### `submit_input(sequence: int, input_mask: int, look_dir: Vector2) -> void`

Utilizado no paradigma rígido de *Command-Based*. (Normalmente usado em jogos E-sports 2D / Figthing Games). O cliente envia unicamente qual teclado foi pressionado (`input_mask`) e o servidor roda a simulação e manda de volta a posição exata. (Note que este método desliga o Client-Side prediction puro).

### `get_remote_state(owner_id: int) -> Dictionary`

O método **mais importante do Cliente**. Ele invoca o `QNInterpBuffer` do C++, que resgata a matemática oficial, lendo pacotes antigos, calculando um meio-termo linear perfeito (Lerp / Slerp / Quaternions) baseado em Delays precisos, e devolve a exata posição milimétrica fluída.

* **Sugestão de uso:** No seu `_process` remoto, rode `visual_mesh.position = QuanticNet.get_remote_state(id)["pos"]`. Simples assim. O movimento fica liso!

---

## 🎯 Lag Compensation e Queries no Passado

Quando alguém dá um tiro na cabeça em alta velocidade, as latências divergem as telas. O servidor resolve injetando a hitbox milissegundos no passado graças ao Rollback.

### `query_raycast(origin: Vector3, direction: Vector3, max_dist: float = -1.0, timestamp: int = -1) -> Dictionary`

O Servidor simula um Raycast (Tiro em Linha Reta) regredindo as hitboxes com base no `timestamp` fornecido pelo Ping de quem atirou.

* **Retorno:** Um dicionário com `hit: bool`, `entity_id` e a distância (`distance`) se houver impacto no "fantasma" do passado.
* **Sugestão de uso:** Para armas Snipers / Hitscan. O Cliente envia "Atirei em Timestamp 5000", o servidor busca em `query_raycast(.., 5000)` se o inimigo realmente cruzou a mira naquela fração exata. E a validação é perfeita.

### `query_box(center: Vector3, extents: Vector3, timestamp: int = -1) -> Array`

Verifica quem estava num Cubo AABB em um determinado passado.

* **Sugestão de uso:** Magias em área quadradas, armadilhas. Retorna um `Array` de `entity_id`.

### `query_sphere(center: Vector3, radius: float, timestamp: int = -1) -> Array`

Verifica quem estava num Raio esférico em um determinado passado.

* **Sugestão de uso:** O Dano em Área (Splash Damage) super preciso de um Foguete que demorou a chegar ao destino.

---

## 🧪 Engenharia do Caos e Netem

### `toggle_netem()`

Inverte rapidamente a simulação de Redes Lixo (Netem). Se aceso, aplica atrasos e dropps pré-configurados pela API no seu peer interno.

### `set_netem_config(loss_pct: float, latency_ms: int, jitter_ms: int, dup_pct: float = 0.0) -> void`

Ajusta a intensidade.

* `loss_pct`: (0-100%) Deleta pacotes da memória forçando *Extrapolation*.
* `latency_ms`: Atrasa todos os UDPs simulando longas distâncias físicas.
* `jitter_ms`: Flutua aleatoriamente os atrasos de `latency_ms`, forçando o "Jitter Buffer" ao limite.
* `dup_pct`: (0-100%) Multiplica um pacote e atira 2 cópias pra frente testando a filtragem sequencial da Engine.
* **Sugestão de uso:** Se o seu jogo fica "pulando/estranho" testando em localhost (0ms delay) assim que você injeta 150ms e 10% loss de Netem, você sabe que seu Client-Side Prediction está fracassando. Esse é o derradeiro teste de AAA.

---
*API Autogerada para QuanticNet 0.7.0 (Stable).*
