# GEMINI.md - A Constituição Arquitetural

## Preâmbulo

Este documento é a **constituição absoluta e soberana** deste projeto. As regras, diretrizes, padrões e fluxos aqui descritos orientam de forma estrita o comportamento da Inteligência Artificial (IA) e de qualquer desenvolvedor humano que interaja com esta base de código.

O objetivo deste documento é **garantir a evolução controlada, limpa, testável e segura** do ecossistema, servindo como a única fonte da verdade para decisões arquiteturais. A IA está terminantemente proibida de afrouxar estas regras sob qualquer pretexto.

## 1. O PROTOCOLO GEMINI (Fluxo de Trabalho Obrigatório)

Para garantir que não haja alterações destrutivas, aumento de acoplamento ou erosão arquitetural sem supervisão rigorosa, a IA deve operar **estritamente** no seguinte ciclo de 3 passos:

1. **Passo 1: Análise e Plano de Ação:** Ao receber uma demanda, a IA deve mapear o contexto completo do projeto (`TODO.md`, dependências afetadas). A IA deve responder **apenas** com um Plano de Ação detalhado, explicitando claramente quais camadas serão afetadas e quais ficheiros serão criados/modificados.
2. **Passo 2: Refinamento:** Se houver qualquer ambiguidade (técnica ou de regras de negócio), a IA é obrigada a fazer questionamentos pontuais antes de gerar qualquer código.
3. **Passo 3: Execução Bloqueada:** A IA gerará o código final **APENAS** após o utilizador responder explicitamente com "Aprovado" ou "Pode avançar" ao Plano de Ação.

## 2. RESTRIÇÕES FUNDAMENTAIS E LIMITES INTRANSPONÍVEIS

A IA está **terminantemente proibida** de:

- **Inventar Histórico:** Deduzir hashes Git, criar versões não liberadas ou gerar changelogs fictícios. Tudo deve ser baseado estritamente na realidade atual do repositório.
- **Acoplamento Visual (UI-Bound Logic):** Injetar lógica de domínio ou regras de negócio diretamente em scripts anexados a nós visuais (`.tscn`). A camada de apresentação deve focar estritamente em manipular a árvore de cena (SceneTree).
- **Dependências Globais Ocultas:** Utilizar `AutoLoads` (Singletons) do Godot para compartilhar estado ou injetar dependências. Toda injeção deve ser explícita via construtor ou métodos dedicados (`inject_dependency()`).
- **Uso Indiscriminado de `class_name`:** O uso global de classes polui o namespace e corrompe o cache. Utilize `preload` com caminhos absolutos (`res://`) para carregar dependências.
- **Alucinação de APIs da Engine:** Empregar funções ou abordagens sem certeza absoluta. A IA deve ler a documentação nativa do Godot alocada em `GodotEngine_extracted/GodotEngine_INDEX.md` via leitura direta de arquivos para consultar referências de uso correto da sintaxe da versão mais atual da engine.

## 3. ARQUITETURA E LIMITES DE CAMADAS (Clean Architecture)

A aplicação segue uma Clean Architecture adaptada ao ecossistema do Godot Engine. A regra da dependência é **unidirecional e de cima para baixo**. Nenhuma camada inferior pode conhecer algo de uma camada superior.

### 3.1. A Topologia (Ordem de Dependência)

Para suportar o rigor de um ecossistema "plug and play" de um jogo **3D Open World MMO** (onde autoridade de servidor, predição de cliente e gerenciamento de estado são críticos), a arquitetura do `QuanticNet` divide-se nas seguintes camadas concêntricas (de dentro para fora):

1. **Core Domain (`src/domain/`):** O coração imutável da rede. Contém as regras de negócio puras (ex: `PlayerSession`, `PacketSerializer`, `StateInterpolator`). Totalmente agnóstico à Engine. Somente tipos estáticos primitivos devem transitar aqui.
2. **Use Cases (`src/use_cases/`):** Orquestram o fluxo de dados entre entidades e repositórios. (ex: `AuthenticatePlayer`, `SyncWorldState`).
3. **Interface Adapters (`src/adapters/`):** Tradutores de limites. Convertem os dados de/para a rede em formatos que os Casos de Uso e o Domínio entendam. Aqui residem os `Controllers` e os `Gateways`.
4. **Framework & Infrastructure (`src/infrastructure/`):** A camada mais externa. Implementa a comunicação concreta utilizando as APIs do Godot (ex: `ENetMultiplayerPeer`, `MultiplayerAPI`, chamadas RPCs nativas). Qualquer acoplamento direto com as classes inerentes da Engine restringe-se a esta camada.

## 4. O MANDATO DE INFRAESTRUTURA

O projeto é governado por **Code-First** e **Clean Architecture**. Eliminando a dependência de editores visuais para lógicas de negócio.

## 5. O MANDATO DE TESTES

O projeto é governado por **TDD Rigoroso**. Nenhuma funcionalidade lógica pode existir se não houver um teste a justificá-la.

### 5.1. As Leis de Ouro do TDD

