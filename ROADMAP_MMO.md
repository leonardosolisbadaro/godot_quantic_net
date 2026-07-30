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

O `NetProfile` define a forma como o estado da entidade será processado e transmitido pela rede:

- **`MMO` (Padrão):** Baixa frequência de atualização (ex: 10-15 Hz). Os clientes utilizam interpolação suave para exibir o movimento. Prioriza economia de banda e CPU.
- **`COMPETITIVE`:** Alta frequência de atualização (ex: 60 Hz). Utiliza predição do cliente pesada e correção imediata (Snapback). Ativado durante momentos críticos, como um combate.
O *Duelo* é concebido como um **estado mútuo** temporário entre entidades específicas, e não uma zona física restrita do mapa.

### 3. Spatial Hashing (Area of Interest - AoI)

O despache não pode enviar os dados do mundo inteiro para todo mundo. Implementaremos um `QNSpatialGrid` para filtrar quem recebe atualizações de quem com base na distância e nas células vizinhas.

- **Fase 1 (GDScript Puro):** A lógica de Grid e Hashing deve nascer de forma purista na camada de Domínio, em GDScript e altamente testada via GUT (sem dependência da engine visual).
- **Fase 2 (C++ / GDExtension):** Uma migração para GDExtension **NUNCA** acontecerá até que ferramentas de *profiling* comprovem que o loop de spatial hashing do GDScript tornou-se o gargalo. Quando ocorrer, o contrato de interface da classe no Domínio permanecerá inalterado.

### 4. Dois Regimes de Tick e Despache

Como consequência do `NetProfile`, a sessão autoritativa do servidor orquestrará dois (ou mais) regimes de tick simultâneos.
Isso só será introduzido no servidor após um cenário de regime único ser devidamente homologado e testado em infraestrutura de rede real (internet/produção simulada).

### 5. Automação e Infraestrutura como Processo (Day 1)

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
5. **Demo MMO Rica:** Evoluir a demo inicial de 2 cubos para múltiplos avatares simulando movimentação mista (predição vs interpolação).
