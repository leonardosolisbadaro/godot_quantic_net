# QuanticNet Demo: Bare Metal Playground

Esta pasta contém a demonstração definitiva do **QuanticNet**.
Mais do que uma prova de conceito, esta Demo é um **Ambiente Educacional de Clean Architecture** para jogos Multiplayer na Godot 4.7. Ela foi projetada do zero ("Bare Metal") para demonstrar como orquestrar instâncias, predição, culling de rede e interpolação, **sem poluir a lógica com acoplamentos visuais**. 

Se você quer aprender como estruturar o netcode de um verdadeiro jogo competitivo ou MMO de mundo aberto, estude a `demo_main.gd`.

## 🎯 A Filosofia da Demo (Zero Acoplamento)

Diferente dos tutoriais tradicionais da Godot que atrelam RPCs diretamente a nós visuais (`@rpc`), o QuanticNet separa estritamente os Dados (State) da Apresentação (View).

* **A Física Roda Separada:** Toda a submissão de estado do Cliente local para a rede roda isolada no `_physics_process`.
* **O Visual Apenas Observa:** Toda a atualização dos avatares inimigos na sua tela roda de forma puramente *Event-Driven* e *Assíncrona* no `_process`, lendo os estados interpolados da rede, livres de stutterings e travamentos da física.

---

## 💻 Entendendo o Código: Exemplos Reais

Os trechos abaixo foram extraídos diretamente da nossa `demo_main.gd`.

### 1. Inicialização Híbrida e Isolada (Setup)

Ao rodar a cena, nós identificamos se somos o Servidor ou um Cliente, conectamos os **Sinais Puros** do QuanticNet e injetamos o roteador nativo em C++ no SceneTree:

```gdscript
func _ready() -> void:
    # 1. Definimos o Perfil de Rede (Ex: Jogadores = 60Hz, Props = 20Hz)
    _entity_profile_player = QuanticNet.get_preset_profile(QuanticNet.EntityProfileType.HIGH_FREQUENCY)
    
    # 2. Conectamos aos sinais agnósticos do QuanticNet (Sem _process polling)
    QuanticNet.connection_state_changed.connect(_on_connection_state_changed)
    QuanticNet.peer_joined.connect(_on_peer_joined)
    QuanticNet.peer_left.connect(_on_peer_left)
    QuanticNet.snapback_received.connect(_on_snapback)
    QuanticNet.pong_received.connect(_on_pong)
    
    # 3. Disparamos a conexão
    var err = QuanticNet.join(DEFAULT_IP, DEFAULT_PORT, SECRET, _netem_active)
    
    # 4. Injeta a implementação nativa C++ na SceneTree, habilitando roteamento veloz
    get_tree().set_multiplayer(QuanticNet.get_tree().get_multiplayer(QuanticNet.get_path()), self.get_path())
```

### 2. Client-Side Prediction e Envio (Zero Input Lag)

No cliente local, não esperamos permissão do servidor para andar. Nós processamos os *inputs*, movemos nosso avatar na tela (`_client_predicted_position`) e informamos à rede a nossa intenção empacotada no `submit_state`. Isso ocorre no `_physics_process`:

```gdscript
func _physics_process(delta: float) -> void:
    if QuanticNet.is_server() or QuanticNet.get_state() != QuanticNet.ConnectionState.CONNECTED:
        return
        
    var input_dir := Vector3.ZERO
    input_dir.x = Input.get_axis("ui_left", "ui_right")
    input_dir.z = Input.get_axis("ui_up", "ui_down")
        
    # Client-Side Prediction: Movimenta instantaneamente o avatar local na malha visual.
    _client_predicted_position += input_dir.normalized() * speed * delta
    _update_visual(QuanticNet.get_unique_id(), _client_predicted_position, true)
    
    var custom_input = 0
    if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
        custom_input = 1 # Dispara Hitscan sem usar RPC pesados!
        
    # Envia a predição otimista de forma cravada para a Engine C++ assinar e rotear
    QuanticNet.submit_state(_client_predicted_position, Vector3.ZERO, custom_input, delta)
```

### 3. Interpolação de Buffer Dinâmico (Renderização de Inimigos)

O servidor envia as coordenadas dos outros jogadores compactadas em *P-Frames* assíncronos. Se nós tentássemos desenhá-los ao recebê-los, eles "gaguejariam" na tela (Jitter).
A solução? O QuanticNet *bufferiza* e interpola no passado C++. Nós só precisamos ler e renderizar (no `_process` destravado):

```gdscript
func _process(_delta: float) -> void:
    # Roda livre no V-Sync. Lógica de Snapshot Interpolation puramente visual.
    if not QuanticNet.is_server() and QuanticNet.get_state() == QuanticNet.ConnectionState.CONNECTED:
        
        for id in _active_visual_entities_map.keys():
            if id != QuanticNet.get_unique_id(): # Pula nós mesmos (que usamos predição local)
                
                # Consome o estado matematicamente interpolado da DLL em C++
                var interp_state = QuanticNet.get_remote_state(id)
                
                if not interp_state.is_empty():
                    var visual = _active_visual_entities_map[id]
                    var target_pos = interp_state.get("pos", visual.position)
                    
                    # Movimenta o inimigo suavemente com Lerp Visual adicional
                    visual.position = visual.position.lerp(target_pos, LERP_SPEED)
```

### 4. Reconciliação (Server Snapback)

Se a predição do cliente bater de frente com a realidade do servidor (Ex: um teletransporte não autorizado, ou uma correção por latência), o Servidor emite o `snapback`. Nós escutamos o sinal e aplicamos o choque de realidade no `_client_predicted_position`:

```gdscript
func _on_snapback(seq: int, pos: Vector3, rot: Vector3, reason: int, replay_inputs: Array) -> void:
    # Host discordou severamente da nossa simulação.
    _client_predicted_position = pos
    
    # Se fôssemos um MMO completo, aqui nós re-aplicaríamos o replay_inputs em loop 
    # simulando os passos novamente a partir deste novo ponto âncora, mascarando a correção!
    _update_visual(QuanticNet.get_unique_id(), _client_predicted_position, true)
```

---

## 🎮 Como Testar na Prática

Você não precisa rodar builds pesadas. O projeto possui um script inteligente para PowerShell que orquestra tudo simultaneamente para você.

Na raiz do projeto (`godot_quantic_net/`), abra o seu terminal e execute:

```powershell
powershell.exe -ExecutionPolicy Bypass -File toggle_demo.ps1
```

*(Isto lançará 1 Servidor em modo Headless e 2 Clientes automaticamente.*
*(Rode o script novamente para finalizar com higiene os processos).*
