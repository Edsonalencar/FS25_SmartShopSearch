# FS25 Smart Shop Search — PRD de Base Técnica e Infraestrutura

**Versão:** 1.0
**Data:** 2026-09-27
**Documento de entrada:** [`requisitos.md`](../requisitos.md) v1.1
**Referência técnica analisada:** `w33zl/FS25_ShopSearch` @ `d4166f7` (v1.1.0.0, último push 2025-03-16)
**Status:** Proposta para aprovação — base da Modelagem Técnica de Implementação

---

## 0. Como ler este documento

Este PRD **não repete** os requisitos funcionais (RF), não funcionais (RNF) e de ModHub (RMH) do documento de requisitos. Ele define **a fundação técnica** sobre a qual esses requisitos serão implementados:

| Parte | Conteúdo |
|---|---|
| §1–2 | Objetivo, escopo e análise técnica do projeto de referência |
| §3 | Restrições da plataforma FS25 que moldam a arquitetura |
| §4 | Decisões arquiteturais (ADRs) |
| §5–9 | Arquitetura, contratos de dados, ciclo de vida, integração GUI e extração de dados |
| §10–14 | Infraestrutura: repositório, toolchain, testes, build/release, observabilidade |
| §15–17 | Orçamentos de performance, compatibilidade e conformidade ModHub |
| §18–21 | Rastreabilidade, plano de execução, riscos e questões em aberto |

Convenções:

- **[CONFIRMADO]** — observado no código da referência ou em comportamento reproduzível.
- **[A VALIDAR]** — API/comportamento provável do FS25, que deve ser confirmado na Fase 0 (spike) contra o LUADOC/código-fonte de scripts do jogo na versão alvo antes de ser adotado. Esta é a aplicação direta do item 2.3 do documento de requisitos ("confrontar com a documentação oficial").
- Palavras **deve / deveria / pode** seguem a semântica RFC 2119.

---

## 1. Objetivo e escopo

### 1.1 Objetivo

Estabelecer a arquitetura, os contratos internos, a cadeia de ferramentas e o pipeline de qualidade que permitam implementar **todo** o escopo do Smart Shop Search (fuzzy, parser de linguagem, ranking, filtros, compatibilidade, explicabilidade, i18n) de forma:

1. **Testável fora do jogo** — o motor de busca roda e é testado em Lua 5.1 puro, sem o GIANTS Engine.
2. **Isolada da GUI** — mudanças de patch do FS25 afetam só a camada de adaptação.
3. **Segura** — qualquer falha do mod degrada para a loja original, nunca a quebra.
4. **Publicável** — pipeline repetível de empacotamento, TestRunner e checklist ModHub.

### 1.2 Dentro do escopo

- Arquitetura em camadas e fronteiras entre módulos.
- Estrutura do repositório e do pacote do mod.
- Contratos de dados (índice, consulta, resultado, motivo de match).
- Estratégia de bootstrap, hooks e fallback.
- Estratégia de extração de metadados do catálogo.
- Toolchain de desenvolvimento, lint, testes, benchmark, build, release e CI.
- Observabilidade e diagnóstico.
- Orçamentos de performance iniciais.

### 1.3 Fora do escopo (tratado na Modelagem de Implementação)

- Valores finais de pesos de ranking e limiares fuzzy (aqui só a estrutura e os valores iniciais).
- Conteúdo completo dos dicionários de aliases.
- Layout visual detalhado dos elementos de GUI.

---

## 2. Análise técnica do projeto de referência

### 2.1 Inventário

| Artefato | Papel | Carregado no jogo? |
|---|---|---|
| `ShopSearch.lua` (~220 linhas) | Toda a lógica: hotkey, diálogo, filtro, exibição, botão | Sim |
| `scripts/modLib/ModHelper.lua` | Bootstrap `Mod:init()`, eventos de ciclo de vida, settings | Sim |
| `scripts/modLib/LogHelper.lua` | Objeto global `Log` | Sim |
| `scripts/modLib/DevHelper.lua` | `measureStart` (cronômetro) | Sim (via `source`) |
| `scripts/modLib/UIHelper.lua` | `cloneButton` | Sim (via `source`) |
| Outros ~20 arquivos `modLib/*` | Utilitários não usados | **Não** — excluídos por `.fsproj` |
| `.fsproj` | Config do FSBuild (ferramenta do autor): exclusões e auto-bump de `descVersion` | Build |
| `modDesc.xml` | `descVersion="96"`, `multiplayer supported="true"`, action `SEARCH_SHOP` → `KEY_f` | Sim |
| `translation_{en,de,fr,pl}.xml` | 5 strings | Sim |

### 2.2 Fluxo de execução [CONFIRMADO]

```text
source(ShopSearch.lua)
  └─ Mod:init() → addModEventListener(); prepend/append em FSBaseMission.* (10 hooks genéricos)
  └─ overwrite TabbedMenuWithDetails.onOpen   → se g_shopMenu.isOpen: registerActionEvent(SEARCH_SHOP)
  └─ overwrite ShopMenu.updateButtonsPanel    → clona 1º botão do buttonsPanel → "searchStoreButton"
                                                 visível só em Vehicles/Brands/Packs/DLCs/ItemDetails

[tecla F ou botão]
  └─ TextInputDialog.createFromExistingGui{ maxCharacters=40, onTextEntered=... }
       └─ hack: TextInputDialog.INSTANCE.textElement.applyProfanityFilter = false
  └─ doSearch(text)
       └─ para cada item de g_storeManager:getItems()
            filtra: not isBundleItem and showInStore and species ∈ {VEHICLE, HANDTOOL}
            match: string.find(campo, padrão "[Tt][Rr]...") em name | dlcTitle | brandNameRaw | author
            → g_shopController:makeDisplayItem(storeItem)
       └─ g_shopMenu.currentCategoryName = "misc"; currentDisplayItems = items
          pageShopItemDetails:setDisplayItems(items)
          se currentPage.rootName == "SEARCH" → popDetail()
          pageShopItemDetails:setCategory("SEARCH", header, ShopMenu.SLICE_ID.VEHICLES)
          pushDetail(pageShopItemDetails); resetListSelection()
```

### 2.3 Pontos de extensão identificados [CONFIRMADO no código da referência]

| Ponto | Uso | Avaliação para o nosso projeto |
|---|---|---|
| `g_storeManager:getItems()` | Fonte do catálogo | **Adotar**. Fonte canônica. |
| Campos `storeItem.name`, `brandNameRaw`, `dlcTitle`, `isMod`, `customEnvironment`, `isBundleItem`, `showInStore`, `species` | Filtragem/match | **Adotar**; ampliar (§9). |
| `g_modManager.nameToMod[env].author` | Autor | **Adotar** com proteção a `nil`. |
| `StoreSpecies.VEHICLE`, `StoreSpecies.HANDTOOL` | Escopo | **Adotar**; avaliar `PLACEABLE` separadamente [A VALIDAR]. |
| `g_shopController:makeDisplayItem(storeItem)` | Converte para item exibível | **Adotar**. Evita recriar a lógica de exibição do jogo. |
| `ShopMenu.pageShopItemDetails:setDisplayItems / setCategory / resetListSelection`, `pushDetail / popDetail` | Renderização de resultados como "categoria virtual" | **Adotar via adaptador**, com verificação de existência de cada função antes do uso. |
| `ShopMenu.updateButtonsPanel` (overwritten) + clone de botão | Botão "Pesquisar" | **Adotar o conceito**, trocando para `appendedFunction` e criação idempotente. |
| `TabbedMenuWithDetails.onOpen` (overwritten) | Registrar hotkey | **Substituir**: hook genérico de uma classe base afeta *todos* os menus com abas. Preferir hook específico de `ShopMenu` [A VALIDAR]. |
| `TextInputDialog.createFromExistingGui` | Entrada de texto | **Adotar como modo inicial**; investigar campo de texto embutido na página (busca incremental, RF-003). |
| `g_inputBinding:registerActionEvent` + `setActionEventTextPriority` | Hotkey configurável (RF-002) | **Adotar**. |

