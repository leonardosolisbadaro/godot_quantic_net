# TODO: QuanticNet

Plugin de network (`QuanticNet`) *plug-and-play*, focado no desenvolvimento de jogos `3D Open World MMO` usando a `Godot Engine 4.7`.
As diretrizes estruturais de **Code-First**, **Test-Driven Development (TDD)** e **Clean Architecture** governam o fluxo. Nenhuma linha é escrita sem antes redigir o seu Teste Falhando (GUT).

---

## 🏗️ FUNDAÇÃO (Concluída - Fases 1 a 9)

O projeto base estabilizou na versão **0.6.0**. Os seguintes épicos estão **100% testados (GUT), homologados e concluídos**:

- [x] Configuração da Clean Architecture e Metodologia AAA (TDD obrigatório).
- [x] Construção do Core Domain: `QNSerializer`, `QNClockSync`, `QNLossTracker`, `QNInterpBuffer`, `QNServerValidator` e `QNInputBuffer`.
- [x] Infraestrutura e Transporte: `QNWirePeer` com ENet, Codec, Obfuscação e Emulação de Redes Extremas via **Netem**.
- [x] Ganchos Nativos Livres de Leaks: `QNNetHook` encapsulando e interceptando a `MultiplayerAPIExtension` do Godot com teardown seguro (`close()`) cravando 0 ObjectDB Leaks!
- [x] Casos de Uso Autoritativos: `QNHostSession` (Anti-Cheat, Reject, Clamp) e `QNClientSession` (Prediction e Local Replay).
- [x] Integração Criptográfica DTLS: `QNDTLSBootstrap` gerando certificados mbedTLS *on the fly* com Fingerprint Pinning de proteção.
- [x] Evolução Competitiva MMO: Delta Compression & ACKs, Priority Accumulator e Tick Híbrido.
- [x] Demo "Bare Metal" e Teste End-to-End validando o Autoload `QuanticNet` *Plug-and-play*.
- [x] **[0.6.0] Spatial Hashing Puro (Area of Interest - AoI):** Culling de rede e Spatial Grid (`QNSpatialGrid`) no C++.
- [x] **[0.6.0] Lag Compensation:** `QNWorldHistoryBuffer` armazenando entidades no passado.
- [x] **[0.6.0] Demo Definitiva e Estabilidade Core:** Refatoração integral da `demo_main.gd` e blindagem da desserialização contra Undefined Behavior de compiladores (MSVC/Windows).

---

## 🚀 FASE 10: A FRONTEIRA MMO E FÍSICA

Esta etapa abraçará mecânicas massivas. A arquitetura de base não será tocada, em vez disso, módulos puristas em GDScript (ou C++ se houver gargalo) serão anexados ao Domínio visando expandir as capacidades simulativas do servidor. O ciclo TDD será estrito.

### PR 28 — Sincronização de Física Rígida (Networked Physics)

- [ ] TDD: Expansão do codec `QNSerializer` ou `BitBuffer` para suportar empacotamento rigoroso de *Linear Velocity* e *Angular Velocity*.
- [ ] Criar constante no Domain: `NetProfile.RIGID_BODY`.
- [ ] Alterar `QNClientSession` e `QNHostSession` para gerenciar repousos (Sleeping states): economizar 100% de banda de entidades físicas quando suas energias cinéticas zerarem e notificar apenas a eclosão inicial do pulso.

### PR 29 — Object Replication Protocol e Interação de Mundo

- [ ] Permitir "spawn" dinâmico no meio da partida. Atualmente, os clientes recebem estado das entidades, mas precisam de um protocolo para saber que "A entidade 1004 é um Baú" ou "A entidade 1005 é uma Porta".
- [ ] Implementar sistema de RPC Assíncrono Desacoplado: Mensagens determinísticas e confiáveis via QuanticNet (fora do `submit_state` interpolado).

### PR 30 — Testes de Escalabilidade Massiva e Cloud

- [ ] Criar nova suíte de testes de integração Headless simulando a conexão concorrente de dezenas de `QNClientSessions` e dezenas de entidades.
- [ ] Validar consumo de banda em *Bytes per Second* em cima do `PriorityAccumulator`. Comprovar matematicamente que o teto de *MTU* é respeitado independente da saturação.
- [ ] Deploy da infraestrutura autônoma em contêineres Docker / Linux Headless.

### PR 31 — Separação Visual e Demos Secundárias

- [ ] Manter `demo_main.gd` como um "Smoke Test" Bare Metal.
- [ ] Iniciar um repositório secundário (ex: `quantic-net-demos`) para ilustrar mecânicas complexas em instâncias separadas (ex: integração do HitScan determinístico com o `QNWorldHistoryBuffer`).
