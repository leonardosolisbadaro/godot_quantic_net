# TODO: QuanticNet (Core Infrastructure)

Plugin de network autoritativo (`QuanticNet`) construído em C++ (GDExtension) para Godot 4.7.
Este repositório é estritamente infraestrutura *Bare Metal*. Demos de gameplay e MMOs concretos residem no repositório externo [godot_quantic_net_demos](https://github.com/leonardosolisbadaro/godot_quantic_net_demos).

---

## 🗄️ FUNDAÇÕES HOMOLOGADAS (Concluído)

* Transporte (ENet/DTLS), Ticks Híbridos, Spatial Hashing (C++), Lag Compensation e Demo Bare Metal de demonstração da API.

---

## 🚀 FASE 1: ARQUITETURA V2 (Command-Based & Multithreading)

*Esta fase transforma o QuanticNet num servidor autoritativo resiliente, imune a manipulações de tempo do cliente e gargalos de thread.*

### PR 1 — Command-Based API & Input Jitter Buffer

* [x] Criar abstração/interface `QNCommandSession` isolada ou flag de configuração de paradigma no `project.godot`.
* [x] Isolar a lógica de movimento em função pura e determinística (`move(state, input, dt)`) rodando em passo fixo.
* [x] Implementar a nova interface pública `submit_input(sequence, input_mask, look_dir)` no `quantic_net_autoload.gd`.
* [x] Desenvolver o *Dynamic Input Jitter Buffer* no lado do servidor (escrevendo testes no Gut primeiro).
* [x] Implementar no servidor atraso dinâmico no consumo baseado no Jitter da conexão do Peer.
* [x] Implementar *Catch-up* no loop físico para processar backlog de inputs após picos de latência.

### PR 2 — I/O Offloading em Worker Threads

* [x] Migrar rotinas de polling (`enet_host_service`) para rodar em Worker Thread dedicado C++.
* [x] Realizar a deserialização bruta (*Bit-Unpacking*) paralelamente no Worker Thread.
* [x] Criar um Lock-Free Ring Buffer para injetar os dados desserializados em memória compartilhada segura.
* [x] Alterar o sinal `_on_custom_packet` na Godot para apenas ler do Ring Buffer pronto na Main Thread.

### PR 3 — Tick Server-Side Independente & Dormancy

* [ ] Substituir o uso de `_physics_process` no servidor por um `_process` com Acumulador Determinístico (Ex: `NET_TICK_RATE = 1.0 / 20.0`).
* [ ] Gerenciar entidades dormentes (Sleep State): Servidor parar de transmitir estados se Δ Posição e Rotação zerarem por `N` ticks.
* [ ] Transmitir notificação explícita de pacote `TYPE_SLEEP` ao cliente para suspender a interpolação visual do prop.

---

## 🚨 FASE 2: FUNDAÇÃO NETCODE AAA (Refatoração Crítica)

*Esta fase é bloqueante. O Core não evolui para novas features até o hotpath atual estar impecável.*

### PR 1 — Ack-Tracking no Delta Serializer (CRÍTICO)

* [ ] Implementar bitmask de 32 bits de confirmação alimentado pelo `QNLossTracker` (em memória contígua `uint32_t`, zero allocation).
* [ ] Gerar P-Frames exclusivamente contra o último snapshot confirmado pelo cliente; emitir I-Frame automático após 32 perdas.

### PR 2 — Struct POD Contígua + Diff Bitwise (Performance)

* [ ] Substituir o modelo `Dictionary`/`Variant` por `struct QNEntityState` POD de tamanho fixo no C++.
* [ ] Diff passa a ser bitwise XOR sobre memória bruta (vetorizado com SIMD quando possível).

---

## 🌐 FASE 3: EXPANSÃO DO CORE (Features C++)

### PR 1 — Networked Physics (RigidBody Sync)

* [ ] Expandir o codec nativo para empacotar *Linear* e *Angular Velocity*.

### PR 2 — RPC Desacoplado e Object Replication

* [ ] Implementar canal de envio garantido para "spawn" semântico dinâmico (transmissão de tipagens e eventos vitais paralelos ao tick posicional).

---

## 🧊 ICEBOX (Tarefas Congeladas)

### Issue: Elastic Time / Clock Steering

* **Status:** Congelada (Obsoleta).
* **Escopo:** Ajuste microscópico de delta no cliente baseado no nível do buffer do host. Rejeitado pois a Arquitetura V2 com Jitter Buffer Ativo e Tick Independente já resolve a autoridade de tempo no lado do servidor.

### Issue: Solver Cinemático Stateless em C++ (`QNKinematicSolver`)

* **Status:** Congelada aguardando necessidade real de colisão.
* **Escopo:** Função pura stateless para rollback seguro via `PhysicsDirectSpaceState`.
