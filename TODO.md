# TODO

Plugin de network (`QuanticNet`) `plug and play`, focado no desenvolvimento de jogos `3D Open World MMO` usando a `Godot Engine 4.7`. Arquitetada absoluta (a partir do zero) focada em **Code-First**, **Test-Driven Development (TDD)** e **Clean Architecture**. Eliminando a dependência de editores visuais para lógicas de negócio.

---

## FUNDAÇÃO: CONSTRUÇÃO DO BOILERPLATE

### Fase 1: Arquitetura

Configuração do ecossistema, IDE e amarras do Code-First, TDD e Clean Architecture.

- [x] Editar `GEMINI.md` definindo as regras arquiteturais, uso de GDScript docstrings e metodologia AAA.
- [x] Instalar e configurar ambiente de testes (bitwes/Gut).

### Fase 2: Core Domain (TDD Rigoroso)

O coração da simulação e validação, agnóstico à infraestrutura de rede.

- [x] Criar a "casca" do plugin Godot (`plugin.cfg` e script `@tool` herdando de `EditorPlugin`).
- [x] Configurar inicialização do plugin (registro de singleton) utilizando as assinaturas exatas da Godot Engine 4.7 (`_enable_plugin` e `_disable_plugin`).
- [x] Injetar o Autoload principal (`quantic_net_autoload.gd`) como fachada (Single-Point of Entry) baseada em sinais para orquestrar e delegar chamadas da Engine.
- [x] Estruturar a árvore de diretórios enraizada nos padrões de Clean Architecture (`domain/`, `use_cases/`, `adapters/`, `infrastructure/`).
- [x] TDD: Implementar `QNSerializer` (quantização binária de 19 Bytes para estado/snapback).
- [x] TDD: Implementar `QNClockSync` (cálculo de RTT e sincronização de tempo do servidor).
- [x] TDD: Implementar `QNLossTracker` (monitoramento de perda de pacotes via tracking de sequência).
- [x] TDD: Implementar `QNInterpBuffer` (armazenamento circular e amostragem no passado remoto).
- [x] TDD: Implementar `QNServerValidator` (clamping, validação anti-teleporte e rejeição baseada no tempo).
- [x] TDD: Implementar `QNInputBuffer` (armazenamento e replay local de inputs - base do client prediction).

### Fase 3: Camada de Infraestrutura e Transporte

#### Limpeza de Testes (Higiene) [x]

- [x] TDD: Adicionar teardown (`after_each`) nas suítes de `infrastructure` para liberar recursos alocados (ex: `_hook.free()`) e eliminar warnings de ObjectDB leak no GUT.
- [x] Commit sugerido: `chore(tests): free Extension instances in GUT teardown`

#### PR 2 — Wire peer, codec e Netem

Implementar `QNWirePeer` em `addons/quantic_net/src/infrastructure/`, herdando
de `MultiplayerPeerExtension` e encapsulando uma `ENetConnection`.

- [x] TDD: Criar `tests/unit/infrastructure/test_qn_wire_peer_netem.gd`.
- [x] TDD: Especificar e testar perfil de perda por canal virtual:
  canal 0 (controle/reliable) sem drop por padrão; canal 1
  (estado/unreliable) com drop configurável.
- [x] TDD: Especificar e testar retenção por latência base, liberação
  após o prazo e jitter gaussiano.
- [x] TDD: Especificar e testar que jitter pode produzir reordenação
  temporal controlada.
- [x] TDD: Especificar e testar duplicação opcional de datagramas.
- [x] TDD: Implementar `QNWirePeer` até a suíte de Netem ficar verde.
- [x] TDD: Criar `tests/unit/infrastructure/test_qn_wire_peer_codec.gd`.
- [x] TDD: Implementar header de wire versionado:
  `magic | version | virtual_channel | flags | payload`.
- [x] TDD: Implementar mapeamento de canais virtuais para ENet:
  controle → ENet 0, estado → ENet 3, reliable ordenado → ENet 1.
- [x] TDD: Implementar codec do payload: compressão ZSTD/DEFLATE condicional,
  obfuscação XOR e decode inverso.
- [x] TDD: Testar round-trip do codec, pacote malformado, versão/magic
  inválidos e payload comprimido/não comprimido.
- [x] TDD: Cobrir wrappers obrigatórios de `MultiplayerPeerExtension`:
  status, id único, peer remoto, channel, transfer mode, target peer,
  close e disconnect.
