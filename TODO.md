# TODO: QuanticNet (Core Infrastructure) v0.9.0-beta

Plugin de network autoritativo (`QuanticNet`) construído em C++ (GDExtension) para Godot 4.7.
Este repositório é estritamente infraestrutura *Bare Metal*. Demos de gameplay e MMOs concretos residem no repositório externo [godot_quantic_net_demos](https://github.com/leonardosolisbadaro/godot_quantic_net_demos).

---

## 🚨 FASE 1: O Sistema de Chunks e Validação Híbrida (AAA)

*Foco total na engenharia de mapas e segurança geométrica contínua.*

### PR 1 — Arquitetura Híbrida: Validação Server-Side (NavMesh & Raycasts)

* [x] Exportar NavMesh (NavigationRegion3D) do mapa e carregá-lo no contexto do Servidor Dedicado.
* [x] Implementar um callback (Hook) ou iterador no Servidor para interceptar posições recebidas de clientes.
* [x] Utilizar `NavigationServer3D.map_get_closest_point` para validar se a coordenada (X, Z) do pacote de movimento é permitida.

### PR 2 — Chunk Manager (Seamless Grid)

* [ ] Criar `qn_chunk_manager.gd` na Demo.
* [ ] Gerar Grid de chão 3D dinamicamente a partir da coordenada (0,0) (Ex: raio 3x3 chunks).
* [ ] Substituir o `open_world_floor` estático pelo carregamento dinâmico do Grid.
* [ ] Adicionar lógica de Streaming (Load/Unload chunks ao afastar do centro).

### PR 3 — Validação Híbrida em Relevos

* [ ] Alterar o `qn_chunk_manager.gd` para gerar malhas 3D e NavMeshes com relevos matemáticos (rampas/escadas).
* [ ] Validar a detecção de Flyhack (eixo Y) e a geração de Snapbacks verticais no Servidor.

---

## 🌐 FASE 2: Gameplay Autoritativo

*Foco em testar e aplicar 100% do potencial da API do QuanticNet em um cenário de MMO real.*

### PR 1 — Integração de OpCodes Complexos

* [ ] Utilizar `send_game_packet` para gerenciar a conjuração de magias (cast bars e interrupções autoritativas).
* [ ] Substituir projéteis simulados no cliente por Raycasts validados com Lag Compensation (`query_raycast` no passado).

### PR 2 — Culling Avançado e Instâncias (Monstros e NPCs)

* [ ] Instanciar NPCs patrulhando livremente pelos Chunks carregados.
* [ ] Associar perfis de baixa prioridade (`QNEntityProfile`) aos NPCs distantes e garantir que o *Spatial Culling* poupe a banda dos clientes.

---

## 🗄️ HISTÓRICO E LEGADO (Concluído em v0.8.0)

* **Tick Server-Side Independente & Dormancy:** _physics_process substituído por acumulador. Entidades agora entram em sono profundo (TYPE_SLEEP).
* **Transporte Nativo:** ENet/DTLS integrado via GDExtension.
* **Paradigma Híbrido:** Suporte a Command-Based (submit_input) e State-Based (submit_state).
* **Worker Threads (I/O Offloading):** Desserialização e ENet rodando em thread paralela via `QNWirePeer` com Lock-Free Ring Buffers.
* **Input Jitter Buffer:** Catch-up físico e absorção dinâmica de flutuações de rede no Host.
* **Otimização de Memória Extrema:** Estruturas POD Contíguas (`QNEntityState`) sem overhead.
* **Queries Espaciais & Lag Compensation:** `QNWorldHistoryBuffer` (Histórico de 60 frames passados).
* **Entity Profiles & Regions:** Culling espacial (AABB) dinâmico e perfis assíncronos.

---

## 🧊 ICEBOX (Tarefas Congeladas)

* **Ack-Tracking no Delta Serializer:** Removido da linha principal para focar no design de domínio. Aguardando a fase de stress test para ser reimplementado.
* **Solver Cinemático Stateless em C++ (`QNKinematicSolver`):** Congelada aguardando necessidade real de colisão nativa pesada.
