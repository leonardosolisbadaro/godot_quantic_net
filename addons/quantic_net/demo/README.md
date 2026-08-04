# QuanticNet Demo: Playground & Guia de Integração

Esta pasta contém a demonstração interativa do QuanticNet, focada na integração de rede e despida de lógicas visuais complexas. O objetivo é atuar como um **Playground Técnico** para que o desenvolvedor possa testar os limites da arquitetura, observar o comportamento sob stress e entender como o motor de rede pode ser embutido em qualquer projeto via `Autoload` de forma puramente *Plug-and-play*.

## 🎯 A Filosofia da Demo

O `demo_main.gd` foi desenhado para expor de maneira transparente a força bruta do QuanticNet. Não usamos otimizações visuais pesadas da Engine (como `MultiMeshInstance3D` ou *RenderingServer* diretos) para forçar o GDScript a processar as atualizações matemáticas individualmente. Isso comprova que a estabilidade de latência e sincronismo do QuanticNet não afunda mesmo sob severa pressão de CPU.

### O Servidor (Host) Autoridade

1. Instancia um ambiente "Headless" silencioso que gera e orbita *Props* (Cubos vermelhos).
2. O servidor aplica **Hybrid Ticking** e **Bandwidth Management**. A cada ciclo físico (60Hz), o servidor verifica o `Tick Rate` assinalado de cada prop e a distância perante os jogadores (`Spatial Culling`).
3. Somente os objetos essenciais são selecionados para preencher o **MTU** daquele instante, sendo despachados como P-Frames (Deltas altamente comprimidos) para o cliente.

### O Cliente (Join) & Interpolação

1. Predição Local (`Client-Side Prediction`): Seu cubo verde obedece seus inputs instantaneamente. O resultado do seu movimento é emaranhado e despachado silenciosamente via `QuanticNet.submit_state(...)`.
2. Interpolação de Buffer Dinâmico (`Snapshot Interpolation`): O cliente lê o estado remoto do mundo varrendo o `QuanticNet.remote_state(id)`. Como pacotes podem se perder ou atrasar, a função interpola nativamente os estados em uma janela segura do passado (geralmente de 60ms a 250ms), resultando em movimento perfeitamente liso.

---

## 🎮 Controles, Atalhos e UI

A interface da Demo exibe, em tempo real, dois perfis críticos de medição:

- **System Profiler:** Taxa de Quadros (FPS: Média, Mínima e Máxima), Tempo de Física e Consumo de Memória.
- **Network Profiler:** RTT Verdadeiro (Ping), Packet Loss Real, Offset de Clock entre Servidor/Cliente e Contagem de Entidades Vivas.

### Atalhos Dinâmicos

A demo permite estressar a arquitetura ao vivo usando os atalhos:

- `SPACE` / `0` : Spawna 100 Props de uma vez / Remove todos os Props.
- `+` / `-` : Adiciona ou remove 10 Props.
- `*` / `/` : Multiplica por 2 ou divide pela metade a quantidade atual de Props.
- `N` : Ativa/Desativa o simulador de caos **Netem** (Injeta 10% de perda de pacote e 150ms de latência/jitter forçado para provar a estabilidade do Interpolador em redes ruins).
- `F` : Destrava/Trava o V-Sync.
- `1` a `5` : Alterna o "Net Profile" da sua própria entidade, definindo sua taxa de atualização na rede (de 60Hz a apenas 1Hz) para testemunhar o Bandwidth Accumulator trabalhando.

---

## 💻 Entendendo o Código (Como Usar o Plugin)

Abaixo estão trechos chaves que demonstram como é simples operar o protocolo QuanticNet em seu jogo. Toda a orquestração complexa roda por baixo dos panos na Clean Architecture.

### 1. Inicializando a Conexão

Basta chamar o Singletom global fornecendo as credenciais:

```gdscript
# No Servidor
var err = QuanticNet.host("127.0.0.1", 20432, "MINHA_SENHA", true) # true liga o Netem na porta

# No Cliente
var err = QuanticNet.join("127.0.0.1", 20432, "MINHA_SENHA", false)
```

### 2. Enviando o Estado do Jogador (Client -> Server)

Em seu `_physics_process` (ou script atrelado ao Input), você processa o movimento nativamente e então delega a nova posição:

```gdscript
# O cliente roda sua própria lógica (MoveAndSlide, RigidBody, etc)
# ...
if QuanticNet.get_state() == QuanticNet.ConnectionState.CONNECTED:
    # Empacota a posição confirmada localmente no Delta Serializer
    QuanticNet.submit_state(my_player.position, my_player.rotation, 0, delta)
```

### 3. Aplicando Estados Remotos (Server -> Client)

O jogo não se preocupa com perdas de pacotes. Ele apenas consome, durante o `_process` visual, o estado já resolvido e interpolado da rede.

```gdscript
func _process(delta: float) -> void:
    for id in get_todos_inimigos_conhecidos():
        var state = QuanticNet.remote_state(id)
        if not state.is_empty():
            # A posição e rotação já vêm matematicamente interpoladas para o frame visual atual!
            inimigo[id].position = state["pos"]
            inimigo[id].rotation = state["rot"]
```

### 4. Injetando Comandos Autoritários (Servidor)

Seu Servidor é o dono do mundo. Ele registra e define o perfil de Tick de qualquer NPC ou Prop interativo.

```gdscript
# Cria um NPC no motor
var prop_id = spawn_npc()
# Avisa o QuanticNet sobre a existência dessa entidade usando um NetProfile customizado
QuanticNet.register_entity(prop_id, false, true, profile_5hz)

# No physics_process do servidor, atualiza a autoridade dele
QuanticNet.get_server_registry()[prop_id].pos = Vector3(x, y, z)
```

## 🚀 Como Testar Localmente

A forma mais efetiva é abrir um **Terminal (PowerShell)** na raiz do seu projeto e executar nosso script de atalho para levantar as 3 instâncias simuladas:

```powershell
.\toggle_demo.ps1
```

*(O Script lançará 1 Servidor Headless, 1 Cliente Sadio e 1 Cliente Netem Simultaneamente. Rodar o script novamente encerrará todas as instâncias limpas).*
