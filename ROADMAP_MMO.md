# ROADMAP MMO & COMPETITIVO: O Destino do QuanticNet

Este documento decreta a visão arquitetural de longo prazo para a evolução do **QuanticNet**. Tendo consolidado com sucesso a base estrutural de baixo nível (Client-Side Prediction, DTLS, Memória controlada e C++ Spatial Hashing), o projeto agora reinicia seu ciclo na fronteira de domínios **MMO Massivos (Grid/Chunk Systems) e instâncias competitivas**.

> **Regra de Ouro:** Este roadmap dita *o que* vamos construir, de forma que as *decisões de interface do presente* jamais criem amarras ou custos prematuros. O código permanecerá brutalmente simples, mas moldado para a expansão matemática severa que o futuro exige.

## Pilares Fundamentais (Concluídos e Blindados) ✅

A arquitetura já acomoda com robustez de C++ e segurança de GDScript os seguintes pilares fundacionais:

- **Delta Compression & Jitter Buffer:** Tráfego quantizado por Sequence ACKs e absorção elástica de flutuações de latência via Netem.
- **Tick Híbrido & Priority Accumulator:** Matriz de escalonamento que respeita estritamente o limite físico da rede (MTU), com frequências isoladas por entidade.
- **Spatial Hashing em C++ (QNSpatialGrid):** O despache autoritativo agora é ciente do espaço tridimensional do mundo, mitigando globalmente o tráfego de dados irrelevantes através do Area of Interest.
- **Lag Compensation (World History Buffer):** Rebobinamento temporal contínuo do servidor para *Hit Registration* milimétrico, independente do *ping* do atirador.
- **Playground Educacional Definitivo (Demo Bare Metal):** O `demo_main.gd` foi consolidado como o laboratório prático oficial para simulações educacionais e test-bed de novas topologias, substituindo abstrações visuais limitantes por mecânicas de código sólidas.

---

## O Futuro (Os Próximos Passos) 🚀

### 1. Spatial Partitioning e Chunk Systems (Curto Prazo)

A prioridade atual é demonstrar visualmente e mecanicamente as benesses matemáticas do recém-criado `QNSpatialGrid` (C++).
O `demo_main.gd` evoluirá para suportar nativamente e demonstrar a divisão de cenários em grandes "Grids" (Chunks). O desafio central será ilustrar a transição dinâmica e ininterrupta de jogadores e entidades transitando entre essas fronteiras lógicas sem saturar a banda global do servidor, mantendo o Area of Interest restrito unicamente aos quadrantes adjacentes. A demo servirá de documentação ativa para a implementação de domínios de "Mapa Único" ou "Chunk System".

### 2. Networked Physics e Sleeping States (Médio Prazo)

As entidades regidas puramente pela física (RigidBodies) exigirão um protocolo de sincronização dedicado (`NetProfile.RIGID_BODY`).
A API do QuanticNet passará a trafegar vetores escaláveis de *Linear* e *Angular Velocity*, introduzindo um culling agressivo de banda para entidades em repouso (Sleeping States). Isso é vital para mundos densos com destroços, baús físicos e detritos persistentes interativos.

### 3. Object Replication e RPC Desacoplado (Médio Prazo)

Atualmente o QuanticNet sincroniza *estado posicional* a altíssima performance, mas mundos MMO exigem contextos dinâmicos.
Desenvolveremos um canal secundário de *Reliable Delivery* para que o servidor possa informar tardiamente a novos clientes a natureza semântica do ambiente (ex: "Entidade 5000 é um Orc", "Entidade 900 é uma Poção"), habilitando o despache de feitiços, inventários e transações garantidas sem poluir ou atrasar o pipeline super veloz da interpolação cinética contínua.

### 4. Dead Reckoning Agressivo e Extrapolação (Longo Prazo)

Quando a nuvem de tempestade da internet chegar e o jogador perder pacotes numa severidade onde o Jitter Buffer resseque por completo: as entidades inimigas e aliados não congelarão na tela.
Um cálculo matemático preditivo de continuidade de vetores manterá os alvos operando numa sobrevida ilusória calculada com precisão, minimizando engasgos grotescos e disfarçando cortes massivos repentinos de TCP/UDP no lado do cliente.

### 5. Cloud Deploy e Server Meshing (Horizonte Final)

Com o Grid System robustecido na demo e testado em Headless, o passo derradeiro será conceber a arquitetura para desacoplar o monolito autoritativo, permitindo que múltiplos contêineres Docker (Headless) gerenciem "Chunks" adjacentes do mundo virtual de forma paralela (Server Meshing), habilitando populações de jogadores simultâneos verdadeiramente ilimitadas em um único *shard* de mapa contínuo.

---

O fim dessa rota consolida o motor QuanticNet como uma alternativa irrefutável e determinística às ferramentas visuais nativas de *High-level Multiplayer*, devolvendo a soberania do Netcode à arquitetura (Code-First) e ao rigor militar do TDD.
