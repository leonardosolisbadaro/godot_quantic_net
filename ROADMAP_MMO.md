# ROADMAP MMO & COMPETITIVO: A Visão de Destino do QuanticNet

Este documento decreta a visão arquitetural de longo prazo para a evolução do **QuanticNet**. O projeto transicionará de um plugin autoritativo simples para um **netcode híbrido (MMO + instâncias competitivas integradas)**.

> **Importante:** Este roadmap dita *o que* vamos construir no futuro, de forma que as *decisões de interface do presente* já acomodem essa realidade, sem custo prematuro de protocolo. O código deve permanecer simples hoje, mas estruturado para a complexidade de amanhã.

## Pilares Fundamentais

### 1. A Abstração Universal de Entidade

Para o motor de rede, todo ator dinâmico no mundo será traduzido em uma `NetworkEntity`:

```gdscript
NetworkEntity = {
 "id": int,
 "pos": Vector3,
 "rot": Vector3, # ou Quat, dependendo do quantizador
 "profile": int # Enum: MMO, COMPETITIVE, etc.
}
```

Jogadores, NPCs estáticos e NPCs móveis são indistinguíveis para o gerenciador de interesse e despache. A única diferença é a origem do input.

### 2. O Domínio do `NetProfile`

O `NetProfile` define a forma como o estado da entidade será processado e transmitido pela rede, sendo uma abstração estritamente técnica (agnóstica à regra de negócio do jogo). É uma classe de dados que dita o comportamento de tráfego:

- **`QNNetProfile.HIGH_FREQUENCY`:** Alta frequência de atualização (ex: 60 Hz) e alta prioridade. Utilizado para mecânicas competitivas ou predição intensa. O *Duelo* é concebido como a adoção temporária deste perfil, e não uma zona física restrita do mapa.
- **`QNNetProfile.LOW_FREQUENCY` (MMO Padrão):** Baixa frequência de atualização (ex: 10-15 Hz). Os clientes utilizam interpolação suave para exibir o movimento. Prioriza economia de banda e CPU.
- **`QNNetProfile.STATIC`:** Atualiza apenas quando sofre mutação (*On Change Only*).

### 3. Spatial Hashing (Area of Interest - AoI)

O despache não pode enviar os dados do mundo inteiro para todo mundo. Implementaremos um `QNSpatialGrid` para filtrar quem recebe atualizações de quem com base na distância e nas células vizinhas.

- **Fase 1 (GDScript Puro):** A lógica de Grid e Hashing deve nascer de forma purista na camada de Domínio, em GDScript e altamente testada via GUT (sem dependência da engine visual).
- **Fase 2 (C++ / GDExtension):** Uma migração para GDExtension **NUNCA** acontecerá até que ferramentas de *profiling* comprovem que o loop de spatial hashing do GDScript tornou-se o gargalo. Quando ocorrer, o contrato de interface da classe no Domínio permanecerá inalterado.

### 4. Dois Regimes de Tick e Despache

Como consequência do `NetProfile`, a sessão autoritativa do servidor orquestrará dois (ou mais) regimes de tick simultâneos.
Isso só será introduzido no servidor após um cenário de regime único ser devidamente homologado e testado em infraestrutura de rede real (internet/produção simulada).

### 5. Delta Compression & ACKs (Snapshot Compression)

O envio do estado do mundo consome a maior parte da banda do servidor. O servidor e o cliente devem trocar `ACKs` (confirmações de recebimento). Com isso, o servidor envia apenas a **diferença quantizada (Delta)** entre o estado atual da entidade e o último estado reconhecido pelo cliente. Entidades estáticas custarão próximo de `0 bytes`.

### 6. Jitter Buffer & Snapshot Interpolation

O movimento do próprio jogador (`Client-Side Prediction`) já está isolado, mas a renderização de todas as outras entidades (outros jogadores, NPCs) do perfil `MMO` deve fluir por um atraso intencional (`Jitter Buffer` no cliente, atualmente embrionário no `QNInterpBuffer`). Esse buffer armazena os *snapshots* do servidor e interpola suavemente no passado, blindando o jogador das perdas de pacotes do UDP.

### 7. Congestion Avoidance & Packet Fragmentation

- **Fragmentation:** Snapshots de áreas superpovoadas ultrapassarão o MTU (1400 bytes). Se a `ENet` se provar insuficiente ou gargalar no *overhead*, uma lógica de re-montagem de *Chunks* confiáveis sobre UDP (Fragmentação) será delegada ao Domínio.
- **Congestion Avoidance:** O servidor monitorará ativamente a perda de pacotes e o RTT (`QNLossTracker`) de cada conexão, estrangulando dinamicamente o tráfego enviado (reduzindo a taxa de atualização ou encolhendo a *Area of Interest*) quando a saúde da rota se deteriorar.

