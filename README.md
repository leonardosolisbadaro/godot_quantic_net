# QuanticNet

**Versão Atual:** `0.2.0`

Plugin de network (`QuanticNet`) `plug and play`, focado no desenvolvimento de jogos `3D Open World MMO` usando a `Godot Engine 4.7`. Arquitetada absoluta (a partir do zero) focada em **Code-First**, **Test-Driven Development (TDD)** e **Clean Architecture**. Eliminando a dependência de editores visuais para lógicas de negócio.

## A Constituição do Projeto

Nenhum código novo deve ser gerado sem a aprovação explícita e o cumprimento integral do ficheiro **[GEMINI.md](./GEMINI.md)**, que governa o ciclo de vida deste repositório. Este é o pilar central do projeto, determinando as regras rígidas, restrições e diretrizes de desenvolvimento.

## Princípios Arquiteturais

A solução baseia-se numa arquitetura focada em **Code-First** e orientada a camadas concêntricas (Clean Architecture), visando total isolamento do **Domínio** (regras puras de simulação de rede e sincronização de estado MMO) em relação à **Infraestrutura** (APIs nativas do Godot 4.7). O foco é garantir escalabilidade, segurança e manutenibilidade com Test-Driven Development (TDD) e injeção de dependências.
