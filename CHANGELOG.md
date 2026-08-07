# CHANGELOG

Todas as mudanças relevantes deste projeto serão documentadas neste arquivo.

O formato segue o padrão do [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/)
e este projeto utiliza [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

<details>
<summary>Histórico de Versões Arquivadas (0.1.0 até 0.5.0)</summary>

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
