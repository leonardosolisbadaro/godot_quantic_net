# 📋 TODO: QuanticNet (Core Infrastructure) v0.9.0

Plugin de rede autoritativo de alto desempenho construído em C++ (GDExtension) para a Godot Engine 4.7+.

> ⚠️ **Fronteira Arquitetural:** Este repositório é estritamente a **infraestrutura do motor (Bare Metal)**. Todas as demonstrações de gameplay, sistemas de chunks de terreno, geração procedural, inventários e inteligência artificial de NPCs residem no repositório parceiro oficial [godot_quantic_net_demos](https://github.com/leonardosolisbadaro/godot_quantic_net_demos).

---

## 🏛️ ESTADO ATUAL: FUNDAÇÕES CONCLUÍDAS (v0.9.0) ✅

### 1. Motor C++ e Gestão de Memória Zero-Allocation

- [x] **Fast Native Priority Accumulator:** `QNPriorityAccumulator::select_entities_fast()` operando diretamente sobre vetores e mapas nativos de C++, eliminando 100% das alocações de `Dictionary`/`Variant` no tick de broadcast.
- [x] **Zero-Allocation World History Buffer:** `QNWorldHistoryBuffer::push_state_native()` gravando snapshots físicos contíguos de POD structs sem instanciar nós ou dicionários.
- [x] **Safe Peer ID Wrap-Around Cycle:** Ciclo de identificadores de peer restrito ao intervalo seguro $[2, 999]$, pulando conexões ativas e prevenindo colisões com o limiar de entidades de ambiente (`PEER_ID_THRESHOLD = 1000`).
- [x] **Padronização de OpCodes de 8 Bits:** Campo `custom_id` padronizado para 8 bits em toda a cadeia de serialização e desserialização UDP, permitindo $256$ tags de estado de animação/gameplay simultâneas.

### 2. Sincronização Temporal e Telemetria

- [x] **Algoritmo de Relógio Contínuo (`QNClockSync`):** Convergência estatística de RTT e Offset via EMA (Exponential Moving Average) e descarte de picos espúrios.
- [x] **APIs de Consulta Expostas no Autoload:** `QuanticNet.is_clock_synced()`, `QuanticNet.clock_rtt()`, `QuanticNet.clock_offset()`, `QuanticNet.server_time()`.
- [x] **Loss Tracker com Janela Deslizante de 64 Bits:** Rastreamento de perda de pacotes por peer com proteção contra wrap-around de 16 bits.

### 3. I/O Offloading e Transporte Seguro

- [x] **Worker Thread Dedicada (`QNWirePeer`):** Polling contínuo de sockets ENet e desembalamento de bits rodando em thread paralela em C++, comunicando-se com a Main Thread via Lock-Free Ring Buffer.
- [x] **Segurança DTLS Nativa:** Handshake com criptografia de ponta a ponta e token compartilhado (`QNDTLSBootstrap`).
- [x] **Network Emulation (NetEmul):** Injeção em tempo real de latência, jitter, perda e duplicação de pacotes em C++.

### 4. Paradigmas de Sincronização e Anti-Cheat

- [x] **Dual Paradigm (State-Based vs Command-Based):** Suporte tanto a envio de estados preditos (Client-Side Prediction com Zero Input Lag) quanto a inputs determinísticos com *Dynamic Jitter Buffer* no servidor.
- [x] **Lag Compensation (Rollback):** Rebobinamento temporal autoritativo para testes de colisão no passado (`query_raycast`, `query_box`, `query_sphere`).
- [x] **Validador de Movimento Híbrido:** Verificação de limites de velocidade elástica (*Clamp*), detecção de teletransporte (*Reject/Kick*) e integração com NavMesh do Godot via RID.

---

## 🎯 PRÓXIMAS METAS DO MOTOR (Rumo à v1.0.0)

### Milestone 1 — Otimizações SIMD e Vetorização

- [ ] Implementar comparações *Bitwise XOR* vetorizadas (instruções AVX2/SSE) no cálculo de Delta Encoding do `QNHostSession`.
- [ ] Vetorizar a detecção de AABB do `QNSpatialGrid` para acelerar o particionamento com mais de $10.000$ entidades ativas.

### Milestone 2 — Suporte a Networked RigidBodies

- [ ] Adicionar struct nativa `QNRigidBodyState` para sincronização de corpos físicos com velocidade linear e angular compactadas.
- [ ] Integrar perfil de prioridade especial para detritos e veículos (`RIGID_BODY_PROFILE`).

### Milestone 3 — Server Meshing Hooks (Escalabilidade Distribuída)

- [ ] Criar interface de Hand-off de entidades entre múltiplos nós dedicados de servidor em nuvem.
- [ ] Roteamento transparente de pacotes entre instâncias regionais sem desconexão do cliente.

---

## 🎮 METAS DO REPOSITÓRIO DE DEMOS (`godot_quantic_net_demos`)

Todas as implementações de conteúdo e mecânicas de jogo avançam no repositório de demos:

- [ ] **Chunk Manager (Seamless Streaming):** Geração e streaming contínuo de malhas de terreno e NavMeshes.
- [ ] **Open World MMO Stress Test:** Simulação de multidão com centenas de avatares e NPCs patrulhando autonomamente.
- [ ] **Combat & Spells System:** Conjuração de magias, projéteis balísticos e combate corpo a corpo validado por Lag Compensation.
