# CHANGELOG

Todas as mudanças relevantes deste projeto serão documentadas neste arquivo.

O formato segue o padrão do [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/)
e este projeto utiliza [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## Unreleased

### Adicionado

- ...

### Corrigido

- ...

### Modificado

- ...

### Removido

- ...

## [0.5.0] - 2026-08-05

### Adicionado

- **GDExtension (PR 24):** Setup da infraestrutura de compilação em C++ via SCons (`SConstruct`), integrando o Godot-CPP e configurando bindings para registro de classes.
- **Camada de Transporte Nativa (PR 24):** Implementação de `QNWirePeer`, `QNNetHook` e `QNDTLSBootstrap` integralmente em C++, permitindo manipulação de bytes no nível da engine sem o gargalo do GDScript.
- **Lógica e Bufferização em C++ (PR 24):** Migração das regras de negócio pesadas, incluindo `QNClockSync`, `QNLossTracker`, `QNInterpBuffer`, `QNInputBuffer`, `QNPriorityAccumulator`, e os Serializadores (`QNSerializer`, `QNDeltaSerializer`) para o *Performance Core*.
- **Orquestração de Sessões C++ (PR 24):** Substituição dos nós GDScript por `QNClientSession` e `QNHostSession` nativos, operando em C++, reduzindo drasticamente a sobrecarga de Ticking.

### Modificado

- **API Autoload (PR 24):** Refatoração da casca GDScript (`quantic_net_autoload.gd`) para atuar puramente como proxy de integração "Plug and Play" com a Godot Engine, despachando chamadas e eventos diretamente para as instâncias instanciadas do GDExtension.

## [0.4.0] - 2026-08-04

### Adicionado

- **Extração Agnóstica (PR 22.8):** Criação da classe purista de domínio `QNTelemetryAggregator` com suporte para janelas deslizantes (Sliding Window), garantindo o rastreio dinâmico de médias, picos e fundos (min/max) de métricas de rede com 100% de separação da Engine.
- **Value Object para Perfis de Rede (PR 22.8):** Implementação de `QNEntityProfile` para substituição de dicionários cruos por uma classe imutável de forte tipagem com mecanismo de `fail-fast` via `assert()` integrado.

### Modificado

- **Integração de Telemetria (PR 22.8):** A `demo_main.gd` não precisa mais implementar lógica matemática de amostras; consome métricas puras através da API pública `QuanticNet.get_telemetry()`.
- **Hospedagem de Agregadores (PR 22.8):** O `quantic_net_autoload.gd` passou a gerenciar instâncias de agregadores por peer-id (`_telemetry_map`), os quais são preenchidos por via de eventos nativos (`pong_received`, recebimento de `TYPE_SNAPSHOT`).
- O sistema de despache `QNPriorityAccumulator` abandonou a tipagem genérica para consumir exclusivamente o contrato imutável `QNEntityProfile`.

## [0.3.0-rc.2] - 2026-08-04

### Adicionado

- **Telemetria Avançada (PR 22):** Implementação da struct `PeerTelemetrics` para armazenamento tipado de RTT, Perda de Pacotes e Offset, com buffers circulares (30 amostras) para cálculo dinâmico de médias.
- **Staggered Polling:** Adicionado sistema de *round-robin* no `_process` da demo para requisição diluída de `loss_of(id)`, evitando travamentos na UI com dezenas de entidades.
- **Feedback Visual (PR 22):** Troca suave da cor de emissão dos avatares/props (teclas `1-5`) utilizando `Tween` sincronizado com os perfis de rede.
- **Encerramento Limpo (PR 21):** Implementação de `_notification` para interceptar `NOTIFICATION_WM_CLOSE_REQUEST` e forçar o `disconnect_net(true)` ao fechar a janela, prevenindo leaks.

### Corrigido

- **Correção de Ativação do Netem (PR 21):** Mover a rotina `set_netem_config(0.10, 150, 50)` restritivamente para dentro da cláusula `if _netem_active`.
- **[LINT] Correção de Private-Access em `demo_main.gd`:** Refatoração da struct interna `PeerTelemetrics` para utilizar métodos *getter* (`get_last_rtt()`, `get_last_loss()`), resolvendo avisos do analisador estático sobre violação de encapsulamento.

### Modificado

- **Atalhos da UI (PR 21):** O bloqueio do FPS/VSync migrou da tecla `L` para `F`, além da remoção do tratamento da tecla `Escape` no `_physics_process`.
- **Silenciamento de Variáveis Não Utilizadas:** Ajuste no styleguide dos parâmetros `delta`, `pos` e `rot` no `_process` e `_on_snapback` (prefixados com `_`) em `demo_main.gd` para limpeza dos alertas do compilador.

## [0.3.0-rc.1] - 2026-08-02

### Corrigido

- **[CRÍTICO] Correção de Memory Leaks (ObjectDB):** Erradicação de vazamentos de instâncias ao garantir que a camada de testes GUT destrua corretamente ganchos e limpe o Singleton via injeção automática e segura no `after_each()`.
- **[CRÍTICO] Prevenção de Crashes de Teardown (`SCRIPT ERROR`):** Injeção de verificação dinâmica `has_signal` no `QNNetHook` antes da chamada para desconectar em massa, viabilizando o teardown robusto tanto para ambientes reais quanto *FakeBase* instanciados nos testes.
- **Resolução de `ERR_INVALID_PARAMETER` no fechamento:** O gerenciamento do ciclo de vida da `MultiplayerAPIExtension` e Godot's `SceneTree` foi segregado através do método `disconnect_net(is_exiting)`, prevenindo corrupção de estado interno quando o Godot é encerrado em modo headless.

### Modificado

- **Expansão de Blindagem da API:** Incorporação de guarda preventiva rigorosa contra nulidade (`if base == null`) em todos os métodos delegados da `MultiplayerAPIExtension`, preservando a sanidade da engine diante de chamadas marginais.

## [0.3.0] - 2026-07-31

### Adicionado

- Implementação de handshake de identidade via `send_auth`, permitindo que o servidor informe dinamicamente ao `QNWirePeer` do cliente qual é o seu ID único, resolvendo conflitos de identidade em instâncias múltiplas.
- Implementação do pacote `TYPE_PEER_LEFT` no protocolo, garantindo que a desconexão de um peer seja propagada autoritativamente para todos os clientes, limpando o registro e a memória.
- Mecanismo de mitigação de jitter de framerate no `QNServerValidator` (`effective_dt`), evitando falsos-positivos de speedhack em clientes que rodem em framerates instáveis.

### Corrigido

- Resolução crítica na máquina de estados de autenticação da Godot 4 onde clientes não recebiam a confirmação de conexão devido a um payload vazio (`PackedByteArray()`).
- Resolução de colisões de identificação local onde todos os clientes assumiam o ID hardcoded `2` e sobrepunham instâncias preditivas incorretamente.
- Resolução de persistência fantasma onde instâncias de jogadores (cubos) permaneciam na cena após a desconexão do peer devido à ausência de broadcast de saída.

### Modificado

- Roteamento dinâmico do `auth_callback` no `quantic_net_autoload.gd` para separar o fluxo de autorização do servidor e a recepção de identidade no cliente.

## [0.2.0] - 2026-07-30

### Adicionado

- Implementação completa do Autoload `QuanticNet`, integrando nativamente o `QNNetHook`, `QNWirePeer`, suporte DTLS e as sessões de Host/Client na árvore do SceneTree, viabilizando o ecossistema "plug-and-play".
- Implementação de segurança de transporte com `QNDTLSBootstrap`, integrando mbedTLS nativo da engine, geração de chaves RSA dinâmicas e "fingerprint pinning" transparente.
- Implementação da sessão preditiva do cliente, `QNClientSession`, suportando Rate-limit (ex: 20 Hz), submissão assíncrona, sincronização remota interpolada e orquestração de Snapbacks/Replays contra o Host.
- Implementação do `QNHostSession` (Casos de Uso), orquestrador do servidor autoritativo responsável por autenticação, decodificação de estados, validação (accept/clamp/reject), disparos de snapbacks e broadcast de ticks globais.
- Implementação completa da infraestrutura de transporte `QNWirePeer` suportando Compressão ZSTD, Obfuscação XOR e simulação nativa de rede (Netem) com suporte a latência, jitter, perda e duplicação controlada.
- Implementação rigorosa dos Testes de Integração End-to-End via loopback (Host ↔ 2 Clients) em ambiente Headless simulando condições severas de rede (PR 8).
- Implementação do interceptador `QNNetHook` atuando sobre a MultiplayerAPI, oferecendo controle absoluto sobre RPCs de saída e injeção de pacotes customizados transparentemente (Filtros e Transformers).
- Implementação rigorosa (TDD/AAA) da entidade de Domínio `QNInputBuffer`, finalizando a arquitetura core do plugin. Gerencia a drenagem circular de inputs do cliente utilizando compensação matemática para resistir ao wrap-around de sequências.
- Implementação rigorosa (TDD/AAA) da entidade de Domínio `QNServerValidator`, isolada da engine. Protege o servidor contra pacotes forjados, limitando velocidade (`HARD_CAP`), aplicando *clamps* em excessos toleráveis e punindo teletransportes via *strikes*.
- Implementação rigorosa (TDD/AAA) da entidade de Domínio `QNInterpBuffer` (extrapolação correta baseada no `render_ts`).
- Implementação rigorosa (TDD/AAA) da entidade de Domínio `QNLossTracker` (wrap-around de 16-bits resiliênte).
- Implementação rigorosa (TDD/AAA) da entidade de Domínio `QNClockSync` (modelo NTP aprimorado).
- Implementação rigorosa (TDD/AAA) da entidade de Domínio `QNSerializer`, garantindo quantização binária extrema.
- "Casca" estrutural do `QuanticNet` em `addons/` orientada a Clean Architecture.
- Criação da Cena de Demonstração (Demo 3D) 100% autônoma "Bare Metal", isolada em `addons/quantic_net/demo/`. Focada em validar o uso consumidor do plugin (Prediction Client-Side e Remote Interpolation) via código de forma plug-and-play e garantida por testes de integração (PR 9).
- Restrição arquitetural no `GEMINI.md` exigindo uso obrigatório de **bitwes/Gut**.

### Corrigido

- Correção de Memory Leaks graves (`ObjectDB instances`) nas suítes de teste de infraestrutura através do emprego de instâncias `autofree` sobre extensões em C++ instanciadas pelo GUT.
- Correção de offset e validação de pacotes na sincronização de relógios (`QNClockSync`) sob latência simulada e na injeção de buffer de input (`QNInputBuffer`) do cliente.
- Correção na ordem dos argumentos passados virtualmente à `MultiplayerAPIExtension.send_bytes` no envio de payloads.

### Modificado

- Atualização integral do arquivo `GEMINI.md` (Constituição Arquitetural), definindo rigorosamente as camadas concêntricas de Clean Architecture e fluxo de TDD para o plugin `QuanticNet` (foco em MMO 3D Open World).

---

## [0.1.0] - 2026-07-28

### Lançamento Inicial

- Estruturação base do projeto.
