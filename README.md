# QuanticNet (Core Infrastructure)

**Versão Atual:** `0.7.0` (Command-Based API & Jitter Buffer)

O **QuanticNet** é um ecossistema de rede *plug-and-play* autoritativo e de altíssimo desempenho, construído nativamente em **C++** (GDExtension) para a **Godot Engine 4.7**.

> ⚠️ **Decisão Arquitetural:** Este repositório foca ESTRITAMENTE no desenvolvimento da infraestrutura *Bare Metal*. Todo o desenvolvimento de domínios concretos, Grid Systems, Chunking e demos de "3D Open World MMO" foi migrado para o repositório externo [godot_quantic_net_demos](https://github.com/leonardosolisbadaro/godot_quantic_net_demos).

A arquitetura resolve as barreiras físicas da infraestrutura multiplayer (Client-Side Prediction, Server-Side Reconciliation, Snapshot Interpolation e Culling Espacial), permitindo a criação de domínios puros através do paradigma **Code-First** e **Clean Architecture**, sem qualquer acoplamento com a árvore visual (`SceneTree`) da Godot.

---

## 🚀 O Poder do Ecossistema (Fundações Concluídas)

- **Topologia Híbrida C++/GDScript:** Transporte seguro (DTLS), criptografia e cálculos vetoriais densos operam em milissegundos no Core (C++). A API consumida é 100% GDScript, limpa e declarativa.
- **Client-Side Prediction (Zero Input Lag):** Colisões locais e movimentação processadas de imediato, sem aguardar respostas de RTT da rede.
- **Delta Compression & Tick Híbrido:** Envio focado em *Deltas* (apenas o que mudou) e frequências individuais por entidade, respeitando estritamente o MTU via Priority Accumulator.
- **Spatial Hashing C++ (AoI):** Culling de rede ultra-rápido utilizando o `QNSpatialGrid`.
- **Lag Compensation:** Validação autoritativa e rebobinamento de *hitboxes* no passado (`QNWorldHistoryBuffer`) garantindo hitscan determinístico.
- **Dual Paradigm (State & Command-Based):** Suporta desde abordagens simples e ágeis (envio direto de estado preditivo) até fluxos rigorosamente competitivos (*Command-Based*) ancorados em um **Dynamic Jitter Buffer** no lado do servidor para total imunidade a manipulações de tempo de rede.
- **Anti-Cheat Determinístico:** Validação rústica de velocidade e limites, com *Snapback* absoluto ou desconexões (*Strikes*).

---

## 🧭 O Caminho Adiante

O desenvolvimento do QuanticNet é guiado de forma transparente. Para entender para onde estamos caminhando, consulte:

- **[TODO.md](./TODO.md):** Para acompanhar as fases táticas de curto prazo e os *Pull Requests* ativos (como as otimizações de *Worker Threads*).
- **[ROADMAP_MMO.md](./ROADMAP_MMO.md):** Para compreender a visão arquitetural de longo prazo do motor em C++ (Networked Physics, Structs POD e Server Meshing).

---

## 📚 Documentação e Guias

- **[A Demo Laboratório Interno](./addons/quantic_net/demo/demo_main.gd)**: O arquivo `demo_main.gd` deste repositório está oficialmente **congelado em escopo**. Ele serve exclusivamente como um laboratório rústico de testes unitários end-to-end e um tutorial cru de como consumir a API pública (sem mecânicas complexas, sem paredes, sem assets).
- **[Constituição GEMINI.md](./GEMINI.md)**: As regras fundamentais do projeto. Code-First, Clean Architecture e TDD rigoroso.
- **[Changelog](./CHANGELOG.md)**: Histórico linear de atualizações e refatorações.
- **[API Pública](./API_PUBLIC.md)**: Guia de integração e assinatura dos métodos do Autoload.

---

## 🏗️ Rodando o Laboratório (Client/Server)

No Windows, criamos um script para gerenciar a auto-topologia de testes de forma fácil e isolada (iniciando 1 Servidor invisível em background e 2 Clientes interligados localmente):

```powershell
powershell.exe -ExecutionPolicy Bypass -File toggle_demo.ps1
```

*(Para derrubar as instâncias e limpar as portas instantaneamente, basta executar o script de novo).*
