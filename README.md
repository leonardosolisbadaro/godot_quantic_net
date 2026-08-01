# QuanticNet

**Versão Atual:** `0.3.0`

Plugin de network (`QuanticNet`) `plug-and-play`, focado no desenvolvimento de jogos `3D Open World MMO` e Competitivos usando a `Godot Engine 4.7`. Arquitetado a partir do zero focado em **Code-First**, **Test-Driven Development (TDD)** e **Clean Architecture**. Elimina a dependência de editores visuais para lógicas de negócio.

## A Constituição do Projeto

Nenhum código novo deve ser gerado sem a aprovação explícita e o cumprimento integral do ficheiro **[GEMINI.md](./GEMINI.md)**, que governa o ciclo de vida deste repositório. Este é o pilar central do projeto, determinando as regras rígidas, restrições e diretrizes de desenvolvimento.

## Princípios Arquiteturais

A solução baseia-se numa arquitetura focada em **Code-First** e orientada a camadas concêntricas (Clean Architecture), visando total isolamento do **Domínio** (regras puras de simulação de rede e sincronização de estado MMO) em relação à **Infraestrutura** (APIs nativas do Godot 4.7). O foco é garantir escalabilidade, segurança e manutenibilidade com Test-Driven Development (TDD) e injeção de dependências.

## Estado Atual da Tecnologia (Features)

A fundação arquitetural e de rede está **concluída e robusta**. As sessões de host e cliente interagem transparentemente com a infraestrutura Godot (MultiplayerAPI e ENet), residindo isoladas em `addons/quantic_net/`.

O motor de rede atualmente suporta o "Estado da Arte" do netcode de ação moderno:

- **Client-Side Prediction & Server Reconciliation (Snapback)**: O jogador local move-se instantaneamente, e o servidor autoritativo emite correções apenas quando fraudes ou dessincronizações severas são detectadas.
- **Snapshot Interpolation (Jitter Buffer)**: Mitiga a percepção de perda de pacotes e flutuações de latência interpolando fluidamente os avatares remotos no passado.
- **Delta Compression & ACKs**: O servidor quantiza a banda de rede enviando apenas P-Frames (Deltas) ao invés de I-Frames integrais, reduzindo drasticamente o tamanho do payload.
- **Priority Accumulator & Hybrid Ticking**: Gestão inteligente de banda limitando o pacote pelo MTU (Maximum Transmission Unit) da rede, controlando o Tick Rate de cada entidade com base em sua prioridade e distância (Spatial Culling).
- **DTLS Auth & Anti-Cheat**: Conexões seguras e validação rígida de distâncias e velocidades de todos os clientes no lado servidor.
- **Simulador Netem Integrado**: Injeção proposital de latência, jitter e packet loss na própria engine para testes em ambiente agressivo.

## O Futuro (Visão ROADMAP MMO)

Inspirado nas teses absolutas de Glenn Fiedler (Gaffer on Games) e Gabriel Gambetta, o QuanticNet está ativamente em transição para sua **Fase 9**, que contemplará:

1. **Lag Compensation (Server-Side Rewind)**: Histórico global no servidor permitindo colisões precisas (Hit Registration) em jogos de tiro, re-simulando o passado para compensar a latência do atirador.
2. **Dead Reckoning & Extrapolação**: Algoritmos de sobrevivência à perda aguda de rede, prevendo continuidades direcionais para manter a fluidez quando os pacotes pararem de chegar.
3. **Networked Physics**: Integração profunda de *Rigid Bodies*, sincronizando velocidade linear, angular, torques e atrito.

*(Para o planejamento técnico detalhado, consulte o **[ROADMAP_MMO.md](./ROADMAP_MMO.md)** e as tarefas do **[TODO.md](./TODO.md)**).*

## Documentação e Demos

A arquitetura de documentação do QuanticNet divide o papel das demonstrações em duas frentes distintas:

1. **Bare Metal Demo (Teste de Aceitação):**
   O plugin acompanha uma cena mínima embutida em `addons/quantic_net/demo/`. O objetivo desta demonstração é ser 100% *plug-and-play* e provar a infraestrutura base (host, join, submissão de estados preditivos e processamento de snapbacks) sem **nenhum** acoplamento a UI, mecânicas ou complexidade de gameplay.

2. **Repositório de Demos Ricas (`quantic-net-demos`):**
   Para explorar o **espaço de possibilidades** do plugin (como perfis competitivos/MMO e sincronização de física complexa), o desenvolvimento e testes visuais migrarão para um repositório secundário e dedicado, blindando o repositório principal contra acoplamento visual.

Para aprender a consumir as funções e sinais do Autoload na prática, inicie pela leitura rigorosa da **[API_PUBLIC.md](./API_PUBLIC.md)**.
