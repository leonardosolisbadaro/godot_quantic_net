# TODO: QuanticNet

Plugin de network (`QuanticNet`) *plug-and-play*, focado no desenvolvimento de jogos `3D Open World MMO` usando a `Godot Engine 4.7`.
As diretrizes estruturais de **Code-First**, **Test-Driven Development (TDD)** e **Clean Architecture** governam o fluxo. Nenhuma linha é escrita sem antes redigir o seu Teste Falhando (GUT).

---

## 🗄️ ARQUIVO (Fases Anteriores Concluídas)

O projeto base estabilizou. As seguintes fundações já estão **100% testadas (GUT), homologadas e integradas em C++ / GDScript**:

* **Clean Architecture & Core Domain:** Implementados `QNSerializer`, `QNClockSync`, `QNLossTracker`, `QNInterpBuffer`, `QNServerValidator` e `QNInputBuffer`.
* **Infraestrutura e Transporte:** ENet, obfuscação de pacotes e emulação de redes extremas (Netem).
* **Teardown Seguro:** `QNNetHook` garantindo zero ObjectDB Leaks no encerramento da `MultiplayerAPIExtension`.
* **Criptografia:** DTLS dinâmico com mbedTLS *on the fly* e Fingerprint Pinning.
* **Competitivo MMO:** Delta Compression, Priority Accumulator e Tick Híbrido consolidados.
* **Spatial Hashing (AoI) C++:** `QNSpatialGrid` implementado em C++ para culling de rede ultra-rápido.
* **Lag Compensation:** `QNWorldHistoryBuffer` armazenando entidades no passado para hitscan determinístico.
* **Demo Bare Metal:** O `demo_main.gd` foi completamente reescrito para demonstrar a API pública, inputs empacotados via `custom_id` e simulação sem RPCs.

---

## 🚀 NOVA FASE 1: A FRONTEIRA DO GRID SYSTEM E MMO MACIÇO

Nesta nova etapa, a arquitetura passa a explorar as verdadeiras capacidades do `QNSpatialGrid` (C++), preparando o terreno para mundos colossais baseados em chunks e simulações físicas maciças.

### PR 1 — Integração de Grid/Chunk System na Demo (Spatial Partitioning)

* [ ] Adaptar a `demo_main.gd` para instanciar cenários divididos em múltiplos "Chunks/Grids" lógicos, utilizando a flag `grid_culling_enabled`.
* [ ] Implementar a transição invisível de entidades (avatares e props) entre as fronteiras do grid, demonstrando o culling ativo e dinâmico quando a distância inter-grids exceder o *Area of Interest*.
* [ ] Garantir que o código da Demo sirva como documentação viva, permitindo e exemplificando claramente ambas as implementações de domínio: "Mapa Único Estático" (atual) e "Grid/Chunk System Dinâmico" (futuro).

### PR 2 — Networked Physics (RigidBody Sync)

* [ ] TDD: Expansão do codec `QNSerializer` ou `BitBuffer` para suportar o empacotamento rigoroso e escalável de *Linear Velocity* e *Angular Velocity*.
* [ ] Criar nova categoria no Domain: `NetProfile.RIGID_BODY`.
* [ ] Alterar `QNClientSession` e `QNHostSession` para gerenciar *Sleeping states*: economizar 100% da banda de entidades físicas quando suas energias cinéticas zerarem, transmitindo apenas a eclosão inicial do pulso.

### PR 3 — Object Replication Protocol (Spawn Dinâmico)

* [ ] Desenvolver um protocolo para "spawn" semântico dinâmico no meio da partida. Clientes precisam saber tipagens no decorrer da sessão (ex: "A entidade 1004 é um Baú", "A entidade 1005 é uma Porta").
* [ ] Implementar um sistema de RPC Assíncrono Desacoplado na API do QuanticNet: permitir o envio de mensagens determinísticas e confiáveis (fora do ciclo ininterrupto e preditivo do `submit_state`).

### PR 4 — Testes de Escalabilidade Massiva e Cloud Deploy

* [ ] Criar uma suíte de testes de integração Headless simulando a conexão concorrente de centenas de `QNClientSessions` transitando ativamente entre os grids do `QNSpatialGrid`.
* [ ] Validar o teto do *Bytes per Second* em cima do `PriorityAccumulator` sob alto estresse populacional no mesmo chunk. Comprovar que a saturação não rompe o limite imposto do MTU.
* [ ] Homologar o deploy da topologia autônoma em contêineres Docker / Linux Headless.
