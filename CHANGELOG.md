# CHANGELOG

Todas as mudanças relevantes deste projeto serão documentadas neste arquivo.

O formato segue o padrão do [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/)
e este projeto utiliza [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.9.0] - 2026-08-14

### Adicionado

- **Zero-Allocation Fast Priority Accumulator (`select_entities_fast`):** Implementada sobrecarga nativa em C++ operando sobre `std::unordered_map` e `std::vector`, eliminando 100% das alocações de `Dictionary` e `Variant` no hotpath do tick de broadcast a 60Hz.
- **Zero-Allocation Native World History Buffers (`push_state_native`):** Gravação contígua de snapshots POD (`QNEntityState`) diretamente no anel de histórico para suporte a *Lag Compensation* e consultas de *Rollback* (`query_raycast`, `query_box`, `query_sphere`) sem overhead de heap.
- **Safe Peer ID Wrap-Around Cycle ($[2, 999]$):** Implementado algoritmo de reciclagem segura de identificadores de peer no `QNWirePeer`, pulando conexões ativas e reiniciando em 2 ao atingir 1000 para evitar colisões com entidades de ambiente (`PEER_ID_THRESHOLD = 1000`).
- **Padronização do `custom_id` para 8 Bits:** O protocolo de rede agora codifica e decodifica 8 bits ($0 \dots 255$) em toda a cadeia de serialização e desserialização UDP, permitindo que jogos utilizem $256$ tags simultâneas de estado/animação e códigos semânticos de snapback.
- **APIs Públicas de Sincronização de Relógio no Autoload:**
    - `QuanticNet.is_clock_synced() -> bool`
    - `QuanticNet.clock_rtt() -> float`
    - `QuanticNet.clock_offset() -> float`
    - `QuanticNet.server_time(now: int) -> int`
- **Reorganização de Atalhos e Depuração na Demo:**
    - <kbd>V</kbd>: Toggle dos Decals GPU (Anéis de AoI / FOV).
    - <kbd>H</kbd>: Toggle integral da Interface (HUD / Profilers).
    - <kbd>.</kbd> *(Ponto)*: Toggle da Sub-grade Espacial interna (Área roxa do `QNSpatialGrid`).
    - <kbd>C</kbd>: Toggle das cápsulas de colisão e pontos de apoio.
    - <kbd>,</kbd> *(Vírgula)*: Toggle da malha de navegação (NavMesh).
- **Otimização de Decals GPU:** Configurado `decal.cull_mask = 1` para limitar a projeção exclusivamente ao terreno (Layer 1) e ajustada altura de projeção para $100\text{ m}$ com zero fade vertical (`upper_fade = 0.0`, `lower_fade = 0.0`), garantindo 100% de visibilidade sólida e nítida em qualquer relevo.

### Modificado

- **`demo_main.gd` Atualizada:** Painel de diagnóstico agora consome ativamente as novas APIs de telemetria de relógio nativo em tempo real e exibe mensagens descritivas para reconciliações de snapback.
- **Otimização de `send_game_packet`:** Substituída a cópia byte a byte por chamada vetorizada `pkt.append_array(data)`.

### Corrigido

- **Conflito de Tecla de Atalho:** O atalho de Decals foi movido de `D` para `V`, eliminando a colisão com o movimento lateral direito do padrão WASD.
- **Corte de Decals em Encostas:** Removido o esmaecimento vertical agressivo que ocultava os anéis em subidas e descidas de montanhas.

---

## [0.8.0] - 2026-08-10

### Adicionado

- **I/O Offloading em Worker Threads:** Migração total das rotinas de ENet `service()`, desserialização binária (*Bit-Unpacking*) e fila do NetEmul para uma `std::thread` dedicada no core C++ (via `QNWirePeer`). O ENet agora é drenado em paralelo, e a GDScript consome os pacotes sem bloqueios via um Lock-Free SPSC Ring Buffer em C++.
- **Dynamic Entity Profiles (`QNEntityProfile`):** Gerenciamento granular por entidade, permitindo customizar Tick Rate, Peso de Prioridade e Raio de Culling.
- **Regions & Spatial Culling System:** Culling baseado em *Axis-Aligned Bounding Boxes* (AABB), isolando a rede de instâncias do mundo exterior.
- **Queries no Passado (Rollback):** API expandida com `query_raycast`, `query_box` e `query_sphere` para detecção de colisão no servidor retrocedida no tempo usando o `QNWorldHistoryBuffer`.

### Corrigido

- **Unconstrained RAM Growth (Memory Leak):** Eliminação de `Dictionary` e `Variant` no loop de serialização a 60Hz, substituídos por structs POD em memória contígua.
- **RTT Calculation Sanity:** Correção do sequenciador de ACK no cabeçalho do pacote, estabilizando o cálculo de RTT no `QNClockSync`.
- **Delta Encoding Cache Miss:** Corrigida a busca da base state no `tick_broadcast` por `peer_id`, restaurando a compressão delta.

---

## [0.7.0] - 2026-08-08

### Adicionado

- **Command-Based API:** Implementação da abstração `QNCommandSession` e da interface `submit_input(sequence, input_mask, look_dir)` para envio determinístico de inputs do cliente.
- **Dynamic Input Jitter Buffer (Server-Side):** Absorção de flutuações de rede via atraso dinâmico no consumo de inputs baseado no Jitter do Peer.
- **Catch-up Físico:** Mecânica de drenagem (*drain/catch-up*) no loop físico do servidor para processar backlogs de inputs acumulados.
- **TDD Rigoroso:** 100% de cobertura nos testes unitários das novas camadas (`test_qn_server_jitter_buffer.gd`, `test_qn_command_session.gd`).

---

## [0.6.0] - 2026-08-07

### Adicionado

- **A Demo Bare Metal Playground:** Criação da `demo_main.gd` como laboratório de testes end-to-end com simulação de topologia espelhada (1 Servidor e 2 Clientes em instâncias independentes).
- **Rastreadores Diagnósticos:** Painéis de métricas de FPS, frametime, memória estática, draw calls, RTT, jitter, loss e clock offset.

### Corrigido

- **Undefined Evaluation Order no GDExtension (Windows/MSVC):** Correção de swap dos eixos X e Z na instanciação de `Vector3` no MSVC, tornando a decodificação sequencial e blindada *cross-platform*.

---

## [0.5.0] - 2026-08-05

### Adicionado

- Setup da infraestrutura de compilação em C++ via SCons.
- Camada de Transporte Nativa (GDExtension), `QNWirePeer`, `QNNetHook`.
- Migração de Lógica Pesada para C++ (`QNInterpBuffer`, Serializadores).

---

## [0.4.0] - 2026-08-04

### Adicionado

- Criação de `QNTelemetryAggregator` e classe imutável `QNEntityProfile`.

---

## [0.3.0] - 2026-07-31

### Adicionado

- Handshake de Identidade Segura DTLS e eventos de `TYPE_PEER_LEFT`.

---

## [0.2.0] - 2026-07-30

### Adicionado

- Integração de mbedTLS, NetEmul em C++ e serialização compacta.
- Client-Side Prediction, Server Reconciliation e Snapshot Interpolation bases.

---

## [0.1.0] - 2026-07-28

### Adicionado

- Criação do repositório base e constituição arquitetural `GEMINI.md`.
