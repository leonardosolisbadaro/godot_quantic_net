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

## 📊 FASE 9: QuanticNet Demo (Visual & Telemetry Update)

Este documento rastreia as tarefas de implementação da nova interface e telemetria da demo, garantindo o alinhamento de longo prazo com o `ROADMAP_MMO.md` e as restrições de arquitetura descritas no `GEMINI.md`.

### PR 21: Sessão A — "Zero Bugs" e Fundações
- [x] Implementar `_notification` para capturar `NOTIFICATION_WM_CLOSE_REQUEST` e executar `QuanticNet.disconnect_net(true)` antes de sair.
- [x] Limpar o input `Escape` do `_physics_process` (agora tratado de forma limpa pelo `_notification`).
- [x] Corrigir o bug do Netem: mover a chamada `set_netem_config(0.10, 150, 50)` para dentro do bloco `if _netem_active`.
- [x] Refatorar atalhos: Migrar toggle de FPS/VSync da tecla `L` para `F` (liberando `L` para os logs).

### PR 22: Sessão B — "Dados Vivos e Infraestrutura"
- [x] Criar classe de dados `PeerTelemetrics` (Struct interna) para armazenar telemetria (RTT, Loss, Offset, etc.) com tipagem forte.
- [x] Inicializar métricas de mínimo (`rtt_min`, `loss_min`) com valores sentinela lógicos (`INF`) para garantir registro correto da primeira amostra.
- [x] Implementar Buffer Circular (ex: 30 amostras) para suavização de `loss_avg` e `rtt_avg`.
- [x] Implementar sistema de *Staggered Polling* (Round-robin) no `_process` para a chamada de `loss_of(id)`, distribuindo a carga de 100+ entidades ao longo dos frames.
- [x] Implementar troca de cor de emissão dos materiais dos cubos (teclas `1-5`) via `Tween` vinculado ao callback `_apply_profile()`.

### PR 22.5: Sessão B.5 — "Network Profiler Avançado"
- [ ] Ampliar o painel de Profiler para incluir dados de rede (RTT, Loss, Offset) extraídos da struct `PeerTelemetrics`.

### PR 23: Sessão C — "Atmosfera e Estado"
- [ ] Implementar Aura Netem (tecla `N`): Adicionar um `ColorRect` na borda da tela que pulsa em laranja, com opacidade e frequência proporcionais ao `jitter_ms` e `delay_ms`.
- [ ] Implementar Barra de Estado de Conexão no topo da tela, reagindo aos sinais de rede (🔴 FAILED, 🟡 CONNECTING, 🟠 AUTHENTICATING, 🟢 CONNECTED).
- [ ] Adicionar botão de reconexão na interface em caso de falha (`connection_failed_reason`).

### PR 24: Sessão D — "Monitoramento e Logs"
- [ ] Criar "Log de Eventos Rolante" (tecla `L`): `RichTextLabel` no canto inferior esquerdo para exibir os últimos 10 eventos (joins, mudança de perfil, snaps) com código de cores e timestamps.

### PR 25: Sessão E — "Telemetria por Entidade"
- [ ] Criar sistema de HUD Flutuante (tecla `H`) em ambiente 2D (CanvasLayer) projetado no 3D usando `camera.unproject_position()` (com checagem `is_position_behind` para evitar espelhamento).
- [ ] Adicionar `VisibleOnScreenNotifier3D` aos cubos para desativar o cálculo do HUD 2D quando o objeto estiver fora do frustum.
- [ ] Implementar lógica condicional no HUD flutuante: Players exibem RTT; Props exibem `ΔT Srv: Xms` (baseado no `last_rx_gap` comparado ao tick rate ideal).
- [ ] Adicionar indicador visual de degradação ("Last seen: X.Xs ago") mudando de branco para vermelho antes do objeto entrar em culling forçado.
- [ ] HUD Local: Separar o campo `confirmed_pos` do transform local durante o `_on_state()`, calculando o *Prediction Drift* apenas quando houver posição confirmada pelo servidor.