- [x] Verificar compilação no Godot 4.7.1, incluindo
  `ENetConnection.MODE_HOST` e tipagem explícita onde o parser exigir.
- [x] Commit sugerido:
  `feat(infrastructure): add QNWirePeer codec, channel mapping and netem`

#### PR 3 — Hook da Multiplayer API [x]

Implementar `QNNetHook` em `addons/quantic_net/src/infrastructure/`, herdando
de `MultiplayerAPIExtension` e encapsulando `SceneMultiplayer`.

- [x] TDD: Criar `tests/unit/infrastructure/test_qn_net_hook.gd`.
- [x] TDD: Especificar reemissão dos sinais de conexão, autenticação,
  entrada e saída de peers.
- [x] TDD: Especificar interceptação de RPCs de saída por `Callable`,
  permitindo observação, alteração ou cancelamento.
- [x] TDD: Especificar interceptação de pacotes customizados de entrada
  e saída, preservando peer de origem e canal virtual.
- [x] TDD: Especificar delegação de object configuration add/remove
  para o `SceneMultiplayer` interno.
- [x] TDD: Implementar `QNNetHook` até todos os testes ficarem verdes.
- [x] TDD: Cobrir o envio de pacote customizado com target peer,
  transfer channel e transfer mode corretos.
- [x] Testar que sinais do `SceneMultiplayer` são reemitidos sem
  depender de identificadores de sinais herdados no `_init()`.
- [x] Commit sugerido:
  `feat(infrastructure): add QNNetHook multiplayer interception`

### Fase 4: Casos de Uso de Sessão (TDD)

Orquestração independente de cena e gameplay. Os casos de uso conhecem
o domínio e contratos de transporte; não instanciam cubos, não leem input
da Godot e não controlam UI.

#### PR 4 — Sessão autoritativa do servidor [x]

Implementar `QNHostSession` em `addons/quantic_net/src/use_cases/`.

- [x] TDD: Criar `tests/unit/use_cases/test_qn_host_session.gd` com
  transporte fake/memory transport.
- [x] TDD: Especificar fluxo de autenticação por token/secret e
  rejeição de credencial inválida.
- [x] TDD: Especificar recebimento de `TYPE_STATE`, decode via
  `QNSerializer` e validação por `QNServerValidator`.
- [x] TDD: Especificar as três saídas autoritativas:
  `accept` → relay do estado; `clamp` → relay + snapback reliable;
  `reject` → snapback reliable sem relay.
- [x] TDD: Especificar kick após `MAX_STRIKES` e limpeza por peer leave.
- [x] TDD: Expor eventos de domínio, incluindo a propagação de
  `peer_rejected(id, reason, strikes)`, sem `print()` interno.
- [x] Implementar o caso de uso até a suíte verde.
- [x] Commit sugerido:
  `feat(use-cases): add authoritative host session`

#### PR 5 — Sessão preditiva do cliente [x]

Implementar `QNClientSession` em `addons/quantic_net/src/use_cases/`.

- [x] TDD: Criar `tests/unit/use_cases/test_qn_client_session.gd` com
  relógio e transporte fake determinísticos.
- [x] TDD: Especificar rate limit de envio de estado a 20 Hz.
- [x] TDD: Especificar criação de `seq`, serialização e armazenamento
  do `sent_ts` no `QNInputBuffer`.
- [x] TDD: Especificar eco autoritativo: lookup de `sent_ts` por seq,
  chamada `QNClockSync.on_pong(client_sent, server_time, client_now)` e
  confirmação/drain de inputs.
- [x] TDD: Especificar recebimento de peer remoto, atualização de
  `QNLossTracker` e alimentação de `QNInterpBuffer`.
- [x] TDD: Especificar `TYPE_SNAPBACK`: estado autoritativo, seq
  confirmado, reason e lista de inputs para replay.
- [x] Implementar o caso de uso até a suíte verde.
- [x] Commit sugerido:
  `feat(use-cases): add predictive client session`

### Fase 5: Infraestrutura DTLS e Fachada (Integração)

A camada de infraestrutura monta a Engine, certificados e adaptadores.
O autoload permanece uma casca fina: não conhece mecânicas, nodes de
jogo, input, mesh, câmera ou UI.

#### PR 6 — Bootstrap DTLS [x]

