# QuanticNet

**VersÃ£o Atual:** `0.2.0`

Plugin de network (`QuanticNet`) `plug and play`, focado no desenvolvimento de jogos `3D Open World MMO` usando a `Godot Engine 4.7`. Arquitetada absoluta (a partir do zero) focada em **Code-First**, **Test-Driven Development (TDD)** e **Clean Architecture**. Eliminando a dependÃªncia de editores visuais para lÃ³gicas de negÃ³cio.

## A ConstituiÃ§Ã£o do Projeto

Nenhum cÃ³digo novo deve ser gerado sem a aprovaÃ§Ã£o explÃ­cita e o cumprimento integral do ficheiro **[GEMINI.md](./GEMINI.md)**, que governa o ciclo de vida deste repositÃ³rio. Este Ã© o pilar central do projeto, determinando as regras rÃ­gidas, restriÃ§Ãµes e diretrizes de desenvolvimento.

## PrincÃ­pios Arquiteturais

A soluÃ§Ã£o baseia-se numa arquitetura focada em **Code-First** e orientada a camadas concÃªntricas (Clean Architecture), visando total isolamento do **DomÃ­nio** (regras puras de simulaÃ§Ã£o de rede e sincronizaÃ§Ã£o de estado MMO) em relaÃ§Ã£o Ã  **Infraestrutura** (APIs nativas do Godot 4.7). O foco Ã© garantir escalabilidade, seguranÃ§a e manutenibilidade com Test-Driven Development (TDD) e injeÃ§Ã£o de dependÃªncias.

## Situação Atual

A fundação arquitetural e de rede está concluída. As sessões do cliente e do servidor estão integradas com a infraestrutura nativa do Godot (MultiplayerAPI e ENet), incluindo DTLS e uma camada customizável de testes de latência e perda (Netem). Os testes cobrem 100% da lógica e integram com sucesso simulações severas de Headless (Host ↔ 2 Clients). Adicionalmente, a cena de demonstração (`demo/`) provê um exemplo consumível 100% Code-First para provar o sistema plug-and-play. O próximo passo e fase final (PR 10) é o encapsulamento para CI/CD e liberação na Asset Library.
