# QuanticNet Demo: Bare Metal

Esta pasta contém a demonstração técnica minimalista do QuanticNet, focada na integração de rede e despida de lógicas visuais complexas. O objetivo é atuar como um **Teste de Vida (Smoke Test)** e provar que o motor de rede pode ser embutido em qualquer projeto via `Autoload` de forma puramente *Plug-and-play*.

## 🎯 O Que Acontece na Demo?

Quando a cena é instanciada (seja em modo *Servidor* ou *Cliente*), o script `demo_main.gd` atua como o consumidor da API do plugin.

### O Servidor (Host) Autoridade

1. Registra a porta e emite chaves criptográficas (mbedTLS).
2. Spawna *Props* (Cubos Vermelhos). Estes cubos rodam puramente matemática algorítmica para flutuarem num padrão circular (representando NPCs).
3. Ao mover os props fisicamente em sua lógica (`_physics_process`), ele empurra esses vetores para o *Broadcast* do QuanticNet.
4. O servidor orquestra **Hybrid Ticking** limitando o *Tick Rate* e limitando pacotes no tamanho de *MTU* (Minimum Transmission Unit) sob a governança do domínio `PriorityAccumulator`.

### Os Clientes (Join) & Client-Side Prediction

1. Instanciam seu próprio avatar instantaneamente (Cubo Verde). O input direcional (ou *auto-move*) move este cubo na exata fração de milissegundo de apertar do teclado (Predição Local Absoluta).
2. O resultado (Nova Posição, Rotação e Delta Time) é empacotado silenciosamente (`QuanticNet.submit_state`) e despachado ao servidor junto com o histórico recente.
3. Paralelamente, o **Snapshot Interpolation** captura os pacotes que chegam contendo os *Props* e *Outros Clientes* (Cubos Ciano), retendo-os no **Dynamic Jitter Buffer**.
4. Ao invés da tela sofrer saltos caóticos quando há latência oscilante, o `_process` consome a função `QuanticNet.remote_state`, mesclando pacificamente as localizações no passado remoto garantindo movimento 100% liso.

## 🛜 Simulando o Caos (Netem)

Você pode pressionar `N` para ativar o injetor de distúrbios de conexão e comprovar a resiliência do QuanticNet em rodar em infraestrutura defasada. Quando injetado `10% Packet Loss` e `50ms de Jitter`:

* Sem interpolação, os NPCs travam agressivamente a todo instante e deslizam.
* Com a nossa camada ligada, os NPCs flutuam suavemente.
* Em situações insustentáveis de falha TCP, o QuanticNet aciona o *Visual Culling* nativo (escondendo quem a rede esqueceu de avisar a localização).

## 🚀 Como Testar Localmente

A forma mais efetiva é abrir **três terminais** independentes apontando para a raiz do seu projeto. O uso de *headless* no servidor poupa recursos da GPU.

1. Levante o Servidor:

   ```bash
   godot --headless --path . -s addons/quantic_net/demo/demo_main.gd --server
   ```

2. Conecte um Cliente puro:

   ```bash
   godot --path . -s addons/quantic_net/demo/demo_main.gd --client
   ```

3. Conecte um Cliente sofrendo instabilidade e observe a resiliência visual frente ao cliente sadio:

   ```bash
   godot --path . -s addons/quantic_net/demo/demo_main.gd --client --netem
   ```
