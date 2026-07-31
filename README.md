# QuanticNet

**Versão Atual:** `0.3.0`

Plugin de network (`QuanticNet`) `plug and play`, focado no desenvolvimento de jogos `3D Open World MMO` usando a `Godot Engine 4.7`. Arquitetado a partir do zero focado em **Code-First**, **Test-Driven Development (TDD)** e **Clean Architecture**. Eliminando a dependência de editores visuais para lógicas de negócio.

## A Constituição do Projeto

Nenhum código novo deve ser gerado sem a aprovação explícita e o cumprimento integral do ficheiro **[GEMINI.md](./GEMINI.md)**, que governa o ciclo de vida deste repositório. Este é o pilar central do projeto, determinando as regras rígidas, restrições e diretrizes de desenvolvimento.

## Princípios Arquiteturais

A solução baseia-se numa arquitetura focada em **Code-First** e orientada a camadas concêntricas (Clean Architecture), visando total isolamento do **Domínio** (regras puras de simulação de rede e sincronização de estado MMO) em relação à **Infraestrutura** (APIs nativas do Godot 4.7). O foco é garantir escalabilidade, segurança e manutenibilidade com Test-Driven Development (TDD) e injeção de dependências.

## Situação Atual

A fundação arquitetural e de rede está concluída. As sessões de host e cliente interagem transparentemente com a infraestrutura Godot (MultiplayerAPI e ENet), incluindo DTLS e uma camada customizável de Netem. O plugin reside isolado em `addons/quantic_net/`.

## Documentação e Demos

A arquitetura de documentação do QuanticNet divide o papel das demonstrações em duas frentes distintas:

1. **Bare Metal Demo (Teste de Aceitação):**
   O plugin acompanha uma cena mínima embutida em `addons/quantic_net/demo/`. O objetivo desta demonstração é ser 100% *plug-and-play* e provar a infraestrutura base (host, join, submissão de estados preditivos e processamento de snapbacks) sem **nenhum** acoplamento a UI, mecânicas ou complexidade de gameplay.

2. **Repositório de Demos Ricas (`quantic-net-demos`):**
   Para explorar o **espaço de possibilidades** do plugin (como *Area of Interest - AoI*, perfis competitivos/MMO e sincronização de dezenas de NPCs independentes), o desenvolvimento e testes visuais migrarão para um repositório secundário e dedicado. Isso assegura que o repositório principal deste addon permaneça um *core* purista de infraestrutura e domínio, obedecendo à risca a *Clean Architecture*.

Para aprender a consumir as funções e sinais na prática, inicie pela leitura do **[API_PUBLIC.md](./API_PUBLIC.md)**.
