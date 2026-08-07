# ROADMAP MMO & COMPETITIVO: O Destino do QuanticNet Core

Este documento decreta a visão arquitetural de longo prazo para a evolução do motor **QuanticNet**. Tendo consolidado com sucesso a base estrutural de baixo nível (Client-Side Prediction, DTLS, Memória controlada e C++ Spatial Hashing), o projeto focará intensamente em performance *Bare Metal* a partir de agora.

> ⚠️ **Fronteira Arquitetural:** Este repositório constrói o *Motor de Infraestrutura*. A aplicação prática em grande escala (Grid/Chunk Systems visuais, demonstrações de MMOs complexos, simulações massivas) reside agora no repositório parceiro oficial `godot_quantic_net_demos`.

## Pilares Fundamentais (Concluídos e Blindados) ✅

- **Delta Compression & Jitter Buffer:** Absorção elástica de latência.
- **Tick Híbrido & Priority Accumulator:** Frequências individuais respeitando as margens do MTU.
- **Spatial Hashing em C++ (QNSpatialGrid):** Filtragem de tráfego via Culling.
- **Lag Compensation (World History Buffer):** Hit-registration milimétrico retroativo.
- **Laboratório Rústico Interno:** A `demo_main.gd` foi congelada. Ela serve apenas para atestar matematicamente o funcionamento do Core end-to-end (sem o fardo de assets e game design acoplado).

---

## O Futuro (Os Próximos Passos do Motor) 🚀

### 1. Refinamento AAA e Otimização Extrema (Curto Prazo)

A prioridade absoluta e bloqueante para qualquer nova feature no GDExtension é a transformação do *hotpath* de serialização.
O motor adotará estruturas em C++ de tamanho rigorosamente fixo (*Struct POD*), abandonando as passagens custosas do modelo `Variant`/`Dictionary`. Implementaremos comparações *Bitwise XOR* (vetorizadas com SIMD quando possível) e um sistema de rastreamento de confirmações (ACK-Tracking) alocado em memória contígua de 32 bits (zero allocation).
No lado do cliente, a predição local dará um salto com a introdução de *Elastic Time* (Clock Steering) e passos fixos matemáticos rígidos, garantindo a aniquilação completa do jitter flutuante de delta.

### 2. Networked Physics e Sleeping States (Médio Prazo)

As entidades regidas puramente por cálculos físicos (RigidBodies) exigirão um protocolo de empacotamento cinemático dedicado na engine (`NetProfile.RIGID_BODY`).
A API do QuanticNet passará a decodificar vetores otimizados de *Linear* e *Angular Velocity*, introduzindo um culling agressivo (C++) para entidades em repouso (Sleeping States). Isso entregará a capacidade bruta de sincronizar milhares de detritos físicos colidindo de forma massiva com um gasto irrisório de banda.

### 3. Object Replication e RPC Desacoplado (Médio Prazo)

Atualmente o QuanticNet sincroniza *estado posicional* a altíssima performance, mas o framework de MMO exige o envio garantido de contextos dinâmicos.
A infraestrutura receberá um canal secundário de *Reliable Delivery* semântico. O servidor poderá empacotar e informar paralelamente a tipagem ou eventos únicos de objetos via spawn determinístico (ex: "Entidade 5000 é um Orc que conjurou Fireball"). Isso habilita o despache rígido de inventários e ações vitais sem sujar ou atrasar a alta frequência de varredura posicional de frames I/P.

### 4. Dead Reckoning Agressivo e Extrapolação (Longo Prazo)

Para viabilizar cenários mobile agressivos: quando a conexão enfraquecer e a perda de pacotes ressecar por completo o Jitter Buffer do jogador.
Um cálculo matemático preditivo de continuidade de vetores acionado a nível de C++ manterá as entidades operando numa sobrevida ilusória autônoma no cliente, minimizando engasgos grotescos durante disrupções temporárias da camada UDP.

### 5. Suporte de Base Cloud e Server Meshing (Horizonte Final)

Com o C++ Core polido em seu limite prático (POD/SIMD), a engine estará pronta para prover as amarras estruturais (API e ganchos) para **Server Meshing**. A topologia da Engine suportará que o consumidor do plugin desacople o monolito autoritativo, suportando que múltiplos instanciamentos Headless externos gerenciem "Chunks" (Grids) de forma paralela e injetem dados de forma simultânea e segura no `QNSpatialGrid`.

---

O fim dessa rota consolida o motor QuanticNet como a base infraestrutural nativa (Code-First / C++) definitiva e irrefutável para jogos de altíssimo desempenho e escalonamento na Godot 4.7.