### PR 26: Sessão F — "Drama" (Feedback de Netcode)
- [ ] Implementar Snapback Visual: Disparar um `Tween` de 0.4s na emissão vermelha do material quando `snapback_received` for chamado.
- [ ] Adicionar banner de texto temporário na tela (2.5s) informando os dados do snapback (sequência e total de inputs refeitos).
- [ ] Implementar tecla `B` (Burst): Salvar a configuração atual de Netem e aplicar um caos temporal extremo por 4 segundos, restaurando automaticamente depois (com *guard* para ignorar no servidor).

### PR 27: Sessão G — "Extras de Arquitetura"
- [ ] Implementar Modo Spectator (tecla `V`): Forçar `_can_send_state = false`, trocar material do cubo local para branco translúcido, e atualizar rótulo do HUD para `[SPECTATOR]`.
- [ ] Implementar Minimap 2D (tecla `Tab`): Criar painel customizado usando `_draw()` para renderizar pontos de entidades, vetores de velocidade (baseados no delta posicional) e raio do culling de rede.

---

## 🚀 FASE 10: A FRONTEIRA MMO E FÍSICA

Esta etapa abraçará mecânicas massivas. A arquitetura de base não será tocada, em vez disso, módulos puristas em GDScript serão anexados ao Domínio visando expandir as capacidades simulativas do servidor. O ciclo TDD será estrito.

### PR 28 — Spatial Hashing Puro (Area of Interest - AoI)

O despache não pode propagar todo o universo. Filtragem espacial inteligente.

- [ ] TDD: Criar a classe `QNSpatialGrid` em `src/domain/`.
- [ ] Especificar inserção, atualização e remoção veloz de IDs em células de Grid (Cell Size parametrizável).
- [ ] Especificar busca de vizinhos radial (`get_entities_in_radius`).
- [ ] Integrar no ciclo de broadcast do `QNHostSession`, poupando banda limitando *snapshots* apenas a entidades que colidem visualmente (culling).

### PR 29 — Lag Compensation (Server-Side Rewind)

Implementação de reconciliação de tempo para hit-registration preciso em jogos competitivos.

- [ ] TDD: Criar `QNWorldHistoryBuffer` armazenando AABB / Bounds das entidades por `render_ts`.
- [ ] Especificar lógica de captura temporal cíclica circular retrocedendo no máximo até 1,5s no passado do servidor.
- [ ] Integrar no Autoload a função `raycast_past(origin, direction, timestamp)`, expondo-a para que jogos de FPS construam seu HitScan determinístico compensando pings de até 250ms perfeitamente.

### PR 30 — Sincronização de Física Rígida (Networked Physics)

- [ ] TDD: Expansão do codec `QNSerializer` ou `BitBuffer` para suportar empacotamento rigoroso de *Linear Velocity* e *Angular Velocity*.
- [ ] Criar constante no Domain: `NetProfile.RIGID_BODY`.
- [ ] Alterar `QNClientSession` e `QNHostSession` para gerenciar repousos (Sleeping states): economizar 100% de banda de entidades físicas quando suas energias cinéticas zerarem e notificar apenas a eclosão inicial do pulso.

### PR 31 — Testes de Escalabilidade Massiva

- [ ] Criar nova suíte de testes de integração Headless simulando a conexão concorrente de dezenas de `QNClientSessions` e dezenas de entidades.
- [ ] Validar consumo de banda em *Bytes per Second* em cima do `PriorityAccumulator`. Comprovar matematicamente que o teto de *MTU* é respeitado independente da saturação das requisições ao longo de 60 segundos de loop contínuo sob perturbações de Netem.

### PR 32 — Separação e Migração Visual

- [ ] Desacoplar quaisquer cenários visuais pesados. Manter apenas um script base estéril "Smoke Test".
- [ ] Iniciar um repositório secundário (ex: `quantic-net-demos`) que importará essa release consumindo suas virtudes de forma arquitetural (sem UI-Bound Lógica), para ilustrar HUDs e avatares detalhados.
