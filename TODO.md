# TODO

Plugin de network (`QuanticNet`) `plug and play`, focado no desenvolvimento de jogos `3D Open World MMO` usando a `Godot Engine 4.7`. Arquitetada absoluta (a partir do zero) focada em **Code-First**, **Test-Driven Development (TDD)** e **Clean Architecture**. Eliminando a dependência de editores visuais para lógicas de negócio.

---

## FUNDAÇÃO: CONSTRUÇÃO DO BOILERPLATE

### Fase 1: Arquitetura [x]

Configuração do ecossistema, IDE e amarras do Code-First, TDD e Clean Architecture.

- [x] Editar `GEMINI.md` definindo as regras arquiteturais, uso de GDScript docstrings e metodologia AAA.
- [x] Instalar e configurar ambiente de testes (bitwes/Gut).

### Fase 2: Core Domain (TDD Rigoroso) [/]

O coração da simulação e validação, agnóstico à infraestrutura de rede.

- [x] Criar a "casca" do plugin Godot (`plugin.cfg` e script `@tool` herdando de `EditorPlugin`).
- [x] Configurar inicialização do plugin (registro de singleton) utilizando as assinaturas exatas da Godot Engine 4.7 (`_enable_plugin` e `_disable_plugin`).
- [x] Injetar o Autoload principal (`quantic_net_autoload.gd`) como fachada (Single-Point of Entry) baseada em sinais para orquestrar e delegar chamadas da Engine.
- [x] Estruturar a árvore de diretórios enraizada nos padrões de Clean Architecture (`domain/`, `use_cases/`, `adapters/`, `infrastructure/`).
- [x] TDD: Implementar `QNSerializer` (quantização binária de 19 Bytes para estado/snapback).
- [x] TDD: Implementar `QNClockSync` (cálculo de RTT e sincronização de tempo do servidor).
- [ ] TDD: Implementar `QNLossTracker` (monitoramento de perda de pacotes via tracking de sequência).
- [ ] TDD: Implementar `QNInterpBuffer` (armazenamento circular e amostragem no passado remoto).
- [ ] TDD: Implementar `QNServerValidator` (clamping, validação anti-teleporte e rejeição baseada no tempo).
- [ ] TDD: Implementar `QNInputBuffer` (armazenamento e replay local de inputs - base do client prediction).

### Fase 3: Casos de Uso & Adaptadores (TDD)

Orquestrando o fluxo das entidades para o motor do jogo.

- [ ] Implementar fluxo de `Prediction` local.
- [ ] Implementar fluxo de reconciliação a partir de Snapbacks autoritativos.
- [ ] Criar adaptadores de autenticação (validação via token/secret).
- [ ] Estruturar Controladores que traduzam RPCs brutos para os Use Cases.

### Fase 4: Infraestrutura & Engine (Integração)

Comunicação e APIs Godot nativas.

- [ ] Implementar integração de transporte seguro (`ENetConnection` com DTLS via certificados `user://`).
- [ ] Acoplar sistema MultiPlayer usando `SceneMultiplayer` e extensions (`MultiplayerAPIExtension` e `MultiplayerPeerExtension`).
- [ ] Integrar sistema Netem (simulador de rede adversa/perda de pacotes e jitter) direto no envio.
- [ ] Fechar ciclo completo conectando o autoload `QuanticNet` aos adaptadores implementados.
