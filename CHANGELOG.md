# CHANGELOG

Todas as mudanças relevantes deste projeto serão documentadas neste arquivo.

O formato segue o padrão do [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/)
e este projeto utiliza [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.8.0] - 2026-08-10

### Adicionado

- **I/O Offloading em Worker Threads**: Migração total das rotinas de ENet `service()`, desserialização binária (`Bit-Unpacking`) e fila do NetEmul para uma `std::thread` dedicada no core C++ (via `QNWirePeer`). O ENet agora é drenado em paralelo, e a GDScript consome os pacotes sem bloqueios via um Lock-Free SPSC Ring Buffer em C++.
- **Dynamic Entity Profiles (`QNEntityProfile`):** Introduzido gerenciamento granular por entidade, permitindo customizar Tick Rate, Peso de Prioridade e Raio de Culling. Possibilita que props inativos rodem a 5Hz enquanto jogadores mantêm 60Hz fluídos.
- **Regions & Spatial Culling System:** Implementado culling baseado em *Axis-Aligned Bounding Boxes* (AABB), isolando a rede de "Dungeons/Ilhas" do mundo exterior.
- **Queries no Passado (Rollback):** API expandida com `query_raycast`, `query_box` e `query_sphere` para detecção de colisão no servidor retrocedida no tempo usando o `QNWorldHistoryBuffer`.
- **API Reference (Rewrite):** Recriação do `API_PUBLIC.md` documentando todas as funções robustas com exemplos práticos.

### Corrigido

- **[CRÍTICO] Unconstrained RAM Growth (Memory Leak):** Refatoração massiva da camada de serialização. A geração abusiva de `Dictionary` e `Variant` a 60Hz foi totalmente eliminada e substituída por `struct QNEntityState` POD em memória contígua (C++). O uso de RAM estática foi estabilizado permanentemente, mitigando gargalos do Garbage Collector.
- **Skyrocketing RTT Poisoning (Ping a 4911ms+):** Resolvido o bug que travava o cálculo do relógio (`QNClockSync`) devido à exclusão redundante da variável `seq` no corpo dos pacotes na migração das structs. O cliente agora lê e drena inputs de forma oficial baseando-se no `client_seq_ack` do *Header*, prevenindo cálculos baseados em zero com *Sanity Checks*.
- **Delta Encoding Cache Miss:** O servidor falhava ao localizar a *Base State* no `tick_broadcast` por referenciar números de sequência ao invés do `peer_id`, forçando transmissões plenas. Corrigido para buscar via *Peer ID*, restaurando a compressão Delta (economia de banda de até 90%).
- **Interpolation Jitter:** Corrigido problema onde a `QNInterpBuffer` amarrava interpolações a *timestamps* locais atrasadas pela rede. A inserção agora respeita puramente o `server_now` autoritativo, restaurando a predição macia e livre de engasgos e teletransportes visuais (Snapbacks fantasma).

---

## [0.7.0] - 2026-08-08

### Adicionado

- **Command-Based API (Paradigma Autoritativo):** Implementação da abstração `QNCommandSession` e da nova interface pública `submit_input(sequence, input_mask, look_dir)` para o envio determinístico de inputs do cliente.
- **Dynamic Input Jitter Buffer (Server-Side):** Motor agora absorve flutuações de rede através de um atraso dinâmico no consumo de inputs baseado no *Jitter* do Peer conectado.
- **Catch-up Físico:** Implementação de uma mecânica de drenagem (*drain/catch-up*) no loop físico do servidor capaz de processar um backlog de inputs engasgados simultaneamente após picos abruptos de latência.
- **TDD Rigoroso:** 100% de cobertura nos testes unitários das novas camadas de domínio (`test_qn_server_jitter_buffer.gd`) e orquestração (`test_qn_command_session.gd`), isolando a regra de ordenação e proteção contra sequências corrompidas e *wrap-around*.

---

## [0.6.0] - 2026-08-07

### Adicionado

- **A Demo Definitiva (Bare Metal Playground):** Refatoração integral e re-escrita da `demo_main.gd`. Arquitetura sem acoplamento visual, implementação cirúrgica de Interpolação, Client-Side Prediction com Zero Input Lag e Culling Espacial Dinâmico.
- **Rastreadores Diagnósticos:** Injeção de Labels UI atreladas ao ciclo de vida das entidades (`id`, `x`, `z`) provando matematicamente o funcionamento agnóstico do Client e Server View, lado a lado.

### Corrigido

- **[CRÍTICO] Undefined Evaluation Order no GDExtension (Windows/MSVC):** Identificação e mitigação de um clássico bug de compilação em C++ nos desserializadores (`qn_delta_serializer.cpp` e `qn_serializer.cpp`). A instancialização do `Vector3` sofria *swap* dos eixos `X` e `Z` na compilação do MSVC por conta do sequenciamento da direita para a esquerda de *reads* na mesma instrução. A decodificação agora é estritamente sequencial, blindada e *cross-platform*.
- **Correção de Escopo de Lógica:** Correção de bugs de acesso fora de limites (Out of Bounds) no Dicionário da UI, originados por declarações mal posicionadas no escopo do iterador do `GDScript`.

### Modificado

- **Refatoração UI/UX da Demo:** Uso intenso de snake_case, padronização de variáveis e recriação do zero de todos os comentários, transformando a demonstração na principal referência didática e pedagógica da infraestrutura QuanticNet.
- Limpeza de Números Mágicos: Consolidação de lógicas rígidas (como alturas e eixos de spawn) em constantes tipadas e rastreáveis na Demo.

---

Histórico de Versões Arquivadas (0.1.0 até 0.5.0)

## [0.5.0] - 2026-08-05

### Adicionado

- Setup da infraestrutura de compilação em C++ via SCons.
- Camada de Transporte Nativa (GDExtension), `QNWirePeer`, `QNNetHook`.
- Migração de Lógica Pesada para C++ (`QNInterpBuffer`, Serializadores).

## [0.4.0] - 2026-08-04

### Adicionado

- Criação de `QNTelemetryAggregator` e classe imutável `QNEntityProfile`.

## [0.3.0-rc.2] - 2026-08-04

### Adicionado

- Implementação da struct `PeerTelemetrics` para RTT e Jitter.

## [0.3.0-rc.1] - 2026-08-02

### Corrigido

- Prevenção de Memory Leaks e Crashes via teardown limpo.

## [0.3.0] - 2026-07-31

### Adicionado

- Handshake de Identidade Segura e `TYPE_PEER_LEFT`.

## [0.2.0] - 2026-07-30

### Adicionado

- Integração de mbedTLS, Netem em C++, Serialização ZSTD.
- Client-Side Prediction, Server Reconciliation e Snapshot Interpolation bases.

## [0.1.0] - 2026-07-28

### Lançamento Inicial

- Estruturação base do projeto.

</details>