### 2.4 Defeitos e limitações observadas (não reproduzir)

| # | Observação | Consequência | Decisão |
|---|---|---|---|
| D1 | `local returnValue superFunc(self, ...)` (falta `=`) no hook de `onOpen` | Valor de retorno do original é descartado; funciona por acaso | Todo hook passa por `HookRegistry` com testes |
| D2 | `storeItem.matchWeight` é **escrito no objeto do jogo** e nunca zerado | Poluição de estado global; peso acumula entre buscas; nunca é usado para ordenar (issue #3 aberta "Sort search result weighted") | Nunca mutar `StoreItem`; score vive no `SearchResult` |
| D3 | Match por padrão Lua gerado caractere a caractere (`[Aa]`) | Caracteres mágicos (`%`, `(`, `-`, `.`) na consulta quebram ou alteram o padrão; sem suporte a acentos/UTF-8 | Normalização própria + comparação literal (`string.find(s, t, 1, true)`) |
| D4 | Consulta inteira tratada como uma substring única | "john 6r" não encontra "John Deere 6R" | Tokenização + cobertura (RF-015, RF-041) |
| D5 | Varredura linear de todo o catálogo a cada busca, sem índice | Custo O(n·m) por consulta; inviável para fuzzy | Índice pré-construído (§6.1) |
| D6 | Hook em `TabbedMenuWithDetails.onOpen` (classe base) | Executa em qualquer menu com abas; já gerou incompatibilidade com *Garage Menu* (issue #5) | Hooks no alvo mais específico possível |
| D7 | `registerActionEvent` a cada abertura sem `removeActionEvent` explícito | Risco de registro duplicado/conflito [A VALIDAR] | Registro idempotente com contexto de input próprio |
| D8 | Hack `applyProfanityFilter = false` via `TextInputDialog.INSTANCE` | Depende de estrutura interna do diálogo; `applyTextFilter` do construtor não funciona | Manter como opção encapsulada, com guarda de existência |
| D9 | `ModHelper` registra 10 hooks em `FSBaseMission.*` que o mod não usa | Superfície de conflito desnecessária | Registrar somente os eventos usados |
| D10 | `MAX_ITEMS = 5000` com `print("skip")` | Spam de log se atingido | Logging com níveis e rate-limit (RNF-009) |
| D11 | Categorias de venda/"outros" precisaram ser bloqueadas manualmente (issue #4) | A lista de páginas válidas é frágil entre patches | Lista de páginas elegíveis centralizada e testada no smoke test |
| D12 | Commit `c7ed772` "Fix the Lua issue introduced in game 1.5.1 or 1.6": `updateSubPageSelector()` deixou de existir/funcionar | **Prova de que a GUI da loja muda entre patches** | Adaptador GUI isolado + verificação defensiva de funções + smoke test a cada patch |

### 2.5 Licença — conclusão e decisão

| Componente | Situação encontrada | Implicação |
|---|---|---|
| `ShopSearch.lua`, `modDesc.xml`, traduções, ícone | **Sem arquivo LICENSE**; API do GitHub retorna `license: null` | Sem licença explícita = todos os direitos reservados ao autor. **Não há autorização para copiar código.** |
| `scripts/modLib/*` (Weezls Mod Lib) | Cabeçalho declara **CC BY-NC-SA 4.0** | Uso não comercial, atribuição obrigatória e *share-alike* (obrigaria licenciar nosso mod sob os mesmos termos). CC não é licença adequada para software e o NC conflita com qualquer monetização futura. |

**Decisão (ADR-01): implementação *clean-room*.** Nenhum trecho de código da referência será copiado. A referência é usada exclusivamente para **identificar quais APIs do jogo existem e como se comportam**. Nomes de APIs do jogo (`g_storeManager`, `ShopMenu`, etc.) pertencem à GIANTS e não à referência. Essa decisão elimina as obrigações do item 2.2 do documento de requisitos. Se no futuro houver interesse em reutilizar algo, deve-se solicitar licença explícita ao autor (w33zl) e registrar em `docs/THIRD_PARTY.md`.

Registrar no README uma seção "Agradecimentos" citando o `FS25_ShopSearch` como inspiração é recomendado (cortesia, não obrigação legal).

---

## 3. Restrições da plataforma FS25

| # | Restrição | Impacto no projeto |
|---|---|---|
| P1 | Scripts em **Lua 5.1** (dialeto do GIANTS Engine) em sandbox: sem `io`, `os.execute`, `require`, rede ou FFI; `string` opera em **bytes**, não em caracteres UTF-8 | Núcleo escrito em Lua 5.1 estrito; normalização UTF-8 implementada manualmente com tabela de dobra de acentos (§6.2). Proibido usar `goto`, `//`, operadores bitwise, `utf8.*` (Lua 5.3+). |
| P2 | Arquivos carregados via `<extraSourceFiles>` do `modDesc.xml` ou `source(g_currentModDirectory .. path)`; `g_currentModDirectory`/`g_currentModName` só são válidos durante o carregamento | Capturar ambos em variáveis locais no primeiro arquivo carregado. |
| P3 | Cada mod roda em ambiente próprio; globais do jogo acessíveis; outros mods podem sobrescrever as mesmas funções | Um único global exportado (`SmartShopSearch`); tudo mais `local`. Hooks encadeados, nunca substituições destrutivas. |
| P4 | Mods com script **não são suportados em consoles** no ModHub [A VALIDAR na política vigente] | Alvo: PC/Mac. Documentar no modDesc/descrição. |
| P5 | Multiplayer: todos os jogadores baixam os mods do servidor; a loja é UI local | Mod 100% **client-side**: sem eventos de rede, sem dados em savegame. `multiplayer supported="true"`. Deve funcionar em servidor dedicado sem GUI (não registrar nada de GUI quando `g_dedicatedServer ~= nil`). |
| P6 | ModHub proíbe dependências externas obrigatórias, acesso à rede e código ofuscado; exige log limpo e TestRunner aprovado [A VALIDAR regras vigentes] | Offline-first (RNF-004); sem dependências de outros mods. |
| P7 | GUI da loja muda entre patches (D12) | Camada `adapters/gui` isolada + guardas de existência + smoke test por patch. |
| P8 | Catálogo inclui base, DLC, pacotes e mods; qualidade dos metadados de mods é heterogênea | Extração defensiva campo a campo com `pcall` (RF-061, RF-062). |
| P9 | Specs de loja no FS25 são carregadas por *spec types* registrados em `g_storeManager` [A VALIDAR estrutura exata: `storeItem.specs`, `getSpecTypes()`, `loadSpecValue`/`getValueFunc`] | Extração de specs via adaptador próprio (§9.2), nunca espalhada pelo núcleo. |

---

## 4. Decisões arquiteturais (ADRs)

Cada ADR deve ser mantido como arquivo em `docs/adr/NNNN-titulo.md` (status, contexto, decisão, consequências).

| ADR | Decisão | Alternativas descartadas | Motivo |
|---|---|---|---|
| **01** | Implementação clean-room, sem Weezls Mod Lib | Fork da referência | Licença (§2.5), defeitos (§2.4), escopo muito maior |
| **02** | **Arquitetura hexagonal**: `core/` puro (zero globais do jogo) + `adapters/` (jogo) + `app/` (orquestração) | Monólito como a referência | Testabilidade fora do jogo, isolamento de patches (P7) |
| **03** | Todo hook passa por um `HookRegistry` que: usa `Utils.appendedFunction` / `prependedFunction` preferencialmente; `overwrittenFunction` só quando for necessário alterar retorno; envolve o corpo em `pcall`; é idempotente; desativa o hook após N falhas | Sobrescrever funções diretamente | RNF-007, RF-060, compatibilidade |
| **04** | Índice invertido em memória construído **sob demanda** na primeira abertura da loja após `loadMapFinished`, com possibilidade de construção fatiada entre frames; invalidado por assinatura do catálogo (contagem + hash de `xmlFilename`) | Construir no `loadMap`; varredura linear por busca | Não atrasar carregamento; itens de mods podem ser registrados tarde |
| **05** | Fuzzy em dois estágios: (a) geração de candidatos por **trigramas** do vocabulário do índice; (b) verificação com **Damerau-Levenshtein restrito (OSA)** com limite de distância e *early exit*. Limiar por tamanho de token | Levenshtein puro sobre todo o catálogo; Soundex/Metaphone | Cobre remoção, inserção, substituição e transposição (RF-016..019) com custo controlado; fonéticos são dependentes de idioma |
| **06** | Dados linguísticos (aliases, sinônimos, unidades, comparadores, números por extenso) em **XML de dados por idioma**, lidos com a API `XMLFile` do jogo em produção e com um leitor mínimo nos testes | Tabelas Lua hardcoded | RF-023, RF-025, RF-058/059; extensível sem tocar no código |
| **07** | Resultados exibidos como **categoria virtual** na página de detalhes da loja (técnica da referência), encapsulada em `ShopGuiAdapter`, com ordenação pelo score | Tela/diálogo próprio de resultados | Reaproveita a exibição, compra e detalhes nativos; menor superfície de conflito |
| **08** | Entrada de texto: fase 1 com `TextInputDialog`; fase 2 investigar `TextInputElement` embutido na página para busca incremental (RF-003) | — | O diálogo é comprovadamente funcional; o campo embutido depende de GUI XML própria |
| **09** | Nenhum dado em savegame. Preferências do usuário (ex.: mostrar explicações, idioma de vocabulário extra) em `modSettings/FS25_SmartShopSearch/settings.xml` | Salvar no savegame | RNF-010; remoção limpa |
| **10** | Mod exclusivamente client-side; sem eventos de rede | Sincronização de buscas | P5 |
| **11** | Um único global `SmartShopSearch`; módulos internos como tabelas locais retornadas por arquivo e registradas num *namespace* interno | Vários globais | P3, conflitos |
| **12** | Integração ModHub (RF-053..056) atrás de interface `CatalogSource`; implementação só se a Fase 0 provar API suportada | Scraping/HTTP | RF-056 |

---

## 5. Arquitetura

### 5.1 Camadas

```text
┌────────────────────────────────────────────────────────────────────┐
│ adapters/  (conhece o FS25; única camada que toca globais do jogo) │
│   GameBootstrap   HookRegistry   ShopGuiAdapter   InputAdapter     │
│   StoreCatalogSource  SpecExtractor  CompatibilityExtractor        │
│   GameLocale  GameLogger  SettingsStore  ModHubCatalogSource(*)    │
└───────────────▲───────────────────────────────────▲────────────────┘
                │ implementa portas                 │ chama
┌───────────────┴──────────────┐   ┌────────────────┴───────────────┐
│ app/                         │   │ ports/ (interfaces documentadas)│
│   SearchService              │◄──┤   CatalogSource  Logger  Clock  │
│   IndexLifecycle             │   │   Locale  DataLoader  Settings  │
│   Diagnostics / Console      │   └────────────────────────────────┘
└───────────────▲──────────────┘
                │ usa
┌───────────────┴────────────────────────────────────────────────────┐
│ core/  (Lua 5.1 puro, determinístico, sem globais do jogo)         │
│   text/  Utf8  TextNormalizer  Tokenizer                           │
│   lang/  AliasResolver  NumberParser  UnitParser  ComparatorParser │
│          QueryParser → QueryAST                                    │
│   index/ SearchIndex  TrigramIndex  IndexBuilder                   │
│   match/ ExactMatcher  FuzzyMatcher(OSA)  FieldMatcher             │
│   rank/  SearchScorer  FilterEngine  Ranker                        │
│   compat/ CompatibilityResolver                                    │
│   model/ IndexedItem  Query  SearchResult  MatchReason             │
└────────────────────────────────────────────────────────────────────┘
(*) somente se RF-053 comprovar API suportada
```

**Regra de dependência (verificada por lint, §11.4):** `core/` não pode referenciar nenhum global com prefixo `g_`, nenhuma classe do jogo (`ShopMenu`, `Utils`, `XMLFile`, …) nem `adapters/`. `app/` depende de `core/` e de `ports/`. Só `adapters/` e `main.lua` conhecem o jogo.

### 5.2 Mapeamento para os componentes esperados (requisitos §23)

| Componente do requisito | Módulo |
|---|---|
| Bootstrap | `main.lua` + `adapters/GameBootstrap.lua` |
| ShopIntegration / GUI | `adapters/ShopGuiAdapter.lua`, `adapters/InputAdapter.lua`, `gui/*.xml` |
| SearchIndex | `core/index/*` + `app/IndexLifecycle.lua` |
| TextNormalizer, Tokenizer | `core/text/*` |
| AliasResolver | `core/lang/AliasResolver.lua` + `data/<lang>/aliases.xml` |
| QueryParser (Number/Unit/Comparator) | `core/lang/*` |
| SearchEngine (Exact/Fuzzy/Field) | `core/match/*` + `app/SearchService.lua` |
| SearchScorer, FilterEngine | `core/rank/*` |
| CompatibilityResolver | `core/compat/*` + `adapters/CompatibilityExtractor.lua` |
| SearchResult | `core/model/SearchResult.lua` |
| Localization | `translations/*.xml` (UI) + `data/<lang>/` (vocabulário) + `adapters/GameLocale.lua` |
| Diagnostics | `app/Diagnostics.lua` + `adapters/GameLogger.lua` |
| ModHubAdapter | `adapters/ModHubCatalogSource.lua` (condicional) |

### 5.3 Estrutura do repositório

```text
SmartShopSearch/                        (raiz do repositório git)
├── README.md
├── CHANGELOG.md
├── LICENSE                             (definir: ver §21, Q-01)
├── requisitos.md
├── docs/
│   ├── PRD-base-tecnica.md             (este documento)
│   ├── adr/0001-clean-room.md …
│   ├── api-findings/                   (resultado da Fase 0 por versão do jogo)
│   │   └── fs25-<versão>.md
│   ├── THIRD_PARTY.md
│   └── release-checklist.md
├── src/                                (= conteúdo do mod; vira o ZIP)
│   ├── modDesc.xml
│   ├── icon_SmartShopSearch.dds
│   ├── main.lua                        (único arquivo em <extraSourceFiles>)
│   ├── core/ …                         (ver §5.1)
│   ├── ports/ …                        (apenas documentação de contrato em comentários LuaLS)
│   ├── app/ …
│   ├── adapters/ …
│   ├── gui/                            (XML/profiles se houver GUI própria)
│   ├── data/
│   │   ├── common/units.xml
│   │   ├── pt/aliases.xml  pt/numbers.xml  pt/comparators.xml
│   │   ├── en/…  de/…  fr/…
│   └── translations/translation_{br,pt,en,de,fr,…}.xml
├── tests/
│   ├── unit/                           (busted, Lua 5.1)
│   ├── golden/                         (consultas → resultados esperados)
│   ├── fixtures/catalog/               (dumps do catálogo: base, base+DLC, base+mods)
│   ├── bench/
│   └── stubs/                          (stubs mínimos de XMLFile/Logger para testes)
├── tools/
│   ├── build.py                        (empacotamento + validação)
│   ├── check_deps.py                   (regra de dependência core/)
│   ├── run_testrunner.ps1              (Windows)
│   └── dev_link.{sh,ps1}               (link do src/ na pasta de mods)
├── types/                              (anotações LuaLS dos globais do FS25 usados)
├── .luacheckrc  .stylua.toml  .luarc.json  .editorconfig
└── .github/workflows/ci.yml
```

### 5.4 Estrutura do pacote distribuído

`FS25_SmartShopSearch.zip` (nome do ZIP = nome do mod = prefixo `FS25_`, apenas `[A-Za-z0-9_]`):

```text
modDesc.xml
icon_SmartShopSearch.dds
main.lua
core/ ports/ app/ adapters/ gui/ data/ translations/
```

Sem `tests/`, `tools/`, `docs/`, `types/`, arquivos de editor, `.git`, `*.md`, fontes de ícone (`.psd`, `.pdn`, `.png` de trabalho).

---

## 6. Contratos de dados

Todos os modelos são tabelas Lua simples, documentadas com anotações LuaLS (`---@class`). Nenhum modelo guarda referência mutável ao `StoreItem` além de `ref` (somente leitura).

### 6.1 `IndexedItem` (entrada do índice)

```lua
---@class IndexedItem
---@field id            integer        -- posição estável no índice
---@field ref           table          -- StoreItem original (somente leitura, nunca mutado)
---@field xmlFilename   string         -- chave de identidade/assinatura
---@field species       string         -- "vehicle" | "handTool" | …
---@field fields        table<string, IndexedField>  -- name, brand, category, mod, author, dlc
---@field specs         table<string, SpecValue>     -- power, capacity, width, speed, …
---@field price         number|nil
---@field origin        "base"|"dlc"|"mod"
---@field compat        CompatInfo|nil  -- preenchido sob demanda

---@class IndexedField
---@field raw     string     -- texto original para exibição
---@field norm    string     -- normalizado (§6.2)
---@field tokens  string[]   -- tokens normalizados

---@class SpecValue
---@field value number        -- sempre na unidade canônica (§6.3)
---@field unit  string        -- "kw", "l", "m", "kmh", "kg", "money"
---@field source string       -- de onde veio (para diagnóstico)
```

Estruturas auxiliares do `SearchIndex`:

- `postings[token] → { [itemId] = bitmaskDeCampos }` — índice invertido exato.
- `vocabulary[token] → frequência` — base para fuzzy e IDF.
- `trigrams[tri] → { token, … }` — candidatos fuzzy.
- `facets.brand / category / origin → { valor → { itemId… } }` — filtros estruturados.
- `numeric[spec] → lista ordenada de (value, itemId)` — filtros por faixa via busca binária.

### 6.2 Normalização (contrato do `TextNormalizer`)

`normalize(s) → string` deve ser **idempotente** e aplicar, nesta ordem:

1. Remoção de códigos de formatação/controle.
2. Dobra de acentos em UTF-8 por tabela de sequências de bytes (`á à â ã ä → a`, `ç → c`, `ß → ss`, `ø → o`, …) cobrindo Latin-1 Suplementar e Latin Extended-A (idiomas do FS25 com alfabeto latino).
3. Minúsculas (ASCII após dobra; letras não latinas preservadas como bytes).
4. Separação de fronteiras letra↔dígito (`200cv → 200 cv`, `6r → 6 r` em índice secundário; o token original também é mantido).
5. Pontuação → espaço, exceto separadores numéricos entre dígitos (`40.000`, `1,5`), resolvidos pelo `NumberParser` conforme o locale.
6. Colapso de espaços e *trim*.

### 6.3 Unidades canônicas

| Grandeza | Canônica | Aceitas na consulta (exemplos) | Conversão |
|---|---|---|---|
| Potência | kW | `cv`, `hp`, `ps`, `kw` | 1 hp = 0,7457 kW; 1 cv/ps = 0,7355 kW |
| Volume | L | `l`, `litro(s)`, `m3`, `m³`, `gal` | 1 m³ = 1000 L |
| Comprimento/largura | m | `m`, `metro(s)`, `ft`, `pés` | 1 ft = 0,3048 m |
| Velocidade | km/h | `km/h`, `kmh`, `mph` | 1 mph = 1,609 km/h |
| Massa | kg | `kg`, `t`, `ton` | 1 t = 1000 kg |
| Dinheiro | unidade do jogo | `R$`, `$`, `€`, `mil`, `k`, `mi` | Moeda do jogo é única internamente; símbolo é ignorado [A VALIDAR se `storeItem.price` já está na moeda exibida] |

A exibição no jogo usa as preferências de unidade do jogador (métrico/imperial); a comparação é sempre na unidade canônica. As tabelas vivem em `data/common/units.xml`.

### 6.4 `Query` (AST da consulta)

```lua
---@class Query
---@field raw        string
---@field terms      QueryTerm[]        -- termos textuais restantes (RF-036)
---@field concepts   QueryConcept[]     -- categoria/marca resolvidas por alias
---@field constraints Constraint[]      -- numéricos
---@field locale     string
---@field warnings   string[]           -- partes não compreendidas (diagnóstico)

---@class QueryTerm
---@field text     string   -- normalizado
---@field span     integer[] -- {inicio, fim} na consulta original
---@field fuzzyMax integer  -- distância máxima permitida para este termo

---@class QueryConcept
---@field kind  "category"|"brand"|"species"|"origin"
---@field value string      -- id canônico (ex.: "TRACTORSM", "JOHNDEERE")
---@field confidence number -- 0..1
---@field span  integer[]

---@class Constraint
---@field spec  string       -- "power" | "capacity" | "price" | …
---@field op    "gt"|"gte"|"lt"|"lte"|"eq"|"between"|"approx"
---@field min   number|nil   -- unidade canônica
---@field max   number|nil
---@field span  integer[]
```

Exemplo de referência (requisitos §1):

```text
"trtor jon dere entre 200 e 300 cv por menos de 150 mil"
concepts:    category≈tractor(0.86), brand≈JOHNDEERE(0.80)
constraints: power between 147.1–220.7 kW; price lt 150000
terms:       []
```

### 6.5 `SearchResult` e `MatchReason`

```lua
---@class SearchResult
---@field item     IndexedItem
---@field score    number          -- 0..1 após normalização
---@field coverage number          -- fração de termos/conceitos satisfeitos
---@field reasons  MatchReason[]

---@class MatchReason
---@field kind   "exact"|"prefix"|"fuzzy"|"alias"|"constraint"|"compat"
---@field field  string            -- "name", "brand", "spec.power", …
---@field query  string            -- trecho da consulta
---@field matched string           -- valor do item
---@field detail string|nil        -- ex.: "distância 1", "221 cv ∈ [200, 300]"
---@field weight number            -- contribuição ao score
```

`reasons` é sempre preenchido (RF-051); exibi-lo é opcional (RF-052).

### 6.6 Modelo de score (estrutura; pesos calibrados na modelagem)

```text
score(item) = Σ_termos  max_campo( wCampo · wTipo · sim(termo, campo) · idf(termo) )
            + Σ_conceitos wConceito · confidence
            × fatorCobertura(coverage)
            − penalidades(fuzzy distante, termo curto, match só em campo secundário)
```

Valores iniciais propostos (a calibrar com o corpus golden, §11.2):

| Parâmetro | Inicial |
|---|---|
| `wCampo`: name / category / brand / spec / mod / author / dlc | 1.0 / 0.9 / 0.9 / 0.8 / 0.6 / 0.4 / 0.5 |
| `wTipo`: exact / prefix / alias / fuzzy d=1 / fuzzy d=2 | 1.0 / 0.85 / 0.9 / 0.7 / 0.45 |
| Limiar fuzzy por tamanho do token | ≤3: 0 (só exato/prefixo) · 4–5: 1 · 6–9: 2 · ≥10: 3 |
| Score mínimo para exibir | 0.25 · (melhor score da consulta) |

Filtros estruturados (`Constraint`) são **eliminatórios** quando o item possui o atributo; itens sem o atributo são excluídos de filtros explícitos de faixa, mas nunca geram erro (RF-061).

---

## 7. Ciclo de vida e bootstrap

### 7.1 Sequência

```text
Carga do mod (source de main.lua)
 1. Captura MOD_DIR / MOD_NAME
 2. source() de core/, app/, adapters/ em ordem fixa (lista explícita em main.lua)
 3. Cria SmartShopSearch (único global) — estado: "loaded"
 4. addModEventListener(SmartShopSearch)

loadMap / loadMapFinished
 5. Se servidor dedicado → estado "disabled-dedicated", encerra
 6. Carrega settings (modSettings) e dados linguísticos do idioma atual + fallback "en"
 7. HookRegistry:install()  — hooks da loja (§8)
 8. Estado: "ready" (índice ainda não construído)

Primeira abertura da loja
 9. IndexLifecycle:ensure() → constrói índice (fatiado se > orçamento de frame)
10. Estado: "indexed"

Cada abertura seguinte
11. Compara assinatura do catálogo → reconstrói se mudou

deleteMap
12. HookRegistry:uninstall() lógico (flags desligam os hooks; funções encadeadas permanecem inertes)
13. Libera índice e dados → estado "unloaded"
```

### 7.2 Máquina de estados e fallback

```text
loaded → ready → indexed
   │        │        │
   └────────┴────────┴──► degraded   (qualquer erro não recuperável)
```

Em `degraded`: o botão/hotkey de busca é ocultado, os hooks passam direto para a função original e uma única linha de erro é registrada no log com o motivo. A loja original permanece 100% funcional (RF-060). O comando de console `sssStatus` mostra o estado.

### 7.3 Regras de robustez

- Todo ponto de entrada vindo do jogo (hook, callback de input, callback de diálogo, comando de console) é envolvido por `SafeCall(fn, contexto)` = `pcall` + log + contador de falhas.
- Extração por item: falha em um item o descarta do índice (log agregado: "N itens ignorados") sem abortar a construção (RF-062).
- Nenhuma função do jogo é chamada sem antes verificar `type(obj.fn) == "function"` quando pertencer a GUI (P7).

---

## 8. Integração com a GUI da loja

### 8.1 Pontos de integração a validar na Fase 0

| # | Necessidade | Candidato | Status |
|---|---|---|---|
| G1 | Detectar abertura/fechamento da loja | `ShopMenu.onOpen` / `onClose` (append) | [A VALIDAR] — substitui D6 |
| G2 | Botão "Pesquisar" no painel | `ShopMenu.updateButtonsPanel` (append) + clone de botão existente, criado uma única vez | [CONFIRMADO conceito] |
| G3 | Páginas elegíveis para a busca | `pageShopVehicles`, `pageShopBrands`, `pageShopPacks`, `pageShopDLCs`, `pageShopItemDetails` | [CONFIRMADO v1.1 ref.] reavaliar por patch |
| G4 | Hotkey configurável | Action `SMART_SHOP_SEARCH` no `modDesc.xml` + `g_inputBinding:registerActionEvent` no contexto do menu | [CONFIRMADO conceito] — nome de action próprio para não colidir com `SEARCH_SHOP` da referência |
| G5 | Entrada de texto | `TextInputDialog.createFromExistingGui` | [CONFIRMADO] |
| G6 | Exibir resultados ordenados | `g_shopController:makeDisplayItem` + `pageShopItemDetails:setDisplayItems/setCategory` + `pushDetail/popDetail` | [CONFIRMADO] |
| G7 | Busca incremental (sem diálogo) | `TextInputElement` adicionado à página via GUI XML/clone | [A VALIDAR] — ADR-08 fase 2 |
| G8 | Painel de filtros (marca, categoria, faixa de preço) | Elementos de GUI próprios ou subpágina | [A VALIDAR] |
| G9 | Explicações de match | Texto auxiliar no item/tooltip, ou painel de detalhe | [A VALIDAR] |
| G10 | Contexto "compatíveis com este veículo" | Ação a partir do item selecionado em `pageShopItemDetails` | [A VALIDAR] |
| G11 | Estado vazio (RF-005) | Categoria virtual com lista vazia + texto informativo | [A VALIDAR] se a página aceita lista vazia sem erro |
| G12 | Limpar busca (RF-004) | `popDetail()` + restaurar categoria anterior | [CONFIRMADO parcial] |

### 8.2 Regras de GUI

- Criar elementos **uma vez** por instância de `g_shopMenu`, guardando referência em tabela própria do mod (não em campos novos de `g_shopMenu` — evita colisão com outros mods; a referência usa `g_shopMenu.searchStoreButton`).
- Nunca remover, reordenar ou re-estilizar elementos nativos.
- Rótulos via `g_i18n:getText` com chaves prefixadas `sss_`.
- Consulta máxima: 80 caracteres (a referência usa 40; consultas compostas precisam de mais).
- Desativar o filtro de palavrões no diálogo somente se a propriedade existir (D8).

---

## 9. Extração de dados do catálogo

### 9.1 Campos textuais

| Campo do índice | Origem | Status |
|---|---|---|
| `name` | `storeItem.name` | [CONFIRMADO] |
| `brand` | `storeItem.brandNameRaw`; título via `g_brandManager:getBrandByIndex(storeItem.brandIndex).title` | [CONFIRMADO] / [A VALIDAR] |
| `category` | `storeItem.categoryName` → título localizado via `g_storeManager:getCategoryByName(...)` | [A VALIDAR] |
| `dlc` | `storeItem.dlcTitle` | [CONFIRMADO] |
| `mod` | `storeItem.customEnvironment` → `g_modManager.nameToMod[env].title` | [CONFIRMADO parcial] |
| `author` | `g_modManager.nameToMod[env].author` (só quando `storeItem.isMod`) | [CONFIRMADO] |
| `origin` | `isMod` → mod; `dlcTitle ~= nil` → DLC; senão base | [A VALIDAR] critério de DLC vs. pacote gratuito |
| Escopo | `showInStore and not isBundleItem and species ∈ {VEHICLE, HANDTOOL}` | [CONFIRMADO]; `PLACEABLE` avaliar |

### 9.2 Especificações técnicas (RF-011, RF-046)

Estratégia em camadas, implementada em `adapters/SpecExtractor.lua`:

1. **Fonte primária:** specs já calculadas pelo jogo para a loja (`storeItem.specs` e *spec types* de `g_storeManager`) [A VALIDAR estrutura e se são carregadas preguiçosamente].
2. **Fonte secundária:** leitura direta do XML do veículo (`storeItem.xmlFilename`) para caminhos conhecidos (`storeData.specs.power`, `storeData.specs.maxSpeed`, `storeData.specs.neededPower`, capacidade de `fillUnit`, `workingWidth`) [A VALIDAR caminhos no FS25]. Ler XML de ~2000 itens tem custo: medir e, se necessário, fazer em fatias ou sob demanda.
3. Cada spec é registrada em `SpecRegistry` com: id, unidade canônica, extrator, conversor. Novas specs = nova entrada, sem mudar o núcleo (RNF-006).
4. Valores inválidos (`nil`, NaN, negativos, strings não numéricas) são descartados silenciosamente e contabilizados no diagnóstico.

Specs-alvo iniciais: `power`, `neededPower`, `maxSpeed`, `capacity`, `workingWidth`, `price`, `weight` (se disponível).

### 9.3 Compatibilidade (RF-048..050)

Somente evidências presentes nos dados do jogo, nesta ordem de confiabilidade:

1. **Combinações declaradas** pelo item (`storeData.specs.combination` / lista de combinações exibida na loja) [A VALIDAR].
2. **Tipos de engate**: `attacherJoints` do veículo × `inputAttacherJoints` do implemento (tipo de junta), mais `neededPower` do implemento × `power` do trator.

Cada relação carrega sua evidência em `MatchReason{kind="compat", detail=...}`. **Nunca** inferir compatibilidade por similaridade textual (RF-050). Extração é **sob demanda** (quando o usuário pede "compatíveis com X"), com cache por `xmlFilename`, pois exige ler XMLs.

### 9.4 Ferramenta de dump do catálogo

Comando de console `sssDumpCatalog` (somente com modo desenvolvedor ativo) grava em `modSettings/FS25_SmartShopSearch/dumps/catalog_<timestamp>.xml` todos os campos extraídos de todos os itens. Esses dumps alimentam `tests/fixtures/catalog/` (§11.2) — é a ponte entre o jogo real e os testes offline.

---

## 10. Ambiente de desenvolvimento

### 10.1 Toolchain

| Ferramenta | Uso | Obrigatório |
|---|---|---|
| **Lua 5.1** (interpretador de referência) | Executar testes com o mesmo dialeto do jogo | Sim |
| **LuaRocks** + **busted** | Testes unitários/golden | Sim |
| **luacheck** | Lint; `std = "lua51"` + globais do FS25 declarados em `.luacheckrc`; proibir globais novos exceto `SmartShopSearch` | Sim |
| **StyLua** | Formatação | Sim |
| **Lua Language Server** (VS Code) + `types/` | Autocomplete e checagem de tipos das anotações `---@class` e dos globais do jogo | Recomendado |
| **Python 3.11+** | `tools/build.py`, `tools/check_deps.py` | Sim |
| **Farming Simulator 25** (Steam/GIANTS) | Testes em jogo | Sim |
| **GIANTS Script Debugger / GIANTS Editor** | Depuração em jogo [A VALIDAR disponibilidade para FS25 na versão alvo] | Recomendado |
| **FS25 TestRunner** (GIANTS Developer Network) | Validação de release (RMH-004) | Sim, em Windows |
| **Documentação de scripts do FS25** (LUADOC / fontes de script extraídas com as ferramentas oficiais) | Fonte de verdade para os itens [A VALIDAR] | Sim |

O desenvolvimento do núcleo ocorre em Linux (máquina atual); jogo, TestRunner e depurador rodam em Windows (ou Linux via Proton — suporte do TestRunner sob Proton [A VALIDAR]).

### 10.2 Ciclo de desenvolvimento em jogo

1. `tools/dev_link` cria link simbólico/junction de `src/` para `Documents/My Games/FarmingSimulator2025/mods/FS25_SmartShopSearch` (pasta descompactada é aceita pelo jogo para desenvolvimento).
2. `game.xml` com `<development><controls>true</controls></development>` para habilitar console de desenvolvedor.
3. Iniciar com savegame de teste dedicado (base game, mapa padrão).
4. Acompanhar `log.txt` com filtro pelo prefixo `[SmartShopSearch]`.
5. Comandos de console (§13.2) para reindexar, rodar consultas e fazer dumps sem reabrir o jogo.
6. Recarregar scripts exige recarregar o savegame; por isso o máximo de lógica é validado offline (ADR-02).

### 10.3 Configuração de modo desenvolvedor do mod

`settings.xml` em `modSettings` com `<debug enabled="true" logLevel="debug"/>`. Sem esse arquivo, o mod roda em modo produção (nível `info`, comandos de dump desabilitados). **Nunca** usar presença de arquivo dentro do pacote como gatilho de debug (a referência faz isso com `DebugHelper.lua`), para que o ZIP publicado seja idêntico ao testado.

---

## 11. Estratégia de testes

### 11.1 Pirâmide

| Nível | Onde roda | Ferramenta | Cobre | Gate |
|---|---|---|---|---|
| Unitário | CI Linux | busted | Utf8, normalizer, tokenizer, parsers, OSA, trigramas, scorer, filtros | Todo PR |
| Golden (regressão de busca) | CI Linux | busted + fixtures | Consulta → top-N esperado sobre dumps reais do catálogo | Todo PR |
| Propriedades | CI Linux | busted + gerador simples | Idempotência da normalização; OSA simétrica e ≤ Levenshtein; parser nunca lança erro com entrada aleatória (fuzzing) | Todo PR |
| Benchmark | CI Linux (Lua 5.1) | `tests/bench` | Build do índice e p95 de consulta sobre fixture de 3000 itens | Todo PR, com tolerância; regressão > 20% falha |
| Arquitetura | CI Linux | `check_deps.py` + luacheck | Regra de dependência de `core/`; ausência de globais | Todo PR |
| Pacote | CI Linux | `build.py --verify` | Estrutura do ZIP, `modDesc.xml` válido, arquivos obrigatórios, sem arquivos proibidos | Todo PR |
| Smoke em jogo | Windows manual | checklist `docs/release-checklist.md` | Fluxos G1–G12, log limpo | Release |
| Compatibilidade | Windows manual | matriz §16 | Base, DLC, lote de mods, mods de loja conhecidos | Release |
| TestRunner | Windows | `run_testrunner.ps1` | RMH-004 | Release |

### 11.2 Corpus golden

- Fixture: dumps do catálogo (§9.4) em três perfis — `base`, `base+dlc`, `base+mods` (≥ 50 mods populares, incluindo mods com metadados incompletos).
- Arquivo `tests/golden/queries.pt.xml` (e por idioma) com casos no formato:
  ```xml
  <case id="fuzzy-trtor" query="trtor">
      <expectTop n="10" category="TRACTORS*" minHits="5"/>
  </case>
  <case id="brand-jon-dere" query="jon dere">
      <expectAll brand="JOHNDEERE" top="5"/>
  </case>
  <case id="composite-01" query="trtor jon dere entre 200 e 300 cv por menos de 150 mil">
      <expectConstraint spec="power" min="147.1" max="220.7"/>
      <expectConstraint spec="price" max="150000"/>
      <expectAll brand="JOHNDEERE" category="TRACTORS*"/>
  </case>
  <case id="negative-noise" query="xqzw">
      <expectMaxScore value="0.2"/>
  </case>
  ```
- **Todo critério de aceitação da seção 21 dos requisitos vira pelo menos um caso golden** (rastreabilidade §18).
- Métricas agregadas reportadas no CI: precisão@5, MRR, taxa de consultas sem resultado. Mudanças de pesos só entram se não piorarem as métricas do corpus.

### 11.3 Stubs para testes

`core/` não precisa de stubs (não conhece o jogo). `app/` recebe as portas por injeção; os testes usam `tests/stubs/` com `CatalogSource` baseado em fixture, `Logger` em memória e `Clock` falso. Adapters **não** são testados offline — são cobertos pelo smoke em jogo, e por isso devem ser finos.

### 11.4 Lint de arquitetura

`tools/check_deps.py` falha se qualquer arquivo em `src/core/` contiver: identificadores `g_[a-zA-Z]`, `ShopMenu`, `Utils.`, `XMLFile`, `getXML`, `source(`, `print(`, ou referência a `adapters/`. `luacheck` roda com `allow_defined_top = false` e lista de globais somente-leitura do FS25 para `adapters/`.

---

## 12. Build, versionamento e release

### 12.1 Versionamento

- SemVer no repositório (`1.0.0`), mapeado para o formato do `modDesc.xml` `1.0.0.0`.
- Fonte única da versão: `src/modDesc.xml`. `build.py` valida que `CHANGELOG.md` tem a entrada correspondente.
- `descVersion`: o valor exigido pela versão do FS25 alvo na data da submissão (a referência usa `96`, fev/2025) — atualizar a cada patch relevante e registrar em `docs/api-findings/`.

### 12.2 `tools/build.py`

1. Lê versão do `modDesc.xml`; valida XML (bem-formado + campos obrigatórios: `author`, `version`, `title` em `en` e `pt`/`br`, `description`, `iconFilename`, `multiplayer`, `l10n`, `extraSourceFiles`, `actions`, `inputBinding`).
2. Verifica que todo arquivo referenciado em `extraSourceFiles` e todos os `source()` listados em `main.lua` existem; e que todo `.lua` em `src/` está referenciado (sem código morto no pacote).
3. Verifica traduções: toda chave usada em `g_i18n:getText("sss_…")` existe em `translation_en.xml`; relata chaves faltantes por idioma.
4. Monta o ZIP com **allowlist** de extensões (`.lua .xml .dds .ogg .i3d .i3d.shapes`), caminhos com `/`, sem diretórios vazios, nome `FS25_SmartShopSearch.zip`.
5. Reabre o ZIP e confere contagem e SHA-256 arquivo a arquivo (mesma técnica do `package-mod.ps1` já usado no projeto Ford 8030).
6. Gera `dist/FS25_SmartShopSearch-<versão>.zip` + `dist/SHA256SUMS`.

### 12.3 TestRunner

- `tools/run_testrunner.ps1 -Zip dist\FS25_SmartShopSearch-<v>.zip` executa o TestRunner público da versão atual e arquiva o relatório em `dist/testrunner/<v>/`.
- Critério: nenhum erro; avisos justificados por escrito no checklist.
- Sempre baixar a versão mais recente do TestRunner antes de uma release candidata (RMH-011).

### 12.4 CI (GitHub Actions)

```text
on: push, pull_request
jobs:
  quality (ubuntu-latest):
    - setup Lua 5.1 + luarocks (leafo/gh-actions-lua, gh-actions-luarocks)
    - luarocks install busted luacheck
    - stylua --check src tests
    - luacheck src tests
    - python tools/check_deps.py
    - busted tests/unit tests/golden
    - lua tests/bench/run.lua --compare baseline.json
    - python tools/build.py --verify
    - upload-artifact: dist/*.zip
  testrunner (manual/self-hosted Windows, tags v*):
    - pwsh tools/run_testrunner.ps1
```

O TestRunner e o smoke em jogo dependem de instalação do jogo e licença; por isso são *gates* de release, não de PR.

### 12.5 Fluxo de release

```text
main verde → tag vX.Y.Z-rc.N → build → TestRunner → smoke + matriz de compatibilidade
          → checklist assinado → tag vX.Y.Z → upload ModHub (manual) → GitHub Release com ZIP e SHA256
```

---

## 13. Observabilidade e diagnóstico

### 13.1 Logging

- Prefixo fixo: `[SmartShopSearch]`. Níveis: `error`, `warning`, `info`, `debug`.
- Produção (`info`): no máximo **3 linhas** por sessão em funcionamento normal — carga (versão), índice construído (itens, tempo), e eventuais itens ignorados agregados. Nada por busca (a referência loga cada busca com `Log:info`).
- `warning`/`error` com *rate limit* por chave (mesma mensagem no máximo 1× a cada 60 s) e contador de supressões.
- Nenhum `print` direto fora do `GameLogger`.

### 13.2 Comandos de console (`addConsoleCommand`)

| Comando | Função | Disponível em produção |
|---|---|---|
| `sssStatus` | Estado da máquina (§7.2), versão, tamanho do índice, hooks ativos, falhas | Sim |
| `sssReindex` | Reconstrói o índice e mostra tempo | Sim |
| `sssQuery <texto>` | Executa busca e imprime AST + top 10 com score e `reasons` | Sim |
| `sssExplain <xmlFilename> <texto>` | Explica score de um item específico | Debug |
| `sssDumpCatalog` | Dump do catálogo extraído (§9.4) | Debug |
| `sssBench <n>` | Roda n consultas do corpus embutido e mostra p50/p95 | Debug |

### 13.3 Métricas internas

`Diagnostics` mantém: tempo de build do índice, nº de itens/tokens/trigramas, memória estimada (`collectgarbage("count")` antes/depois), itens ignorados por motivo, p50/p95 das últimas 100 consultas, contagem de falhas por hook.

---

## 14. Localização

- **UI:** `translations/translation_<código>.xml` via `<l10n filenamePrefix="translations/translation"/>`. Idiomas mínimos na 1.0: `en` (obrigatório, fallback), `br` (português brasileiro — prioritário, RF-057), `pt`, `de`, `fr` [A VALIDAR códigos de idioma exatos do FS25 para pt-BR vs. pt-PT].
- **Vocabulário de busca:** `data/<lang>/aliases.xml`, `numbers.xml`, `comparators.xml`. Carregar o idioma do jogo + `en` sempre (jogadores misturam termos em inglês, ex.: "trailer", "baler").
- Os nomes de itens e marcas não são traduzidos pelo jogo; aliases cobrem as variações ("jon dere", "jhon deere").
- Formato de `aliases.xml`:
  ```xml
  <aliases lang="pt">
      <concept kind="category" id="TRACTORS">
          <term>trator</term><term>tratores</term><term>trator agrícola</term>
      </concept>
      <concept kind="brand" id="JOHNDEERE">
          <term>jd</term><term>john deere</term><term>deere</term>
      </concept>
  </aliases>
  ```
  O mapeamento `id` → categoria/marca real do jogo é resolvido em tempo de carga (ids de categoria [A VALIDAR] na Fase 0).

---

## 15. Orçamentos de performance (metas iniciais)

Medidas em PC de referência a definir (Q-05). Valores ajustáveis pela modelagem, mas devem existir desde o primeiro benchmark.

| Métrica | Meta inicial | Onde medir |
|---|---|---|
| Construção do índice, 2.000 itens, sem leitura de XML | ≤ 150 ms total; ≤ 8 ms por frame se fatiada | `sssReindex`, bench |
| Leitura de specs secundárias por XML | ≤ 1 s total, fatiada, fora da abertura da loja | bench em jogo |
| Consulta simples (1–2 termos) | p95 ≤ 5 ms | bench offline e `sssBench` |
| Consulta composta (5+ termos, 2 constraints) | p95 ≤ 15 ms | idem |
| Memória do índice | ≤ 8 MB para 3.000 itens | `collectgarbage("count")` |
| Impacto em FPS com loja fechada | 0 (nenhum `update(dt)` registrado) | inspeção + profiler |

Regras: sem `update(dt)` permanente; sem alocação por item durante consulta além do resultado (reutilizar buffers); strings normalizadas calculadas uma única vez na indexação.

---

## 16. Compatibilidade com outros mods

### 16.1 Estratégia

- Hooks encadeados (append/prepend) e específicos (ADR-03, D6).
- Nenhum campo novo em objetos do jogo; estado do mod em tabelas próprias.
- Action de input própria (`SMART_SHOP_SEARCH`) com tecla padrão sem conflito [A VALIDAR tecla — `F` é usada pela referência].
- Detecção de mods conhecidos que alteram a loja via `g_modIsLoaded[...]`, apenas para **log informativo** e ajustes defensivos — nunca desativar outro mod.

### 16.2 Matriz mínima de testes de release

| Mod / cenário | Motivo |
|---|---|
| `FS25_ShopSearch` (referência) ativo ao mesmo tempo | Coexistência: dois botões/hotkeys, ambos funcionais |
| Enhanced Shop Sorting (w33zl) | Altera ordenação da loja |
| Garage Menu | Já quebrou a referência (issue #5) |
| Vehicle Years (issue #7 da referência) | Adiciona metadados de ano — candidato futuro a spec |
| Mods com `storeItem` incompletos (sem marca, sem categoria válida) | RF-061/062 |
| Pacote com 100+ mods de veículos | Performance e dados heterogêneos |
| Multiplayer: host + cliente; servidor dedicado | P5 |

---

## 17. Conformidade ModHub (checklist técnico)

- [ ] Nome do mod/ZIP `FS25_SmartShopSearch`, apenas `[A-Za-z0-9_]`.
- [ ] `modDesc.xml` com `descVersion` vigente, título/descrição em `en` + idiomas suportados, sem URLs/links na descrição e nos scripts (a própria referência comenta que a GIANTS não aceita links nos scripts).
- [ ] Ícone `.dds` no tamanho exigido [A VALIDAR 512×512, DXT], sem marca d'água de "preview".
- [ ] Sem código ofuscado/compilado; sem `loadstring` de conteúdo externo; sem acesso a rede.
- [ ] Sem dependências obrigatórias.
- [ ] Sem arquivos de desenvolvimento no ZIP.
- [ ] `log.txt` sem erros/avisos do mod nos fluxos do checklist.
- [ ] TestRunner atual aprovado.
- [ ] Funcionamento verificado em SP, MP (host/cliente) e dedicado.
- [ ] Remoção do mod: savegame carrega sem erros e loja normal (RNF-010).
- [ ] Revisão das regras do ModHub vigentes na data da submissão (RMH-011), registrada no checklist com data.

---

## 18. Rastreabilidade (resumo)

A matriz completa `RF/RNF/RMH → módulo → teste` vive em `docs/traceability.md` e é conferida pelo `build.py` (todo id citado nos requisitos precisa aparecer na matriz).

| Requisitos | Módulo principal | Verificação |
|---|---|---|
| RF-001..005 | `ShopGuiAdapter`, `InputAdapter` | Smoke G1–G6, G11, G12 |
| RF-006..011 | `StoreCatalogSource`, `SpecExtractor`, `IndexBuilder` | Golden + dump |
| RF-012..015 | `TextNormalizer`, `Tokenizer`, `Utf8` | Unit + propriedades |
| RF-016..022 | `FuzzyMatcher`, `TrigramIndex` | Unit + golden (`trtor`, `tratro`, `pulverizdor`, negativos) |
| RF-023..025, RF-059 | `AliasResolver`, `data/<lang>` | Unit + golden por idioma |
| RF-026..034 | `NumberParser`, `UnitParser`, `ComparatorParser`, `QueryParser` | Unit (tabela de casos) + golden composto |
| RF-035..036 | `QueryParser`, `SearchService` | Golden (consulta parcialmente compreendida) |
| RF-037..042 | `SearchScorer`, `Ranker` | Unit + métricas do corpus |
| RF-043..047 | `FilterEngine`, facets | Unit + smoke G8 |
| RF-048..050 | `CompatibilityExtractor`, `CompatibilityResolver` | Unit com fixtures de engates + smoke G10 |
| RF-051..052 | `MatchReason`, `ShopGuiAdapter` | Unit (`reasons` sempre preenchido) + smoke G9 |
| RF-053..056 | `ModHubCatalogSource` (condicional) | Relatório da Fase 0 |
| RF-057..058 | `translations/`, `GameLocale` | `build.py` (chaves) |
| RF-060..062, RNF-010 | `SafeCall`, máquina de estados | Unit com falhas injetadas + smoke de remoção |
| RNF-001..003 | `SearchIndex`, bench | Benchmark §15 |
| RNF-005..007 | Arquitetura em camadas, `HookRegistry` | `check_deps.py`, revisão |
| RNF-008..009 | `GameLogger`, `Diagnostics` | Smoke (contagem de linhas de log) |
| RMH-001..011 | `build.py`, TestRunner, checklist | Gate de release |

---

## 19. Plano de execução técnica

O produto 1.0 é o escopo completo (requisitos §3.1 — sem MVP). As fases abaixo são **ordem de construção e de redução de risco**, não versões reduzidas.

| Fase | Entrega | Critério de saída |
|---|---|---|
| **0 — Spike de plataforma** | `docs/api-findings/fs25-<versão>.md` respondendo todos os itens [A VALIDAR] deste PRD e as questões 1–4, 13–15, 18 dos requisitos; protótipo descartável que abre a loja, cria botão, recebe texto, exibe lista ordenada; primeiro `sssDumpCatalog` | Pontos G1–G6, G11–G12 confirmados; dump dos 3 perfis de catálogo gerado; decisão sobre ModHub (RF-053) |
| **1 — Infraestrutura** | Repositório, toolchain, CI, `build.py`, `check_deps.py`, stubs, esqueleto de `main.lua` + `HookRegistry` + `SafeCall` + máquina de estados + logger + comandos `sssStatus/sssReindex` | CI verde; ZIP vazio-funcional carrega sem erros e passa no TestRunner |
| **2 — Núcleo textual** | Utf8, normalizer, tokenizer, índice invertido, exact/prefix, scorer básico, integração GUI ordenada por score | Golden de busca textual e resiliência verdes |
| **3 — Fuzzy e vocabulário** | Trigramas, OSA, limiares, aliases por idioma | Golden de fuzzy verde; benchmark dentro do orçamento |
| **4 — Linguagem estruturada** | Parsers de número/unidade/comparador, AST, specs, filtros, facets | Golden composto verde |
| **5 — GUI avançada** | Busca incremental, painel de filtros, explicações, estado vazio | Smoke G7–G9 |
| **6 — Compatibilidade** | Extração de engates/combinações, consulta contextual | Smoke G10; zero compatibilidade sem evidência |
| **7 — Endurecimento e release** | Matriz de compatibilidade, performance com 100+ mods, traduções, checklist, TestRunner | Definição de pronto (requisitos §25) |

---

## 20. Riscos

| # | Risco | Prob. | Impacto | Mitigação |
|---|---|---|---|---|
| R1 | Patch do FS25 altera a GUI da loja (já ocorreu, D12) | Alta | Alto | Adaptador isolado, guardas de existência, modo `degraded`, smoke a cada patch |
| R2 | Specs não expostas de forma uniforme em mods | Alta | Médio | Extração em camadas; filtros só onde o dado existe; diagnóstico de cobertura por spec |
| R3 | Fuzzy gera falsos positivos em termos curtos | Média | Médio | Limiar por tamanho; corpus negativo; score mínimo relativo |
| R4 | Custo de leitura de XML para specs/compatibilidade | Média | Médio | Fatiamento entre frames, sob demanda, cache por `xmlFilename` |
| R5 | Campo de texto embutido (G7) inviável sem hacks | Média | Médio | Manter `TextInputDialog` como modo suportado (ADR-08) |
| R6 | Conflito com outros mods de loja | Média | Alto | Hooks encadeados/específicos; matriz de compatibilidade |
| R7 | API do ModHub inexistente para mods | Alta | Baixo | ADR-12; documentar limitação (RF-056) |
| R8 | Regras do ModHub mudam | Média | Médio | RMH-011; checklist datado |
| R9 | TestRunner exige Windows e licença do jogo | Certa | Baixo | Gate manual/self-hosted; fora do CI de PR |
| R10 | Questão de licença da referência | Baixa (após ADR-01) | Alto | Clean-room; nenhuma cópia; revisão em PR |
| R11 | Diferenças de comportamento entre Lua 5.1 de referência e o runtime do jogo | Baixa | Médio | Usar só o subconjunto comum; smoke em jogo valida o `core/` também |

---

## 21. Questões em aberto

| # | Questão | Responsável | Quando |
|---|---|---|---|
| Q-01 | Licença do nosso projeto (ex.: MIT para o código, "todos os direitos reservados" para arte) e se o repositório será público | Produto | Antes da Fase 1 |
| Q-02 | Versão alvo do FS25 e `descVersion` correspondente | Técnico | Fase 0 |
| Q-03 | Código de idioma do FS25 para pt-BR e pt-PT | Técnico | Fase 0 |
| Q-04 | Incluir `PLACEABLE` (construções) no escopo de busca? | Produto | Fase 0 |
| Q-05 | Configuração de PC de referência para metas de performance | Técnico | Fase 1 |
| Q-06 | Tecla padrão do atalho (evitar `F` da referência?) | Produto | Fase 0 |
| Q-07 | Onde o repositório será hospedado (GitHub público/privado) e se haverá runner Windows self-hosted | Infra | Fase 1 |
| Q-08 | Existe API suportada para o catálogo online do ModHub? (RF-053) | Técnico | Fase 0 |

Respostas antecipadas às questões obrigatórias dos requisitos (§24), sujeitas à Fase 0:

| Questão dos requisitos | Resposta proposta |
|---|---|
| 5 — Algoritmo fuzzy | Trigramas para candidatos + Damerau-Levenshtein OSA limitado (ADR-05) |
| 6 — Limiar por tamanho | ≤3: 0 · 4–5: 1 · 6–9: 2 · ≥10: 3 (§6.6) |
| 7 — Cálculo do score | Modelo aditivo ponderado por campo/tipo/IDF × cobertura − penalidades (§6.6) |
| 8 — Quando construir o índice | Na primeira abertura da loja após `loadMapFinished` (ADR-04) |
| 9 — Invalidação | Assinatura do catálogo (contagem + hash de `xmlFilename`) a cada abertura; `sssReindex` manual |
| 10 — Localização de aliases | XML por idioma + `en` sempre carregado (§14) |
| 11 — Representação da consulta | AST `Query` (§6.4) |
| 12 — Compatibilidade sem inferência falsa | Somente combinações declaradas e tipos de engate, com evidência no `MatchReason` (§9.3) |
| 16 — Regressão automatizada | busted + corpus golden sobre dumps reais (§11) |
| 17 — TestRunner repetível | `run_testrunner.ps1` + gate de release (§12.3) |
| 18/19 — O que reaproveitar da referência | Tabela §2.3 (conceitos) e §2.4 (o que não reproduzir) |
| 20 — Licença da referência | Sem licença no código principal; libs CC BY-NC-SA 4.0 → clean-room (§2.5) |
