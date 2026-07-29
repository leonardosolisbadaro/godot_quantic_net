# CHANGELOG

Todas as mudanças relevantes deste projeto serão documentadas neste arquivo.

O formato segue o padrão do [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/)
e este projeto utiliza [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Adicionado

- Implementação rigorosa (TDD/AAA) da entidade de Domínio `QNSerializer`, com testes passando, garantindo quantização binária de pacotes de estado para 19 Bytes.
- "Casca" estrutural e arquivos descritores (autoload e plugin.cfg) do `QuanticNet` injetada em `addons/`, adotando fielmente as hierarquias isoladas da Clean Architecture (`domain/`, `use_cases/`, `adapters/` e `infrastructure/`).
- Workflow de produtividade integrado ao VS Code (atalhos F5, F10 e F12 e `tasks.json`), orquestrando o ciclo de validação do TDD e proteção do processo Headless (LSP).
- Restrição arquitetural no `GEMINI.md` exigindo o uso obrigatório e exclusivo do framework **bitwes/Gut** para a confecção da suíte de testes (TDD).

### Modificado

- Atualização integral do arquivo `GEMINI.md` (Constituição Arquitetural), definindo rigorosamente as camadas concêntricas de Clean Architecture e fluxo de TDD para o plugin `QuanticNet` (foco em MMO 3D Open World).

### Corrigido

- ...

### Removido

- ...

---

## [0.1.0] - 2026-07-28

### ...
