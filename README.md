# QuanticNet (Core Infrastructure)

**Versão Atual:** `0.8.0` (Struct POD Migration & Memory Optimization)

O **QuanticNet** é um ecossistema de rede *plug-and-play* autoritativo e de altíssimo desempenho, construído nativamente em **C++** (GDExtension) para a **Godot Engine 4.7**.

> ⚠️ **Decisão Arquitetural:** Este repositório foca ESTRITAMENTE no desenvolvimento da infraestrutura *Bare Metal*. Todo o desenvolvimento de domínios concretos, Grid Systems, Chunking e demos de "3D Open World MMO" foi migrado para o repositório externo [godot_quantic_net_demos](https://github.com/leonardosolisbadaro/godot_quantic_net_demos).

A arquitetura resolve as barreiras físicas da infraestrutura multiplayer (Client-Side Prediction, Server-Side Reconciliation, Snapshot Interpolation e Culling Espacial), permitindo a criação de domínios puros através do paradigma **Code-First** e **Clean Architecture**, sem qualquer acoplamento com a árvore visual (`SceneTree`) da Godot.

---

## 🚀 Core Features (Os 4 Pilares do QuanticNet)

- **Performance Bare-Metal (C++):** Todo o transporte via sockets (ENet/DTLS), criptografia, Culling Espacial (`QNSpatialGrid`) e cálculos vetoriais densos rodam nativamente em GDExtension. A API consumida, contudo, permanece 100% GDScript, limpa e declarativa.
- **Dual Paradigm (State ou Command-Based):** Você tem controle absoluto. Opte pelo envio direto de estados preditivos (ideal para jogos ágeis e PvE) ou adote o fluxo rigoroso de *Inputs* blindado por um **Dynamic Jitter Buffer** autoritativo no servidor (para cenários competitivos e eSports).
- **Sincronização de Elite:** A engine resolve nativamente as dores clássicas do netcode: *Client-Side Prediction* (Zero Input Lag), *Lag Compensation* (hitscan com rebobinamento através do `QNWorldHistoryBuffer`), e *Delta Compression* elástica guiada por prioridade visual (Priority Accumulator).
- **Anti-Cheat Determinístico:** O servidor não é cego. Tentativas de *Speedhack* ou teletransporte fora dos limites acionam matematicamente as correções absolutas da engine (*Snapbacks* visuais) ou o banimento por infrações acumuladas (*Strikes*).

---

## 🧭 O Caminho Adiante

O desenvolvimento do QuanticNet é guiado de forma transparente. Para entender para onde estamos caminhando, consulte:

- **[TODO.md](./TODO.md):** Para acompanhar as fases táticas de curto prazo e os *Pull Requests* ativos (como as otimizações de *Worker Threads*).
- **[ROADMAP_MMO.md](./ROADMAP_MMO.md):** Para compreender a visão arquitetural de longo prazo do motor em C++ (Networked Physics, Structs POD e Server Meshing).

---

## 📚 Documentação e Guias

- **[A Demo Laboratório Interno](./addons/quantic_net/demo/demo_main.gd)**: O arquivo `demo_main.gd` deste repositório está oficialmente **congelado em escopo**. Ele serve exclusivamente como um laboratório rústico de testes unitários end-to-end e um tutorial cru de como consumir a API pública (sem mecânicas complexas, sem paredes, sem assets).
- **[Constituição GEMINI.md](./GEMINI.md)**: As regras fundamentais do projeto. Code-First, Clean Architecture e TDD rigoroso.
- **[Changelog](./CHANGELOG.md)**: Histórico linear de atualizações e refatorações.
- **[API Pública](./API_PUBLIC.md)**: Guia de integração e assinatura dos métodos do Autoload.

---

## ⚙️ Instalação e Uso

O QuanticNet é desenhado para ser uma caixa preta elegante. Siga as instruções abaixo de acordo com o seu perfil.

### Opção A: Plug and Play (Apenas o Addon)

Se você é um desenvolvedor de jogos e deseja apenas usar o motor:

1. Baixe o repositório ou a última *Release*.
2. Copie a pasta `addons/quantic_net/` inteira (que já contém as bibliotecas compiladas e os scripts) para a raiz do seu novo projeto Godot.
3. Abra seu projeto, vá em `Project` -> `Project Settings` -> `Plugins` e ative o **QuanticNet**.
4. O Autoload principal será injetado automaticamente. Pronto!

### Opção B: Compilação Manual (Contribuidores)

Se você planeja modificar a infraestrutura em C++ (GDExtension):

1. Certifique-se de ter o [SCons](https://scons.org/) e um compilador C++ (MSVC no Windows ou GCC/Clang no Linux) instalados.
2. Clone o repositório.
3. Na raiz do projeto, execute a compilação:

   ```powershell
   scons target=template_debug debug_symbols=yes
   ```

4. Após o build, abra o projeto na Godot 4.7, vá em `Project Settings` -> `Plugins` e ative o **QuanticNet**.

---

## 🚀 Hello World QuanticNet

Aqui está um exemplo completo e robusto em GDScript puro (assumindo que o plugin está ativo). Crie um script `game_manager.gd` e anexe a um Node vazio na sua cena principal. Este exemplo cobre inicialização, sinais vitais, sincronia e reconciliação (*Snapback*).

```gdscript
extends Node

const PORT = 7777
const SECRET = "chavesecreta123"

# Variáveis Locais do Cliente
var _my_position := Vector3.ZERO
var _my_rotation := Vector3.ZERO
var _move_speed := 5.0

# Perfil Padrão para Entidades (TickRate: 60Hz, Prioridade: 1.0, Culling: 50m)
var _player_profile := QNEntityProfile.new()

func _ready() -> void:
    _player_profile.init(60.0, 1.0, 50.0)
    
    # 1. Conectando os Sinais Vitais do Motor
    QuanticNet.peer_joined.connect(_on_peer_joined)
    QuanticNet.peer_left.connect(_on_peer_left)
    QuanticNet.state_received.connect(_on_state_received)
    QuanticNet.snapback_received.connect(_on_snapback_received)
    
    # 2. Roteamento via Argumentos de Linha de Comando (CLI)
    if "--server" in OS.get_cmdline_args():
        print("[SERVIDOR] Iniciando na porta ", PORT)
        # Sobe o servidor autoritativo
        QuanticNet.host(PORT, SECRET, "*", 32)
        
        # Opcional: Se for um Dedicated Server (invisível), NÃO registre o ID 1.
        # QuanticNet.register_entity(1, true, true, _player_profile)
    else:
        print("[CLIENTE] Conectando ao Host...")
        QuanticNet.join("127.0.0.1", PORT, SECRET)


# ==========================================
# EVENTOS DE REDE (SINAIS)
# ==========================================

func _on_peer_joined(id: int) -> void:
    print("Jogador conectou: ", id)
    if QuanticNet.is_server():
        # O Servidor é a Autoridade: Ele decide registrar a nova entidade na malha.
        # Parâmetros: (id, é_humano, tem_estado_inicial, perfil)
        QuanticNet.register_entity(id, true, true, _player_profile)

func _on_peer_left(id: int) -> void:
    print("Jogador desconectou: ", id)
    # Aqui você removeria o Node 3D (Mesh) do jogador da sua SceneTree

func _on_state_received(owner_id: int, pos: Vector3, rot: Vector3, custom: int) -> void:
    # Ignora os próprios pacotes para não anular o Client-Side Prediction local
    if owner_id == QuanticNet.get_unique_id():
        return
        
    # Os pacotes de outros jogadores chegam aqui.
    # O motor C++ (QNInterpBuffer) usará esses dados nos bastidores para gerar um Lerp perfeito.
    # Na sua lógica visual (_process), você apenas chamaria:
    # var remote_pos = QuanticNet.get_remote_state(owner_id)["pos"]

func _on_snapback_received(seq: int, pos: Vector3, rot: Vector3, reason: int, replay_inputs: Array) -> void:
    # O coração do Anti-Cheat arquitetural.
    # Se o cliente tentou burlar a física, o servidor envia a posição Real (Autoritativa).
    print("[CLIENTE] Snapback! Posição forçada pelo servidor: ", pos)
    _my_position = pos
    
    # Após aceitar a posição real, re-simulamos os inputs pendentes (Lag Compensation)
    for pending in replay_inputs:
        var input_dir = pending["move"] # (Vector2)
        var dt = pending["dt"]
        _my_position += Vector3(input_dir.x, 0, input_dir.y) * _move_speed * dt


# ==========================================
# LOOP DE JOGO E PREDIÇÃO (CLIENT-SIDE)
# ==========================================

func _physics_process(delta: float) -> void:
    # Apenas clientes conectados enviam movimentação
    if not QuanticNet.is_server() and QuanticNet.get_state() == QuanticNet.ConnectionState.CONNECTED:
        
        # 1. Coleta Input e simula instantaneamente (Client-Side Prediction - Zero Lag)
        var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
        if input_dir.length() > 0:
            _my_position += Vector3(input_dir.x, 0, input_dir.y) * _move_speed * delta
        
        # 2. Informa ao servidor onde VOCÊ ACHA que está (State-Based)
        # O Motor C++ vai absorver isso, encadear num Jitter Buffer e validar.
        QuanticNet.submit_state(_my_position, _my_rotation, 0, delta)
```

---

## 🏗️ Rodando o Laboratório (Client/Server)

No Windows, criamos um script para gerenciar a auto-topologia de testes de forma fácil e isolada (iniciando 1 Servidor invisível em background e 2 Clientes interligados localmente):

```powershell
powershell.exe -ExecutionPolicy Bypass -File toggle_demo.ps1
```

*(Para derrubar as instâncias e limpar as portas instantaneamente, basta executar o script de novo).*
