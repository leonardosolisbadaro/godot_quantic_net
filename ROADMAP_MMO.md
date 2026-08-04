# ROADMAP MMO & COMPETITIVO: O Destino do QuanticNet

Este documento decreta a visão arquitetural de longo prazo para a evolução do **QuanticNet**. Estando com a fundação arquitetural cimentada sob a versão `0.4.0` (Client-Side Prediction seguro, DTLS e Memória controlada sem ObjectDB Leaks), o projeto engatilha oficialmente a **Fase 9**, que transicionará a engine para um **netcode híbrido (MMO + instâncias competitivas integradas)**.

> **Regra de Ouro:** Este roadmap dita *o que* vamos construir, de forma que as *decisões de interface do presente* jamais criem amarras ou custos prematuros. O código permanecerá brutalmente simples, mas moldado para a expansão matemática severa que o futuro exige.

## Pilares Fundamentais (Concluídos e Blindados) ✅

A arquitetura já acomoda com robustez de C++ e segurança de GDScript os seguintes pilares:

### 1. Delta Compression & ACKs (Snapshot Compression) ✅

O servidor deixou de espelhar o mundo inteiro a cada tick. Através de *Sequence ACKs*, o tráfego foi reduzido a Deltas quantizados.

### 2. Jitter Buffer & Snapshot Interpolation ✅

A barreira de flutuação (*jitter*) do UDP está domesticada localmente por um *Dynamic Jitter Buffer* autônomo. O tempo de retenção respira e desincha orgulhosamente, adaptando-se às intempéries latentes reportadas pelo Netem.

### 3. NetProfile e Tick Híbrido (Hybrid Ticking) ✅

O despachante não trabalha em regime estático. Todo tráfego respeita uma matriz de escalonamento regida por perfis isolados (60Hz competitivo, 20Hz padrão, 5Hz periférico, *On Change* estático).

### 4. Priority Accumulator & Congestion Avoidance ✅

O limite físico da rede (MTU UDP overhead ~1400 bytes) é respeitado. Entidades recebem pontuações de prioridade baseada em culling espacial e *debito acumulado*, priorizando o despache de forma justa e otimizada (Sem estouros de pacote!).

---

## O Futuro: A Engenharia de Fronteira (Fase 9+) 🚀

### 1. Spatial Hashing (Area of Interest - AoI)

O despache será filtrado por um `QNSpatialGrid`. Ninguém receberá dados irrelevantes que cruzam continentes, economizando banda extrema.

* **Tática Arquitetural:** O algoritmo nascerá estritamente em GDScript no *Core Domain*, garantido por TDD cego sem nós visuais. Uma migração GDExtension (C++) só será permitida quando evidências sólidas de profiling acusarem gargalo intratável do interpretador do Godot 4.7.

### 2. Lag Compensation (Server-Side Rewind / Hit Registration)

Para viabilizar arenas competitivas e *hitscan* milimétrico.
O servidor ganhará um `QNWorldHistoryBuffer` armazenando os históricos rigorosos dos volumes 3D no passado (aprox. 1 a 2 segundos). Ao acionar o gatilho, a infraestrutura servidor rebobinará o mundo autoritativo retroagindo o *ping* do atirador, calculando a colisão perfeita e avançando para o tempo real num único frame, ignorando a relatividade da Internet.

### 3. Networked Physics (RigidBody Sync)

As entidades de física pura abandonarão o envio cinemático primitivo.
A API de domínio passará a quantizar *Linear Velocity*, *Angular Velocity*, vetores de empuxo, torques de inércia e estados binários críticos de repouso (Sleeping states) para economizar processamento do Host. O perfil será expandido para a categoria dedicada `NetProfile.RIGID_BODY`.

### 4. Dead Reckoning Agressivo (Sobrevivência de Extrapolação)

Quando a nuvem de tempestade chegar e o jogador perder pacotes numa severidade onde o Jitter Buffer estoure ou resseque por completo: as entidades não congelarão.
Um cálculo matemático de continuidade de vetores preditivos manterá os alvos inimigos operando numa sobrevida ilusória calculada, minimizando engasgos grotescos e disfarçando cortes massivos de TCP/UDP.

### 5. Escalabilidade Maciça: Testes Estressados

As suítes do GUT darão luz a cenários severos: 100 props, 50 avatares disparando simulações híbridas concorrentes sob limites apertados de *MTU* para homologar a performance bruta e aferição algorítmica de estrangulamento de banda.

---

O fim dessa rota consolida o motor QuanticNet como uma alternativa irrefutável e determinística às ferramentas visuais nativas de *High-level Multiplayer*, devolvendo a soberania do Netcode à arquitetura e ao TDD.
