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

## 🌍 Hello World QuanticNet

Aqui está o esqueleto mínimo de integração em GDScript puro (assumindo que o plugin está ativo). Crie um script `game_manager.gd` e anexe a um Node vazio na sua cena principal:

```gdscript
extends Node

const PORT = 7777
const SECRET = "chavesecreta123"

func _ready() -> void:
    # 1. Escutamos os sinais do motor
    QuanticNet.peer_joined.connect(_on_peer_joined)
    
    # 2. Escolhemos o nosso papel na rede (Host ou Cliente)
    if "--server" in OS.get_cmdline_args():
        print("Iniciando Servidor Autoritativo...")
        # Inicializa em Modo 0 (State-Based)
        QuanticNet.host(PORT, SECRET, "*", 32, {"network_mode": 0})
    else:
        print("Iniciando Cliente...")
        QuanticNet.join("127.0.0.1", PORT, SECRET)

func _on_peer_joined(id: int) -> void:
    print("Novo Peer autenticado com ID: ", id)

func _physics_process(delta: float) -> void:
    if not QuanticNet.is_server() and QuanticNet.get_state() == QuanticNet.ConnectionState.CONNECTED:
        # 3. (Apenas Cliente): Disparamos a nossa posição preditiva local para a rede.
        # O motor em C++ absorve, empacota em Deltas e envia ao servidor.
        QuanticNet.submit_state(Vector3.ZERO, Vector3.ZERO, 0, delta)
```

---

## 🏗️ Rodando o Laboratório (Client/Server)

No Windows, criamos um script para gerenciar a auto-topologia de testes de forma fácil e isolada (iniciando 1 Servidor invisível em background e 2 Clientes interligados localmente):

```powershell
powershell.exe -ExecutionPolicy Bypass -File toggle_demo.ps1
```

*(Para derrubar as instâncias e limpar as portas instantaneamente, basta executar o script de novo).*
