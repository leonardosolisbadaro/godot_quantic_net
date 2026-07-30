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

## [0.2.0] - 2026-07-30

### Adicionado

- Implementação do `QNHostSession` (Casos de Uso), orquestrador do servidor autoritativo responsável por autenticação, decodificação de estados, validação (accept/clamp/reject), disparos de snapbacks e broadcast de ticks globais.
- Implementação completa da infraestrutura de transporte `QNWirePeer` suportando Compressão ZSTD, Obfuscação XOR e simulação nativa de rede (Netem) com suporte a latência, jitter, perda e duplicação controlada.
- Implementação do interceptador `QNNetHook` atuando sobre a MultiplayerAPI, oferecendo controle absoluto sobre RPCs de saída e injeção de pacotes customizados transparentemente (Filtros e Transformers).
- Implementação rigorosa (TDD/AAA) da entidade de Domínio `QNInputBuffer`, finalizando a arquitetura core do plugin. Gerencia a drenagem circular de inputs do cliente utilizando compensação matemática para resistir ao wrap-around de sequências.
- Implementação rigorosa (TDD/AAA) da entidade de Domínio `QNServerValidator`, isolada da engine. Protege o servidor contra pacotes forjados, limitando velocidade (`HARD_CAP`), aplicando _clamps_ em excessos toleráveis e punindo teletransportes via _strikes_.
- Implementação rigorosa (TDD/AAA) da entidade de Domínio `QNInterpBuffer` (extrapolação correta baseada no `render_ts`).
- Implementação rigorosa (TDD/AAA) da entidade de Domínio `QNLossTracker` (wrap-around de 16-bits resiliênte).
- Implementação rigorosa (TDD/AAA) da entidade de Domínio `QNClockSync` (modelo NTP aprimorado).
- Implementação rigorosa (TDD/AAA) da entidade de Domínio `QNSerializer`, garantindo quantização binária extrema.
- "Casca" estrutural do `QuanticNet` em `addons/` orientada a Clean Architecture.
- Restrição arquitetural no `GEMINI.md` exigindo uso obrigatório de **bitwes/Gut**.

### Corrigido

- Correção de Memory Leaks graves (`ObjectDB instances`) nas suítes de teste de infraestrutura através do emprego de instâncias `autofree` sobre extensões em C++ instanciadas pelo GUT.

### Modificado

- Atualização integral do arquivo `GEMINI.md` (Constituição Arquitetural), definindo rigorosamente as camadas concêntricas de Clean Architecture e fluxo de TDD para o plugin `QuanticNet` (foco em MMO 3D Open World).

---

## [0.1.0] - 2026-07-28

###
