# 🗺️ ROADMAP MMO: A Visão de Infraestrutura do QuanticNet Core

Este documento delineia a visão técnica, os fundamentos de escalabilidade e o horizonte arquitetural para o **QuanticNet**, projetado desde a sua primeira linha de código em C++ para atender às exigências de jogos **3D Open World MMO** e títulos multiplayer competitivos na **Godot Engine 4.7+**.

> ⚠️ **Fronteira Arquitetural:** O QuanticNet é estritamente o **motor de infraestrutura de baixo nível**. Lógicas específicas de gameplay, inventários, árvores de talentos, streaming visual de chunks e shaders de terreno residem no repositório parceiro oficial [godot_quantic_net_demos](https://github.com/leonardosolisbadaro/godot_quantic_net_demos).

---

## 🏛️ Os Pilares Arquiteturais (Fundamentos Consolidados) ✅

O QuanticNet consolidou uma infraestrutura de alto rendimento baseada em Clean Architecture e TDD rigoroso:

```
+---------------------------------------------------------------+
|                    GDScript Domain Layer                      |
| (Regras de Jogo, Máquinas de Estado, Eventos de Gameplay)     |
+-------------------------------+-------------------------------+
                                |  (API Pública Declarativa)
+-------------------------------v-------------------------------+
|             QuanticNet Autoload & Use Cases                   |
| (QNHostSession, QNClientSession, QNCommandSession, Telemetry) |
+-------------------------------+-------------------------------+
                                |  (C++ GDExtension Hotpath)
+-------------------------------v-------------------------------+
|                 C++ Bare-Metal Core Engine                    |
| - QNSpatialGrid (Culling Espacial O(1))                       |
| - QNPriorityAccumulator (Zero-Alloc Fast Priority Scheduling) |
| - QNWorldHistoryBuffer (Rollback Snapshot Ring Buffer)        |
| - QNWirePeer (Worker Thread I/O + Lock-Free SPSC Ring Buffer) |
| - QNClockSync (Sincronizador Estatístico de Relógio Sub-ms)   |
| - QNDTLSBootstrap (ENet Nativo com Criptografia Segura)       |
+---------------------------------------------------------------+
```

### 1. Dual Paradigm (Flexibilidade Total de Design)

O desenvolvedor não fica preso a um único modelo de sincronização:

* **State-Based Paradigm:** Predição local no cliente com *Zero Input Lag* e reconciliação autoritativa no servidor (ideal para exploração de mundo aberto, MMORPGs e PvE).
* **Command-Based Paradigm:** Envio de máscaras puras de comandos determinísticos com *Dynamic Jitter Buffer* no servidor (ideal para arenas PvP, eSports e combate competitivo).

### 2. Zero-Allocation Hotpaths

Todas as rotinas críticas executadas no tick de rede (60Hz) operam sobre estruturas `POD` (Plain Old Data) contíguas em C++, eliminando instâncias de `Dictionary` e alocações dinâmicas no heap da Godot.

### 3. I/O Offloading em Worker Threads

O tráfego de rede e a desserialização binária de pacotes (*Bit-Unpacking*) rodam em uma `std::thread` dedicada em C++. A *Main Thread* da Godot não sofre bloqueios de I/O de sockets.

---

## 🚀 O Horizonte Técnico (Evolução da Infraestrutura)

```
                       [ VISÃO DE ESCALA ]

    [ Clientes (Godot) ] <--- UDP/DTLS ---> [ Edge Server Nodes ]
                                                  |
                  +-------------------------------+-------------------------------+
                  |                               |                               |
          [ Zone Server A ]               [ Zone Server B ]               [ Zone Server C ]
         (Chunk X: -500..0)               (Chunk X: 0..500)              (Chunk X: 500..1000)
                  |                               |                               |
                  +---------------+---------------+---------------+---------------+
                                  |                               |
                          [ QNSpatialGrid ]               [ Server Meshing ]
                          (Particionamento)              (Roteamento Inter-Nós)
```

---

### Fase 1: Otimizações SIMD e Compressão Vetorizada (Curto Prazo)

* **Bitwise Delta Compression SIMD:** Vetorização das comparações de snapshot no `QNHostSession` via instruções AVX2/SSE, reduzindo o tempo de cálculo de delta para centenas de entidades a frações imperceptíveis de microssegundo.
* **Spatial Grid SIMD Filtering:** Aceleração do teste de intersecção esfera/AABB no `QNSpatialGrid`.

---

### Fase 2: Networked RigidBodies e Física Predita (Médio Prazo)

* **Sincronização de Corpos Rígidos:** Criação de perfil dedicado `RIGID_BODY_PROFILE` com codificação compacta de vetores de velocidade linear e angular.
* **Extrapolação Cinemática Suave (Dead Reckoning):** Projeção autônoma de trajetórias de entidades em caso de rajadas intensas de perda de pacotes (*Packet Burst Loss*).

---

### Fase 3: Server Meshing e Escalabilidade Distribuída (Longo Prazo)

* **Arquitetura Multi-Processo (Zone Handoff):** O QuanticNet fornecerá abstrações para transferência transparente de autoridade de entidades entre múltiplos nós dedicados de servidor em nuvem.
* **Seamless Continuum:** Jogadores atravessam fronteiras de nós geográficos sem telas de carregamento (*Loading Screens*) e sem perder a continuidade dos pacotes de rede.

---

## 🎯 Conclusão

O QuanticNet é construído para libertar os desenvolvedores de jogos da Godot 4 das complexidades matemáticas de baixo nível do netcode, permitindo que a criatividade de gameplay prospere sobre uma fundação robusta, escalável e comprovada por testes rigorosos.
