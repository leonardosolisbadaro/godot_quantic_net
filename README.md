# ⚡ QuanticNet

O **QuanticNet** é um plugin de rede autoritativo *plug-and-play* de alta performance para a **Godot Engine 4.7+**.

Ele foi projetado para simplificar o desenvolvimento de jogos multiplayer — desde arenas competitivas até ecossistemas massivos (*3D Open World MMO*) — cuidando de toda a infraestrutura complexa de baixo nível (sockets UDP, criptografia DTLS, predição no cliente, interpolação de snapshots, particionamento espacial e compensação de lag) diretamente em **C++ (GDExtension)**, enquanto entrega uma API leve, declarativa e direta em **GDScript**.

---

## ✨ Principais Destaques

* **Client-Side Prediction (Zero Input Lag):** Movimentação local instantânea com reconciliação autoritativa do servidor apenas em caso de divergências.
* **Snapshot Interpolation Fluída:** Renderização suave de entidades remotas com amortecimento de variações de rede (jitter).
* **Particionamento e Culling Espacial:** Grade contígua em C++ que transmite para cada cliente estritamente o que está em sua Área de Interesse (AoI).
* **Lag Compensation (Rollback):** Rebobinamento do mundo físico no servidor para validação precisa de acertos e tiros de *Hitscan*.
* **Dual Paradigm:** Liberdade para escolher entre sincronização orientada a estados (*State-Based*) ou envio de comandos determinísticos (*Command-Based*).
* **Desacoplamento Visual:** Arquitetura limpa (*Code-First*), permitindo que servidores dedicados rodem de forma ultra-leve em modo puramente *Headless*.

---

## 📦 Instalação Passo a Passo

Usar o QuanticNet no seu projeto é simples e rápido:

1. **Download do Addon:** Copie a pasta `addons/quantic_net` deste repositório (ou da última *Release*) para dentro da pasta `res://addons/` do seu projeto Godot.
2. **Ativação do Plugin:** No editor da Godot, acesse o menu superior:
   $$\text{Project} \longrightarrow \text{Project Settings} \longrightarrow \text{Plugins}$$
   Localize o **QuanticNet** e marque a caixa **Enable**.
3. **Pronto para Usar:** O Singleton global `QuanticNet` será injetado automaticamente e estará disponível em qualquer script GDScript (`.gd`) do seu jogo.

---

## 🚀 Hello World (Exemplo Básico)

Crie um script `network_manager.gd` e anexe a um nó na sua cena principal:

```gdscript
extends Node

const PORT := 4242
const SECRET := "minha-chave-secreta"

func _ready() -> void:
    # 1. Escuta os eventos do motor de rede
    QuanticNet.connection_state_changed.connect(_on_state_changed)
    QuanticNet.peer_joined.connect(_on_peer_joined)
    QuanticNet.state_received.connect(_on_state_received)

    # 2. Inicializa como Servidor ou Cliente via argumentos da linha de comando
    if OS.get_cmdline_args().has("--server"):
        print("[SERVIDOR] Iniciando na porta %d..." % PORT)
        QuanticNet.host(PORT, SECRET, "*", 32)
    else:
        print("[CLIENTE] Conectando ao servidor...")
        QuanticNet.join("127.0.0.1", PORT, SECRET)

func _physics_process(delta: float) -> void:
    # 3. O cliente envia sua posição predita para o servidor a cada frame de física
    if not QuanticNet.is_server() and QuanticNet.get_state() == QuanticNet.ConnectionState.CONNECTED:
        var minha_posicao = Vector3(0, 1, 0)
        QuanticNet.submit_state(minha_posicao, Vector3.ZERO, 0, delta)

func _on_state_changed(new_state: int) -> void:
    print("Estado da Conexão: ", new_state)

func _on_peer_joined(peer_id: int) -> void:
    print("Novo jogador conectado com ID: ", peer_id)

func _on_state_received(owner_id: int, pos: Vector3, rot: Vector3, custom: int) -> void:
    # Atualiza a posição da entidade visual no cliente
    pass
```

---

## 🧭 Onde Ir a Partir Daqui (Documentação Completa)

Para explorar a fundo todos os recursos, consulte os documentos detalhados:

* 📚 **[API_PUBLIC.md](./API_PUBLIC.md):** Referência completa e comentada de todos os métodos, sinais, parâmetros e enums do Autoload.
* 📋 **[TODO.md](./TODO.md):** Status dos marcos de infraestrutura concluídos e metas táticas do motor.
* 🗺️ **[ROADMAP_MMO.md](./ROADMAP_MMO.md):** Visão arquitetural de longo prazo para jogos de grande escala e *Server Meshing*.
* 📜 **[CHANGELOG.md](./CHANGELOG.md):** Histórico de versões e melhorias no padrão *Keep a Changelog* (SemVer).
* 🏛️ **[GEMINI.md](./GEMINI.md):** A constituição arquitetural, regras de Clean Architecture e mandates de TDD do projeto.
* 🎮 **[godot_quantic_net_demos](https://github.com/leonardosolisbadaro/godot_quantic_net_demos):** Repositório oficial com exemplos de gameplay, streaming de chunks de terreno e testes visuais avançados.