Implementar `QNDTLSBootstrap` em
`addons/quantic_net/src/infrastructure/`.

- [x] TDD/integração: Criar teste headless para servidor e cliente
  locais com DTLS real.
- [x] Implementar host com
  `dtls_server_setup(TLSOptions.server(key, cert))`.
- [x] Implementar join com
  `dtls_client_setup(hostname, TLSOptions.client(cert))`.
- [x] Implementar fallback de desenvolvimento em `user://`:
  gerar/reutilizar `qnet_cert.crt` e `qnet_cert.key`.
- [x] Definir contrato de produção:
  certificado público em `res://certs/server.crt`; chave privada apenas
  no preset/export do servidor; hostname configurável e pinning.
- [x] Propagar erros de bind, carregamento de cert e conexão via
  `Error`/sinais, nunca apenas `push_error`.
- [x] Commit sugerido:
  `feat(infrastructure): add DTLS host and client bootstrap`

#### PR 7 — Autoload plug-and-play [x]

Completar `quantic_net_autoload.gd` como única API pública do addon.

- [x] TDD/integração: Criar `tests/integration/test_quantic_net_api.gd`.
- [x] Implementar `host()` e `join()` retornando `Error`.
- [x] Implementar `submit_state()`, `remote_state()`, `loss_of()`,
  `kick()` e `toggle_netem()` delegando às sessões.
- [x] Manter/expor sinais públicos:
  `peer_joined`, `peer_left`, `state_received`, `pong_received` e
  `snapback_received`.
- [x] Definir contrato final de `snapback_received`: seq confirmado,
  posição, rotação, reason e inputs pendentes para replay; a aplicação
  decide como reaplicar sua própria mecânica.
- [x] Garantir que o addon não tenha referência a Node3D, cubos,
  Input, meshes, câmera ou regras de gameplay.
- [x] Commit sugerido:
  `feat(api): complete plug-and-play QuanticNet autoload`

### Fase 6: Aceitação, Demo e Distribuição

Evidência executável de que o addon instala uma vez, funciona em projeto
3D vazio e pode ser consumido sem acoplamento à demo.

#### PR 8 — Teste de integração de rede real [ ]

- [ ] Migrar o teste do rascunho para
  `tests/integration/test_server_two_clients.gd`.
- [ ] Subir um servidor e dois clientes DTLS reais na mesma árvore
  headless, sob Netem (latência, jitter e perda configurada).
- [ ] Validar: dois peers autenticados, clock sincronizado, RTT em
  faixa esperada, relay de estado remoto, perda medida e convergência
  do estado no servidor.
- [ ] Fazer o processo encerrar com exit code 0/1 para CI.
- [ ] Commit sugerido:
  `test(integration): cover DTLS server and two clients under netem`

#### PR 9 — Demo agnóstica de gameplay [ ]

- [ ] Criar demo 3D isolada em `demo/`, fora de `addons/`.
- [ ] Demonstrar apenas integração consumidora:
  prediction local, `submit_state`, `remote_state`, visualização de
  peers e aplicação de snapback.
- [ ] Incluir instruções code-first: projeto vazio, cópia da pasta
  `addons/`, ativação do plugin e execução servidor/cliente.
- [ ] Manter valores didáticos (porta, secret e assets) somente na
  demo, nunca no núcleo do addon.
- [ ] Commit sugerido:
  `docs(demo): add minimal 3D plug-and-play example`

#### PR 10 — CI, release e Asset Library [ ]

- [ ] Criar workflow GitHub Actions para executar GUT e testes de
  integração headless em todo push e pull request.
- [ ] Adicionar badge de CI ao README.
- [ ] Criar `CHANGELOG.md` no padrão Keep a Changelog e política
  SemVer.
- [ ] Adicionar `LICENSE`, ícone, screenshots/GIF da demo e README de
  instalação/API voltado à Godot Asset Library.
- [ ] Definir `.gitattributes`/artefato de release para distribuir
  somente `addons/quantic_net/`; excluir `tests/`, `demo/`, `.github/`
  e ferramentas internas do pacote ao usuário.
- [ ] Documentar filtros de export para cliente e servidor:
  cliente exclui chave privada, testes e demo; servidor inclui a chave
  privada e pode excluir assets pesados.
- [ ] Publicar release `v0.1.0` e submeter à Godot Asset Library.
- [ ] Commit sugerido:
  `ci(release): automate tests and package addon for distribution`
