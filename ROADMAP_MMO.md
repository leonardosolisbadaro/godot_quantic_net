# ROADMAP MMO & COMPETITIVO: O Destino do QuanticNet Core

Este documento não é apenas um guia técnico; é uma carta de amor à infraestrutura *Bare-Metal*. É a visão do futuro definitivo para o motor **QuanticNet**, uma declaração de guerra contra gargalos de CPU e latência.

Tendo consolidado a nossa fundação com a **Versão 0.7.0** — que cravou com sucesso o *Client-Side Prediction*, o Culling Espacial em C++, a compensação de *Lag* e, acima de tudo, o novíssimo **Dual Paradigm** (com a implacável *Command-Based API* e o *Dynamic Input Jitter Buffer*) — o projeto agora levanta voo rumo à excelência bruta de performance.

> ⚠️ **A Fronteira Arquitetural:** O QuanticNet é e sempre será o *Motor de Infraestrutura de Baixo Nível*. Toda a aplicação prática de design de jogos, inventários, magias, ou simulações visuais de um "3D Open World MMO", encontram-se isoladas no repositório parceiro oficial [godot_quantic_net_demos](https://github.com/leonardosolisbadaro/godot_quantic_net_demos). Aqui, lidamos com os elétrons, a matemática e o silício.

---

## 🏛️ Os Alicerces Inquebráveis (Onde Estamos Hoje) ✅

O suor das trincheiras do TDD e da *Clean Architecture* nos trouxe até aqui. O ecossistema atual já domina nativamente os vilões clássicos do netcode:

- **Dual Paradigm Blindado:** O desenvolvedor agora tem o poder de escolher. Do envio ágil de estados para jogos PvE (*State-Based*), até o rigor competitivo de *eSports* (*Command-Based*), onde o servidor acumula *Inputs* determinísticos e os consome através de um atraso dinâmico no tempo exato, ignorando flutuações de rede e anulando *Speedhacks*.
- **Culling Milissegundo em C++:** O `QNSpatialGrid` resolve a vizinhança de milhares de entidades sem bloquear a *Main Thread* da Godot.
- **História Rebobinada:** O `QNWorldHistoryBuffer` nos concede *Lag Compensation* para hitscans perfeitos, permitindo "atirar no passado" e acertar no servidor.

---

## 🚀 O Horizonte (O Que Vamos Construir)

O futuro do QuanticNet é pautado por um único lema: **"Descarregar a Main Thread e Vetorizar a Lógica"**. Eis as batalhas que já decidimos que vamos vencer.

### 1. I/O Offloading e Lock-Free Ring Buffers (Curto Prazo)

A rede não pode ditar o FPS da sua física. O próximo passo (como mapeado no nosso `TODO.md`) é migrar a rotina bruta de *polling* do ENet e as desserializações de bytes pesadas (*Bit-Unpacking*) inteiramente para uma **Worker Thread em C++**. Os dados mastigados serão injetados de forma cirúrgica na Godot através de filas *Lock-Free* de memória contígua. A *Main Thread* da Godot servirá apenas para "ler o jornal" já impresso.

### 2. Tick Autoritativo Independente & Sleeping States (Curto Prazo)

O servidor abandonará o ciclo de renderização (`_physics_process`). O motor receberá um acumulador de *Tick* independente e cristalino, ditando o ritmo real do mundo (ex: estritos 20hz ou 60hz). Junto a isso, entidades em repouso absoluto entrarão em *Dormancy* de rede, economizando colossalmente a largura de banda.

### 3. Refinamento AAA e Estruturas POD (Médio Prazo)

A API do QuanticNet abraçará o *hotpath* definitivo. Substituiremos empacotamentos GDScript/Variants no C++ por *Structs POD* (Plain Old Data) de tamanho fixo na memória. O sistema de confirmações de pacotes (ACK-Tracking) e os cálculos de compressão de Delta utilizarão comparações *Bitwise XOR* vetorizadas (SIMD), levando o custo de CPU a frações de milissegundo.

### 4. Networked Physics e RPC Semântico (Médio Prazo)

Para suportar montanhas de detritos ou veículos balísticos, introduziremos um pacote dedicado `NetProfile.RIGID_BODY`, capaz de decodificar *Linear* e *Angular Velocity* com precisão. Em paralelo, a engine ganhará um canal confiável e desacoplado (*Reliable Delivery*) para eventos semânticos e replicação pontual de inventários (ex: "RPC: Baú Aberto"), sem sujar os minúsculos e implacáveis pacotes do loop posicional UDP.

### 5. Dead Reckoning Agressivo (Longo Prazo)

O *Jitter Buffer* não faz milagres se o cabo for cortado. O QuanticNet adotará a extrapolação de vetores diretamente em C++. Quando a perda de pacotes ressecar o buffer, o motor cliente continuará projetando autonomamente os NPCs e inimigos numa sobrevida matemática suave e ilusória, salvando a experiência do jogador durante instabilidades agressivas de latência ou perda de pacotes.

### 6. Server Meshing e Escalabilidade Massiva (O Horizonte Final)

Quando as fundações acima convergirem, o monolito autoritativo do servidor será fragmentado. O QuanticNet proverá as amarras infraestruturais para **Server Meshing**, permitindo que múltiplos binários *Headless* (nós de processamento na Cloud) gerenciem "Chunks" do mapa de forma paralela, roteando e injetando entidades simultaneamente no Culling Espacial sem que o cliente sequer perceba a transição de zonas.

---

Este é o futuro que desenhamos. Cada linha de código em C++, cada teste unitário no GUT e cada refatoração cimentará o QuanticNet não apenas como um plugin, mas como o coração imutável e soberano do seu próximo grande jogo na Godot 4.
