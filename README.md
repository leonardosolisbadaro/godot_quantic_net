# QuanticNet

**Versão Atual:** `0.6.0` (Bare Metal Playground & Network Core Stabilization)

O **QuanticNet** é um ecossistema de rede *plug-and-play* autoritativo e de altíssimo desempenho, construído nativamente em **C++** (GDExtension) para a **Godot Engine 4.7**. Focado primariamente no desenvolvimento de `3D Open World MMOs` e arenas hiper-competitivas.

Ele resolve os desafios mais complexos de infraestrutura Multiplayer (Client-Side Prediction, Server-Side Reconciliation, Snapshot Interpolation e Culling Espacial de Rede), entregando estabilidade sem exigir acoplamento com a árvore visual da Godot.

## 🚀 Potenciais e Funcionalidades

- **Zero Input Lag:** Predição de Cliente (Client-Side Prediction) que não espera a rede para processar colisões locais e inputs do jogador.
- **Topologia Híbrida C++/GDScript:** O transporte e cálculo vetorial é processado a nível de CPU em milissegundos no Core (C++), mas a API que você consome é 100% GDScript, limpa e assíncrona.
- **Isolamento Absoluto:** Completamente desvinculado do `SceneTree` durante o processamento. A renderização acontece em `_process` por interpolação, sem os travamentos clássicos atrelados ao tick de rede (`_physics_process`).
- **Segurança Determinística (Anti-Cheat Base):** Validação rígida no servidor de velocidade de movimento e posições. O cliente tenta "enganar" o servidor e recebe um imediato Snapback e eventuais "Strikes" até a expulsão.
- **Cross-Platform Seguro:** Código mitigado e homologado para não sofrer problemas clássicos de Undefined Behavior de compiladores C++ (como inversão de matrizes de coordenadas induzida por compiladores em Windows/MSVC).

## 📚 Documentação e Guias

Toda a arquitetura é baseada nos princípios do **Code-First**, **Clean Architecture** e regida estritamente pelas diretrizes do nosso [GEMINI.md](./GEMINI.md).

- **[API Pública e Casca de Uso (Autoload)](./API_PUBLIC.md)**: Documentação completa dos métodos expostos (ex: `host`, `join`, `submit_state`, `get_remote_state`), sinais disponíveis e guias de integração arquitetural.
- **[A Demo Definitiva (Bare Metal Playground)](./addons/quantic_net/demo/README.md)**: Nós não escrevemos apenas código; nós provamos que ele funciona! A demonstração é uma verdadeira sala de aula de boas práticas em Clean Architecture aplicadas ao GDScript, contendo exemplos reais de códigos independentes de SceneTree.
- **[Changelog](./CHANGELOG.md)**: Acompanhe o ciclo de desenvolvimento contínuo desta engine.

## 🏗️ Rodando a Demonstração (Client/Server)

No Windows, execute o script em PowerShell para abrir o Servidor e 2 Clientes interligados de forma automática:
```powershell
powershell.exe -ExecutionPolicy Bypass -File toggle_demo.ps1
```
(Para fechar as instâncias todas de uma vez, basta rodar o mesmo comando novamente).