### 8. NetProfile e Tick Híbrido (Hybrid Ticking)

Para escalar o limite de entidades no servidor, o sistema não pode enviar tudo na mesma frequência. Entidades passarão a ter um `NetProfile` (`tick_rate_hz`, `base_priority`, etc). O despachante do servidor será escalonado por perfis, respeitando o ritmo exato de cada entidade (ex: 20Hz, 5Hz) independentemente se o jogo a considera um NPC, um Jogador ou uma Árvore.

### 9. Dynamic Jitter Buffer e Error Blending

Um buffer rígido de 120ms sucumbe a perdas drásticas (10% de packet loss / alto jitter). A evolução arquitetural exige um *Dynamic Jitter Buffer*, onde o tempo de retenção do passado (`RENDER_DELAY_MS`) incha e desincha em tempo real acompanhando a variância do ping do cliente. Além disso, o fim de uma extrapolação utilizará *Error Blending* (decaimento exponencial) para mesclar a posição sem sobressaltos.

### 10. Lag Compensation (Server-Side Rewind / Hit Registration)

Para combates competitivos ou MMOs de ação (hitscan, projéteis), o servidor deve manter um histórico rigoroso de *hitboxes* de todas as entidades. Ao processar um tiro do cliente, o servidor rebobina o mundo para o momento exato em que o cliente efetuou o disparo, realiza o teste de colisão e, em seguida, avança o estado de volta ao presente.

### 11. Extrapolação e Dead Reckoning (Sobrevivência à Latência)

Quando pacotes são perdidos consecutivamente e o *Jitter Buffer* do cliente esvazia (falta de *snapshots* futuros), em vez de congelar a entidade, o motor de rede calcula o vetor de velocidade instantânea e *extrapola* (prevê) a continuidade do movimento. Isso mantém a ilusão de fluidez até que a conexão se recupere.

### 12. Gerenciamento Avançado de Banda (Priority Accumulator)

O `QNSpatialGrid` resolve quem está próximo, mas o limite físico da rede (MTU ~1400 bytes) impõe contenções rigorosas. Utilizaremos um *Priority Accumulator*: entidades ganham pontuação de prioridade com base na distância, no alvo do jogador e no `NetProfile`. Se uma entidade não couber no pacote atual, ela não é enviada, mas acumula "débito" de prioridade até que seja obrigatoriamente incluída no próximo pacote disponível.

### 13. Networked Physics (Sincronização de Corpos Rígidos)

A evolução do `NetProfile` englobará estados físicos puros (Rigid Bodies). Além de cinemática básica (posição e rotação), a rede sincronizará vetores de Força (Velocidade Linear e Angular) e detecção otimizada de repouso (`Sleep/Awake`) para economizar largura de banda na simulação de ambientes com alta interação física.

### 14. Automação e Infraestrutura como Processo (Day 1)

Scripts para levantar cenários de teste rapidamente serão nativos do ecossistema:

- `run_local_test.sh`: Script para iniciar 1 servidor headless e 2 clientes, isolando logs e gerenciando portas localmente.
- **Export Presets de Segurança**: A garantia desde o dia 1 de que um export "Client" **jamais** irá embutir credenciais como `certs/server.key`.

---

## O Ciclo de Vida Pós-1.0 (Expansão MMO)

Quando o milestone 1.0 do plugin for atingido (Auth, Snapshot, Replay Local, DTLS, Netem, Demo), o roadmap MMO ditará que cada um dos pilares acima ganhe vida seguindo o rigor arquitetural e do TDD:

1. **Domínio `QNSpatialGrid`:** Estruturas de dados em GDScript puro cobrindo query de vizinhos.
2. **AoI como Política de Despacho:** Modificação da `QNHostSession` para calcular `snapshot` diferencial por par peer-to-peer.
3. **NetProfile e Tick Híbrido:** Orquestrar relógios secundários (60Hz para peers cujo perfil seja `COMPETITIVE`).
4. **Profiling:** Obtenção de métricas de estresse real na rede (ex: centenas de CCUs). Se gargalar, reescrita isolada em GDExtension C++ para o Grid.
5. **Catálogo de Demos (`quantic-net-demos`):** Evoluir o "espaço de possibilidades" em um repositório separado consumindo o addon, demonstrando implementações ricas com múltiplos avatares, integração de UI (HUD), e simulação híbrida (predição vs interpolação) via NetProfile e AoI.
