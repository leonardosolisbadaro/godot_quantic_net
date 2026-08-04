# QuanticNet

**Versão Atual:** `0.4.0` (Stable Foundation)

O **QuanticNet** é um ecossistema de rede *plug-and-play* autoritativo construído para a **Godot Engine 4.7**. Focado estritamente na criação de jogos `3D Open World MMO` e arenas competitivas, ele resolve os desafios clássicos de infraestrutura de rede, despache e reconciliação sem acoplar a lógica de domínio aos nós visuais da Engine.

A sua arquitetura baseia-se desde a raiz no **Code-First**, **Test-Driven Development (TDD)** rigoroso via *bitwes/Gut* e na topologia de **Clean Architecture**, eliminando acoplamentos desnecessários e dependências de UI.

---

## 🏛️ A Constituição do Projeto

A evolução deste repositório é rigidamente governada pelo arquivo **[GEMINI.md](./GEMINI.md)**. O arquivo define o protocolo inegociável de trabalho: nenhuma linha de domínio ou adaptador é escrita sem que um teste unitário (`.gd`) falhando dite o seu comportamento, garantindo um código imutavelmente seguro e livre de vazamentos de memória (ObjectDB Leaks blindados).

## 💡 Princípios Arquiteturais

A solução baseia-se em camadas concêntricas visando o total isolamento do **Core Domain** em relação ao *Framework* da Godot:

- **Domínio e Casos de Uso:** As regras puras (Sincronização de Estado, `QNServerValidator`, `QNInterpBuffer`, Acumuladores de Prioridade) não conhecem *Nodes*, não despacham física e não tocam em *Input*. Tudo é validado em frações de bytes.
- **Interface e Adaptadores:** O uso da API nativa da Godot 4.7 (`MultiplayerAPIExtension`, `ENetConnection`) reside exclusivamente na fronteira. O Autoload do `QuanticNet` rege a máquina de estados atuando como o ponto único de entrada (Single-Point of Entry) isolado por sinais.

## 🚀 Estado da Arte: Features (v0.3.0)

A fundação arquitetural encontra-se **estável e homologada** sob testes de integração pesados (DTLS, Netem, Loopback de Hosts e Clientes e Memory Leaks exterminados). O motor de rede já dispõe de:

- **Client-Side Prediction & Server Reconciliation (Snapback)**: O jogador move-se instantaneamente no lado do cliente. O servidor autoritativo emite *snapbacks* (correções forçadas) seguidas de re-aplicação assíncrona de inputs unicamente quando fraudes ou dessincronizações severas são flagradas.
- **Snapshot Interpolation (Dynamic Jitter Buffer)**: Mitigação elástica de flutuações de ping (Jitter) e Packet Loss, interpolando fluidamente os avatares remotos no passado e diluindo o erro residual de snaps através de algoritmos de *Error Blending*.
- **Delta Compression & ACKs**: O servidor quantiza a banda de rede enviando apenas as diferenças (P-Frames) a partir do último estado confirmado pelo cliente (via *Sequence ACKs*), enxugando os payloads para dimensões de 10-15 bytes.
- **Priority Accumulator & Hybrid Ticking (Tick Híbrido)**: Gestão cirúrgica de banda limitando pacotes ao teto do MTU (Maximum Transmission Unit). Entidades trafegam em regimes diferenciados (ex: Jogadores a 60Hz, Portas a 5Hz ou *On Change*) orquestradas pelo `QNNetProfile`.
- **DTLS, Segurança e Identificação Segura**: Conexões com mbedTLS (certificados gerados sob demanda e "fingerprint pinning"). Prevenção rígida contra roubo de identidade, teletransporte (*Hard Caps* e *Strikes*) e pacotes malformados.
- **Simulador Netem Nativamente Embutido**: O `QNWirePeer` permite injeção intencional de latência oscilante, duplicação e descarte caótico de pacotes para forçar a prova de carga da engine no desenvolvimento.

## 🔮 O Futuro (Fase 9: MMO e Física de Rede)

Com a arquitetura base de interpolação e predição estabilizada, o projeto engatilha a sua ascensão em direção às teses modernas (inspiradas por Glenn Fiedler / Gaffer on Games). Nossos próximos horizontes incluem:

1. **Lag Compensation (Server-Side Rewind / Hit Registration)**: Rebubinamento contínuo de estados no servidor (`QNWorldHistoryBuffer`) permitindo *raycasts* validados no passado, indispensável para atiradores competitivos.
2. **Networked Physics**: Integração profunda de sincronização de *Rigid Bodies*, com troca autoritativa de velocidade linear, angular, torques de inércia e repouso (sleeping states).
3. **Extrapolação e Dead Reckoning**: Previsão matemática de continuidades vetorizadas para garantir resiliência visual absoluta, mesmo quando uma conexão UDP perde pacotes sequencialmente.

*(Para o planejamento técnico de longo prazo, consulte o **[ROADMAP_MMO.md](./ROADMAP_MMO.md)**).*

## 📚 Documentação e Integração (Plug and Play)

O QuanticNet não impõe hierarquias nem classes base ao desenvolvedor de jogo. O uso dá-se pelo consumo de métodos via Autoload `QuanticNet` e observação de seus Sinais de Domínio.

1. **Demo Embardada (Bare Metal):**
   O plugin acompanha uma cena autossuficiente e mínima em `addons/quantic_net/demo/` projetada como prova de vida. Valida predição, conectividade e processamento sem acoplar complexidade de gameplay.
2. **Documentação Pública:**
   Para orientações estritas sobre como acionar os Casos de Uso, instanciar a rede, manipular limites de MTU e responder a *snapbacks*, devore a **[API_PUBLIC.md](./API_PUBLIC.md)**.
