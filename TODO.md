# TODO: QuanticNet (Core Infrastructure)

Plugin de network autoritativo (`QuanticNet`) construído em C++ (GDExtension) para Godot 4.7.
Este repositório é estritamente infraestrutura *Bare Metal*. Demos de gameplay e MMOs concretos residem no repositório externo `godot_quantic_net_demos`.

---

## 🗄️ FUNDAÇÕES HOMOLOGADAS (Concluído)

* Transporte (ENet/DTLS), Ticks Híbridos, Spatial Hashing (C++), Lag Compensation e Demo Bare Metal de demonstração da API.

---

## 🚨 FASE 1: FUNDAÇÃO NETCODE AAA (Refatoração Crítica)

*Esta fase é bloqueante. O Core não evolui para novas features até o hotpath atual estar impecável.*

### PR 1 — Ack-Tracking no Delta Serializer (CRÍTICO)

* [ ] Implementar bitmask de 32 bits de confirmação alimentado pelo `QNLossTracker` (em memória contígua `uint32_t`, zero allocation).
* [ ] Gerar P-Frames exclusivamente contra o último snapshot confirmado pelo cliente; emitir I-Frame automático após 32 perdas.

### PR 2 — Eliminação do Double-Smoothing na Demo Bare Metal

* [ ] Aplicar a saída do `QNInterpBuffer.sample()` diretamente na posição visual, removendo lerps secundários que destróem a precisão do buffer.

### PR 3 — Struct POD Contígua + Diff Bitwise (Performance)

* [ ] Substituir o modelo `Dictionary`/`Variant` por `struct QNEntityState` POD de tamanho fixo no C++.
* [ ] Diff passa a ser bitwise XOR sobre memória bruta (vetorizado com SIMD quando possível).

### PR 4 — Elastic Time / Clock Steering

* [ ] Implementar ajuste microscópico de delta no cliente baseado no nível do `QNInputBuffer` do host, garantindo `server_time()` monotônico.

### PR 5 — Predição em Passo Fixo

* [ ] O integrador da prediction da demo passa a rodar no mesmo passo fixo do tick de rede, eliminando divergências de ponto flutuante.
* [ ] Isolar o passo de movimento na função `move(state, input, dt)`.

---

## 🌐 FASE 2: EXPANSÃO DO CORE (Features C++)

### PR 1 — Networked Physics (RigidBody Sync)

* [ ] Expandir o codec nativo para empacotar *Linear* e *Angular Velocity* e gerenciar *Sleeping states* para economizar banda.

### PR 2 — RPC Desacoplado e Object Replication

* [ ] Implementar canal de envio garantido para "spawn" semântico dinâmico (transmissão de tipagens e eventos vitais paralelos ao tick posicional).

---

## 🧊 ICEBOX (Tarefas Congeladas)

### Issue: Solver Cinemático Stateless em C++ (`QNKinematicSolver`)

* **Status:** Congelada aguardando necessidade real de colisão.
* **Escopo:** Função pura stateless para rollback seguro via `PhysicsDirectSpaceState`.