1. **Test-First Exigido:** É expressamente proibido escrever código sem antes ter escrito um `.gd` de teste falhando na pasta `tests/`. O ciclo vermelho, verde e refatoração é obrigatório.
2. **Comentários Didáticos e Metodologia AAA:** Cada teste unitário deve servir como documentação viva. Todo o teste deve ser estruturado e comentado com o padrão **Arrange, Act, Assert**:

    ```gdscript
    func test_must_do_something_specific():
        # Arrange (Preparação): Por que o mock X está assim...
        var mock_dependencia = double(Dependencia)
        stub(mock_dependencia, "metodo").to_return(true)

        # Act (Ação): Execução da unidade sob teste (SUT)...
        var result = sut.execute_action()

        # Assert (Verificação): Validação dos resultados...
        assert_true(result, "A ação deveria retornar verdadeiro")
    ```

3. **Framework Obrigatório:** O framework oficial e exclusivo para testes (incluindo unitários, mocks, doubles e spies) deste projeto é o **[bitwes/Gut](https://github.com/bitwes/Gut)**. Todas as asserções e simulações devem utilizar estritamente a API nativa fornecida por ele. O uso da suíte de testes internos da Godot (doctest) ou de alternativas de terceiros (como GDUnit4) está terminantemente proibido.

## 6. PADRÕES DE CÓDIGO E CONVENÇÕES

### 6.1 Cabeçalhos de Arquivos e Rastreabilidade (GDScript Docstrings)

Todo e qualquer arquivo de código (`.gd`) da aplicação e dos testes deve iniciar **obrigatoriamente** com um bloco estruturado de docstrings (`##`). Este cabeçalho padroniza a rastreabilidade e define a responsabilidade arquitetural do módulo. A nomenclatura de Arquivos deve ser sempre em `snake_case` (padrão Godot) e utilizar tipagem estática rigorosa.

**Template Principal:**

```gdscript
## @file [nome_do_arquivo.gd]
## @path [caminho/relativo/nome_do_arquivo.gd]
##
## @description
## Descrição clara da responsabilidade arquitetural do arquivo.
## No caso de testes, detalhar o System Under Test (SUT) e mocks globais.
##
## @created [YYYY-MM-DD]
## @updated [YYYY-MM-DD]
##
## @since [Versão original]
## @lastModifiedIn [Versão atual/release]
##
## @author Leonardo S. Badaró (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)
```

**Regras de Metadados:**

- **`@file` e `@path`**: Identificação direta do arquivo no repositório.
- **`@created` e `@since`**: Históricos e imutáveis. A base deste boilerplate inicia-se em `2026-07-24` e versão `0.1.0`.
- **`@updated`**: Atualizado apenas por alterações funcionais, estruturais ou arquiteturais. **NÃO** atualize por lint automático ou pequenos ajustes cosméticos.
- **`@lastModifiedIn`**: Atualizado apenas quando o arquivo fizer parte efetiva de uma nova release/tag global.

### 6.2 Formatação e IDE

- **Identação:** Tabs puros (`\t`), configurados para tamanho visual de 4 espaços.
- **Formatador:** Regido estritamente pelo `godot-tools` via servidor LSP no arquivo `.vscode/settings.json`.

### 6.3 Padrões de Nomenclatura (GDScript Style Guide)

- **Funções e Métodos:** É **obrigatório** que o nome de todas as funções (inclusive de testes) seja escrito em inglês e utilizando `snake_case`, conforme definido pelo GDScript Style Guide oficial (ex: `inject_repository()`, `test_must_create_user`), seguindo estritamente o formato [GDScript style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html).

## 7. DIRETRIZES DE EVOLUÇÃO E INTEGRIDADE

A IA, ao receber um pedido para criar um "novo domínio" (Ex: `FeatureX`), deve obedecer rigidamente à topologia do projeto, sempre escrevendo o teste antes, seguindo o fluxo em cascata:

1. **Definição de Contratos:** Determinar abstrações e interfaces antes de qualquer implementação.
2. **Ciclo TDD (Domínio):** Escrever o teste que dita o comportamento esperado para o Core Domain. Implementar o domínio até o teste passar (Verde) e refatorar.
3. **Casos de Uso:** Orquestrar o fluxo de informações, novamente governado por testes unitários e mocks rigorosos.
4. **Adaptadores e Infraestrutura:** Implementar as amarras com o Godot Engine, garantindo que o acoplamento permaneça apenas nas fronteiras externas.
5. **Injeção de Dependência:** Todo componente deve receber suas dependências via construtor ou métodos de injeção claros. Instanciações diretas `new()` de classes de infraestrutura dentro do domínio estão proibidas.

A robustez da aplicação é inversamente proporcional ao acoplamento. Mantenha os métodos pequenos, altamente coesos e a injeção de dependências clara via construtores nas camadas intermédias.

## 8. Padrões de Documentação e Versionamento (SemVer)

- **Versionamento Semântico (SemVer):** O projeto adota o padrão global `MAJOR.MINOR.PATCH`. A versão global representa o estado consolidado completo da aplicação, seguindo estritamente o formato [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
- **Changelog:** Todas as alterações relevantes (features, correções, refatorações estruturais) devem ser documentadas no `CHANGELOG.md`, seguindo estritamente o formato [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
- **Histórico Imutável (Git):** O changelog é a fonte da verdade para lançamentos. Cada alteração significativa deve refletir o estado do repositório no momento da criação.

**[FIM DO CONTRATO]**
