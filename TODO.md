# TODO: QuanticNet

Plugin de network (`QuanticNet`) *plug-and-play*, focado no desenvolvimento de jogos `3D Open World MMO` usando a `Godot Engine 4.7`.
As diretrizes estruturais de **Code-First**, **Test-Driven Development (TDD)** e **Clean Architecture** governam o fluxo. Nenhuma linha é escrita sem antes redigir o seu Teste Falhando (GUT).

---

## 🏗️ FUNDAÇÃO (Concluída - Fases 1 a 8)

O projeto base estabilizou na versão **0.3.0**. Os seguintes épicos estão **100% testados (GUT), homologados e concluídos**:

- [x] Configuração da Clean Architecture e Metodologia AAA (TDD obrigatório).
- [x] Construção do Core Domain: `QNSerializer`, `QNClockSync`, `QNLossTracker`, `QNInterpBuffer`, `QNServerValidator` e `QNInputBuffer`.
- [x] Infraestrutura e Transporte: `QNWirePeer` com ENet, Codec, Obfuscação e Emulação de Redes Extremas via **Netem**.
- [x] Ganchos Nativos Livres de Leaks: `QNNetHook` encapsulando e interceptando a `MultiplayerAPIExtension` do Godot com teardown seguro (`close()`) cravando 0 ObjectDB Leaks!
- [x] Casos de Uso Autoritativos: `QNHostSession` (Anti-Cheat, Reject, Clamp) e `QNClientSession` (Prediction e Local Replay).
- [x] Integração Criptográfica DTLS: `QNDTLSBootstrap` gerando certificados mbedTLS *on the fly* com Fingerprint Pinning de proteção.
- [x] Evolução Competitiva MMO: Delta Compression & ACKs, Priority Accumulator e Tick Híbrido.
- [x] Demo "Bare Metal" e Teste End-to-End validando o Autoload `QuanticNet` *Plug-and-play*.

---

## 🚀 FASE 9: A FRONTEIRA MMO E FÍSICA

Esta etapa abraçará mecânicas massivas. A arquitetura de base não será tocada, em vez disso, módulos puristas em GDScript serão anexados ao Domínio visando expandir as capacidades simulativas do servidor. O ciclo TDD será estrito.

### PR 21 — Spatial Hashing Puro (Area of Interest - AoI)

O despache não pode propagar todo o universo. Filtragem espacial inteligente.

- [ ] TDD: Criar a classe `QNSpatialGrid` em `src/domain/`.
- [ ] Especificar inserção, atualização e remoção veloz de IDs em células de Grid (Cell Size parametrizável).
- [ ] Especificar busca de vizinhos radial (`get_entities_in_radius`).
- [ ] Integrar no ciclo de broadcast do `QNHostSession`, poupando banda limitando *snapshots* apenas a entidades que colidem visualmente (culling).

### PR 22 — Lag Compensation (Server-Side Rewind)

Implementação de reconciliação de tempo para hit-registration preciso em jogos competitivos.

- [ ] TDD: Criar `QNWorldHistoryBuffer` armazenando AABB / Bounds das entidades por `render_ts`.
- [ ] Especificar lógica de captura temporal cíclica circular retrocedendo no máximo até 1,5s no passado do servidor.
- [ ] Integrar no Autoload a função `raycast_past(origin, direction, timestamp)`, expondo-a para que jogos de FPS construam seu HitScan determinístico compensando pings de até 250ms perfeitamente.

### PR 23 — Sincronização de Física Rígida (Networked Physics)

- [ ] TDD: Expansão do codec `QNSerializer` ou `BitBuffer` para suportar empacotamento rigoroso de *Linear Velocity* e *Angular Velocity*.
- [ ] Criar constante no Domain: `NetProfile.RIGID_BODY`.
- [ ] Alterar `QNClientSession` e `QNHostSession` para gerenciar repousos (Sleeping states): economizar 100% de banda de entidades físicas quando suas energias cinéticas zerarem e notificar apenas a eclosão inicial do pulso.

### PR 24 — Testes de Escalabilidade Massiva

- [ ] Criar nova suíte de testes de integração Headless simulando a conexão concorrente de dezenas de `QNClientSessions` e dezenas de entidades.
- [ ] Validar consumo de banda em *Bytes per Second* em cima do `PriorityAccumulator`. Comprovar matematicamente que o teto de *MTU* é respeitado independente da saturação das requisições ao longo de 60 segundos de loop contínuo sob perturbações de Netem.

### PR 25 — Separação e Migração Visual

- [ ] Desacoplar quaisquer cenários visuais pesados. Manter apenas um script base estéril "Smoke Test".
- [ ] Iniciar um repositório secundário (ex: `quantic-net-demos`) que importará essa release consumindo suas virtudes de forma arquitetural (sem UI-Bound Lógica), para ilustrar HUDs e avatares detalhados.
