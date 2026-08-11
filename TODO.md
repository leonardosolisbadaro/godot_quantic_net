# TODO: QuanticNet (Core Infrastructure)

Plugin de network autoritativo (`QuanticNet`) construído em C++ (GDExtension) para Godot 4.7.
Este repositório é estritamente infraestrutura *Bare Metal*. Demos de gameplay e MMOs concretos residem no repositório externo [godot_quantic_net_demos](https://github.com/leonardosolisbadaro/godot_quantic_net_demos).

---

## 🗄️ FUNDAÇÕES HOMOLOGADAS (Concluído)

* **Transporte Nativo:** ENet/DTLS integrado via GDExtension.
* **Paradigma Híbrido:** Suporte a Command-Based e State-Based prediction.
* **Worker Threads (I/O Offloading):** Desserialização e ENet rodando em thread paralela via `QNWirePeer` com Lock-Free Ring Buffers.
* **Input Jitter Buffer:** Catch-up físico e absorção dinâmica de flutuações de rede no Host.
* **Otimização de Memória Extrema:** Estruturas POD Contíguas (`QNEntityState`) sem `Variant/Dictionary` overhead para tracking.
* **Queries Espaciais & Lag Compensation:** `QNWorldHistoryBuffer` e `QNSpatialGrid` com suporte a `query_raycast` no passado.
* **Entity Profiles & Regions:** Culling espacial (AABB) dinâmico e perfis assíncronos customizados por taxa de tick e prioridade.

---

## 🚨 FASE ATUAL: EXPANSÃO DO NETCODE AAA E ESTABILIDADE

*Esta fase foca em otimizar a resiliência à perda de pacotes e isolar a autoridade do tempo no servidor.*

### PR 1 — Ack-Tracking no Delta Serializer (CRÍTICO)

* [ ] Implementar bitmask de 32 bits de confirmação alimentado pelo `QNLossTracker` (em memória contígua `uint32_t`, zero allocation).
* [ ] Gerar P-Frames exclusivamente contra o último snapshot confirmado pelo cliente; emitir I-Frame automático após 32 perdas.

### PR 2 — Tick Server-Side Independente & Dormancy

* [x] Substituir o uso de `_physics_process` no servidor por um `_process` com Acumulador Determinístico (Ex: `NET_TICK_RATE = 1.0 / 20.0`).
* [x] Gerenciar entidades dormentes (Sleep State): Servidor parar de transmitir estados se Δ Posição e Rotação zerarem por `N` ticks.
* [x] Transmitir notificação explícita de pacote `TYPE_SLEEP` ao cliente para suspender a interpolação visual do prop.

---

## 🌐 FASE FUTURA: EXPANSÃO DO CORE (Features Avançadas C++)

### PR 1 — Networked Physics (RigidBody Sync)

* [ ] Expandir o codec nativo para empacotar *Linear* e *Angular Velocity* para simulações baseadas em física autoritativa.

### PR 2 — RPC Desacoplado e Object Replication

* [ ] Implementar canal de envio garantido (Reliable) para "spawn" semântico dinâmico (transmissão de tipagens e eventos vitais paralelos ao tick posicional UDP).

---

## 🧊 ICEBOX (Tarefas Congeladas)

### Issue: Elastic Time / Clock Steering

* **Status:** Congelada (Obsoleta).
* **Escopo:** Ajuste microscópico de delta no cliente baseado no nível do buffer do host. Rejeitado pois a Arquitetura V2 com Jitter Buffer Ativo e Tick Independente já resolve a autoridade de tempo no lado do servidor.

### Issue: Solver Cinemático Stateless em C++ (`QNKinematicSolver`)

* **Status:** Congelada aguardando necessidade real de colisão nativa pesada.
* **Escopo:** Função pura stateless para rollback seguro via `PhysicsDirectSpaceState`.
