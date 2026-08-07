# QuanticNet

**Versão Atual:** `0.6.0` (Fronteira MMO & Spatial Partitioning)

O **QuanticNet** é um ecossistema de rede *plug-and-play* autoritativo e de altíssimo desempenho, construído nativamente em **C++** (GDExtension) para a **Godot Engine 4.7**. Ele é focado no desenvolvimento escalável de **3D Open World MMOs** e instâncias competitivas.

A arquitetura resolve as barreiras físicas da infraestrutura multiplayer (Client-Side Prediction, Server-Side Reconciliation, Snapshot Interpolation e Culling Espacial), permitindo a criação de domínios puros através do paradigma **Code-First** e **Clean Architecture**, sem qualquer acoplamento com a árvore visual (`SceneTree`) da Godot.

---

## 🚀 O Poder do Ecossistema

Com a conclusão da Fundação Estrutural (Fases 1 a 10 arquivadas), o projeto solidificou seus pilares:

- **Topologia Híbrida C++/GDScript:** O transporte seguro (DTLS), a criptografia e os cálculos vetoriais densos operam em milissegundos no Core (C++), mas a API que você consome é 100% GDScript, limpa e declarativa.
- **Client-Side Prediction (Zero Input Lag):** Colisões locais e movimentação processadas de imediato, sem aguardar respostas de RTT da rede (suavizado via Jitter Buffer dinâmico).
- **Delta Compression & Tick Híbrido:** Envio focado em *Deltas* (apenas o que mudou) e frequências individuais por entidade (ex: Projéteis a 60Hz, Props a 5Hz), respeitando agressivamente o limite global de pacote (MTU) via Priority Accumulator.
- **Spatial Hashing C++ (AoI):** Culling de rede ultra-rápido utilizando o `QNSpatialGrid`. O despache global desconsidera automaticamente entidades fisicamente distantes, escalando a simulação de cenários densos sem inflar a banda.
- **Lag Compensation:** Validação autoritativa e rebobinamento de *hitboxes* no passado (`QNWorldHistoryBuffer`) para permitir combates milimétricos (hitscan) independentes de latência.
- **Anti-Cheat Determinístico:** Validação rústica de velocidade, limites e autenticidade. Clientes infratores recebem *Snapback* absoluto ou desconexões punitivas (*Strikes*).

---

## 🧭 O Caminho Adiante (A Nova Fase 1)

O QuanticNet adentrou a sua fase de integração **MMO Maciço (Grid/Chunk Systems)**. Os próximos objetivos incluem:

1. Evoluir a **Demo Bare Metal** para instanciar cenários colossais suportados por Chunk Systems e transições contínuas utilizando o Culling ativo.
2. Integração de **Networked Physics** para sincronização dedicada de RigidBodies e *Sleeping states* (Economia de banda massiva de detritos físicos).
3. **Replicação Semântica e Dinâmica** de tipagens de classe durante a sessão através de um RPC Desacoplado confiável.
4. Testes rigorosos de escalabilidade e saturação de MTU no formato de deploy **Cloud Headless** (Docker).

Acompanhe nossa trilha de desenvolvimento interativa no [TODO.md](./TODO.md) e o planejamento futuro definitivo no [ROADMAP_MMO.md](./ROADMAP_MMO.md).

---

## 📚 Documentação e Guias

O desenvolvimento do QuanticNet obedece fielmente ao rigor metodológico da nossa Constituição de Arquitetura [GEMINI.md](./GEMINI.md), sendo amparado inteiramente por Test-Driven Development (TDD).

- **[A Demo Definitiva (Playground Educativo)](./addons/quantic_net/demo/demo_main.gd)**: O `demo_main.gd` foi consolidado como o laboratório ativo e educacional do projeto. Sem abstrações confusas ou lógicas nichadas de gameplay limitantes, este arquivo é o melhor local para testemunhar o QuanticNet manipulando tick híbrido, client-side prediction, Netem (emulador de redes hostis) e Lag Compensation na prática, de forma *Bare Metal*.
- **[Changelog](./CHANGELOG.md)**: Histórico linear e detalhado das atualizações, refatorações e conquistas arquiteturais.
- **[API Pública](./API_PUBLIC.md)** *(Em constante expansão)*: Guia de integração estrutural e referência dos métodos de entrada (*Single Point of Entry*) expostos globalmente pelo Autoload.

---

## 🏗️ Rodando a Demonstração (Client/Server)

No Windows, criamos um script para gerenciar a Auto-Topologia (Iniciando de forma automatizada e invisível 1 Servidor em background e abrindo 2 Clientes locais paralelos e interligados):

```powershell
powershell.exe -ExecutionPolicy Bypass -File toggle_demo.ps1
```

*(Para encerrar todas as instâncias em lote simultaneamente e limpar portas presas, execute o mesmo comando novamente).*
