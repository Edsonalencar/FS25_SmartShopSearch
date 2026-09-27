---
date: 2026-09-27T12:29:44-03:00
author: claude
source_prd: docs/PRD-base-tecnica.md
requirements: requisitos.md (v1.1)
git_commit: n/a (repositório ainda não inicializado — criado na Fase 1)
branch: n/a
status: draft
tags: [spec, fs25, lua, core, adapters, gui, search, fuzzy, parser, ranking, modhub]
---

# Spec: FS25 Smart Shop Search 1.0

## Overview

Implementar o mod **FS25_SmartShopSearch** completo (sem MVP, requisitos §3.1) sobre a fundação definida no PRD: arquitetura hexagonal com `core/` Lua 5.1 puro e testável offline, `app/` de orquestração com portas injetadas e `adapters/` finos que são a única camada a tocar o FS25.

Estratégia aprovada: **núcleo offline primeiro**. As Fases 1–4 constroem infraestrutura e todo o motor de busca (texto, fuzzy, vocabulário, linguagem estruturada, filtros) contra um catálogo **sintético** versionado. A Fase 5 (spike em jogo) pode rodar em paralelo a partir do fim da Fase 1 e produz os dumps reais e a validação dos itens `[A VALIDAR]`. As Fases 6–8 ligam o motor ao jogo (GUI básica, GUI avançada, compatibilidade) e a Fase 9 endurece, calibra e prepara a submissão ao ModHub.

Este spec **fecha as lacunas de cobertura** encontradas ao confrontar o PRD com `requisitos.md` (ver "Lacunas do PRD corrigidas") e termina com a **matriz de cobertura completa** (Apêndice A), que é copiada para `docs/traceability.md` e verificada automaticamente pelo `tools/check_trace.py`.

## Current State

- Existem apenas `requisitos.md` (v1.1) e `docs/PRD-base-tecnica.md` (v1.0). Nenhum código, a pasta não é repositório git e não há Makefile nem CI.
- O PRD fixa ADR-01..12, contratos (`IndexedItem`, `Query`, `SearchResult`, `MatchReason`), o modelo de score com valores iniciais, a normalização, as unidades canônicas, a estrutura do repositório e do ZIP, o pipeline de build/CI, a observabilidade e os orçamentos de performance.
- Estação de desenvolvimento: Linux. Jogo/TestRunner: Windows (ou Proton), usados a partir da Fase 5.

## Decisões tomadas nesta etapa

| # | Decisão | Origem |
|---|---|---|
| S-01 | Ordem: núcleo offline (F1–F4) antes do spike; spike (F5) paralelizável após F1 | Usuário |
| S-02 | Licença: **MIT** para o código (`LICENSE`); ícone/arte com todos os direitos reservados (`LICENSE-ART.md`) — responde Q-01 | Usuário |
| S-03 | `PLACEABLE` entra no escopo **se** a F5 confirmar que `makeDisplayItem`/`pageShopItemDetails` exibem placeables sem erro; senão fica registrado em `docs/api-limitations.md` — responde Q-04 | Usuário |
| S-04 | GitHub + Actions: job Linux em todo PR; job Windows `workflow_dispatch`/tags `v*` para TestRunner (runner self-hosted opcional; sem ele, execução local do mesmo script) — responde Q-07 | Usuário |
| S-05 | Tecla padrão `KEY_lctrl KEY_f` na action `SMART_SHOP_SEARCH`. A F5 verifica se há conflito com os bindings padrão do FS25 e, se houver, usa `KEY_lalt KEY_f` — responde Q-06 | Spec |
| S-06 | Códigos de idioma: `br` → vocabulário `data/pt`, `pt` → `data/pt`, demais → `data/<code>` se existir; `en` sempre carregado. A F5 confirma os códigos reais (Q-03) e só altera a tabela `GameLocale.LANG_MAP` | Spec |
| S-07 | Q-02 (versão/`descVersion`), Q-05 (PC de referência) e Q-08 (API do ModHub) são **entregáveis da F5/F9** com regra de decisão definida, não questões abertas deste spec | Spec |

## Lacunas do PRD corrigidas por este spec

| # | Lacuna | Requisito | Correção (fase) |
|---|---|---|---|
| L1 | RNF-004 (offline-first) não tem verificação na rastreabilidade | RNF-004, RMH-010 | `check_deps.py` proíbe em `src/` qualquer uso de rede/HTTP, `loadstring`/`load` de conteúdo externo, `io.`, `os.execute`; linha própria na matriz (F1) |
| L2 | Falta registro formal de funcionalidades "indisponíveis por limitação comprovada" | DoD §25.3, RF-056, princípio 3.9 | `docs/api-limitations.md` + `check_trace.py` exige que todo requisito condicional esteja `implemented` ou `unavailable` com evidência (F1, preenchido F5/F9) |
| L3 | "Limpar pesquisa" do PRD (G12) só faz `popDetail`, não zera filtros | RF-004 | `SearchState:clear()` zera texto, filtros de UI, contexto de compatibilidade e restaura a categoria anterior (F6) |
| L4 | RF-049 só tem via GUI; parser não prevê frases de compatibilidade | RF-049 | `ContextParser` reconhece "compatível(eis) com …", "para este trator" → `Query.context` (F4); resolução em F8 |
| L5 | Critérios de aceitação §21 não enumerados como casos | §21 | 38 critérios com ID `AC-*` (Apêndice A.4), cada um com caso golden, unit ou smoke nominal; `check_trace.py` exige cobertura (F1+) |
| L6 | Limiar "≤3 chars: só exato" impede `jon dere` → John Deere (`jon` tem 3) | RF-020, AC-FUZ-03 | **Fuzzy de frase**: janelas de 2–3 tokens comparadas contra frases do vocabulário (marcas/categorias/aliases multi-palavra) com limiar pelo comprimento da frase (F3) |
| L7 | Palavras funcionais ("por", "de", "com") poluem termos | RF-034/036 | `data/<lang>/stopwords.xml` aplicado apenas aos tokens remanescentes (F4) |
| L8 | Símbolos monetários (`R$`, `$`, `€`) seriam apagados pela regra "pontuação → espaço" | RF-029 | Normalizer isola símbolos monetários e sequências protegidas (`km/h`, `m³`) configuradas por dados antes da regra de pontuação (F2) |
| L9 | Constraint sem unidade (`menos de 150 mil`) não tem regra de atribuição | RF-029/032 | Regra determinística no `QueryParser` (F4, §4.5) |
| L10 | Unidade de potência ambígua entre `power` (trator) e `neededPower` (implemento) | RF-027, RF-046 | Constraint referencia **grandeza**; `units.xml` declara a lista ordenada de specs por grandeza; `FilterEngine` usa a primeira spec presente no item (F4) |
| L11 | Score "0..1" sem definição do denominador; o caso negativo `expectMaxScore 0.2` fica sem sentido | RF-037/042, AC-FUZ-06 | Score normalizado pelo máximo teórico da consulta (F2, §2.6) |
| L12 | Golden depende de dumps que só existem após a F5 | §11.2 PRD | Catálogo sintético `tests/fixtures/catalog/synthetic.xml` (F2); dumps reais somam-se na F9 sem alterar os casos |
| L13 | Itens do §2.3 dos requisitos (teclado/input, conflitos, limitações da referência) não têm entregável explícito da F5 | Req. §2.3, Q18/Q19 | Seções obrigatórias no template `docs/api-findings/fs25-<ver>.md` (F5) |

## Desired End State

1. Repositório git com `src/` = conteúdo exato do ZIP; `make ci` verde em Linux (formato, lint, dependências, rastreabilidade, unit, propriedades, golden, bench, build/verify).
2. `dist/FS25_SmartShopSearch-1.0.0.zip` aprovado no TestRunner vigente, sem erros do mod no `log.txt` nos fluxos do `docs/release-checklist.md`.
3. Na loja: botão e hotkey configurável abrem a busca; os resultados aparecem ordenados por score numa categoria virtual; há busca incremental (ou a limitação está registrada), painel de filtros (categoria, marca, preço, specs, origem, espécie), explicações opcionais, estado vazio, "limpar" e "compatíveis com este veículo".
4. A consulta `trtor jon dere entre 200 e 300 cv por menos de 150 mil` produz `category≈TRACTORS*`, `brand≈JOHNDEERE`, `power ∈ [147.1, 220.7] kW`, `price < 150000`, `terms=[]`, e retorna tratores John Deere da faixa com `reasons` explicáveis.
5. Qualquer falha põe o mod em `degraded` e a loja original continua 100% funcional. Remover o mod não deixa rastro no savegame.
6. `docs/traceability.md` cobre 100% dos RF/RNF/RMH/AC; `docs/api-limitations.md` classifica cada funcionalidade condicional; `docs/api-findings/fs25-<ver>.md` responde todos os `[A VALIDAR]` e as questões 1–4, 13–15 e 18–20 dos requisitos.

## What We're NOT Doing

- **Copiar código de `w33zl/FS25_ShopSearch` ou da Weezls Mod Lib** — ADR-01 (sem licença / CC BY-NC-SA).
- **Sincronização multiplayer, eventos de rede, dados em savegame** — ADR-09/10; o mod é client-side.
- **Acesso a rede, scraping ou hacks para o ModHub** — RF-056; se não houver API suportada, a limitação é documentada.
- **Suporte a consoles** — mods com script não são aceitos em console (P4); a F5 confirma na política vigente.
- **Tradução de nomes de itens/marcas** — o jogo não os traduz; aliases cobrem as variações.
- **Busca fonética (Soundex/Metaphone)** — ADR-05.
- **Inferência de compatibilidade por texto** — RF-050.
- **Conteúdo exaustivo de dicionários** — a 1.0 entrega o vocabulário necessário ao corpus golden, mais as categorias e marcas do jogo base. A ampliação é só de dados, sem código.
- **Recarregar scripts a quente em jogo** — não suportado pelo FS25 (§10.2 PRD).

---

## Convenções gerais (valem para todas as fases)

- **Lua 5.1 estrito** em `src/`: sem `goto`, `//`, bitwise, `utf8.*`, `require`, `io`, `os.execute`. Tudo é `local`, exceto o global `SmartShopSearch`.
- **Registro de módulo** (padrão único, usado pelo jogo via `source()` e pelos testes via `dofile`):
  ```lua
  -- src/core/text/Tokenizer.lua
  local NS = SmartShopSearch
  local Tokenizer = {}
  -- ... implementação ...
  NS.core.Tokenizer = Tokenizer
  ```
  Um módulo acessa outro por `NS.core.X` **em tempo de chamada** ou, no topo do arquivo, apenas se `X` vier antes no manifesto.
- **Manifesto único de carga** `src/manifest.lua` (ordem fixa). Ele é lido por `main.lua`, por `tests/support/load.lua` e pelo `build.py`.
- Anotações LuaLS `---@class` em todos os modelos. `types/fs25.lua` declara os globais do jogo usados pelos adapters.
- Comandos: todo passo automatizado é um alvo do `Makefile` criado na F1.
- Chaves de tradução: prefixo `sss_`. Logs: prefixo `[SmartShopSearch]`.

---

## Phase 1: Infraestrutura e esqueleto

### Goal
Repositório, toolchain, CI, build/verify, lints de arquitetura e rastreabilidade, e um esqueleto de mod que carrega no jogo sem erros (quando testado na F5) com máquina de estados, `SafeCall`, `HookRegistry`, logger e comandos `sssStatus`/`sssReindex`.

### Changes

#### Repositório e toolchain

**Create**: `.gitignore`
```gitignore
/dist/
/.lua/
/.luarocks/
*.zip
/spike/**/dumps/
.vscode/*
!.vscode/settings.json
```

**Create**: `tools/setup_dev.sh` — instala Lua 5.1 local com hererocks, mais busted/luacheck. O StyLua é binário do sistema.
```bash
#!/usr/bin/env bash
set -euo pipefail
python3 -m pip install --user hererocks
hererocks .lua -l5.1 -rlatest
.lua/bin/luarocks install busted
.lua/bin/luarocks install luacheck
command -v stylua >/dev/null || echo "Instale StyLua: cargo install stylua  (ou release binária)"
```

**Create**: `Makefile`
```make
LUA      ?= .lua/bin/lua
BUSTED   ?= .lua/bin/busted
LUACHECK ?= .lua/bin/luacheck
PY       ?= python3

.PHONY: setup fmt fmt-check lint deps trace test unit golden prop bench build verify ci
setup:     ; ./tools/setup_dev.sh
fmt:       ; stylua src tests tools
fmt-check: ; stylua --check src tests
lint:      ; $(LUACHECK) src tests
deps:      ; $(PY) tools/check_deps.py
trace:     ; $(PY) tools/check_trace.py
unit:      ; $(BUSTED) --lua=$(LUA) tests/unit
prop:      ; $(BUSTED) --lua=$(LUA) tests/prop
golden:    ; $(BUSTED) --lua=$(LUA) tests/golden
test: unit prop golden
bench:     ; $(LUA) tests/bench/run.lua --compare tests/bench/baseline.lua
build:     ; $(PY) tools/build.py
verify:    ; $(PY) tools/build.py --verify
ci: fmt-check lint deps trace test bench verify
```

**Create**: `.luacheckrc`
```lua
std = "lua51"
allow_defined_top = false
max_line_length = 120
globals = { "SmartShopSearch" }
files["src/adapters"] = { read_globals = dofile("tools/fs25_globals.lua") }
files["src/main.lua"] = { read_globals = dofile("tools/fs25_globals.lua") }
files["tests"] = { std = "+busted", globals = { "SmartShopSearch" } }
```

**Create**: `tools/fs25_globals.lua` — lista somente-leitura dos globais do FS25 usados, que cresce conforme os adapters: `g_storeManager`, `g_shopController`, `g_shopMenu`, `g_modManager`, `g_brandManager`, `g_i18n`, `g_inputBinding`, `g_gui`, `g_dedicatedServer`, `g_currentModDirectory`, `g_currentModName`, `g_modSettingsDirectory`, `g_languageShort`, `g_modIsLoaded`, `ShopMenu`, `TabbedMenuWithDetails`, `TextInputDialog`, `Utils`, `XMLFile`, `StoreSpecies`, `InputAction`, `addModEventListener`, `addConsoleCommand`, `removeConsoleCommand`, `source`, `getTimeSec`, `Logging`, `createFolder`.

**Create**: `.stylua.toml` (`column_width = 120`, `indent_type = "Spaces"`, `indent_width = 4`, `quote_style = "AutoPreferDouble"`), `.editorconfig`, `.luarc.json` (`runtime.version = "Lua 5.1"`, `workspace.library = ["types"]`).

**Create**: `LICENSE` (MIT, titular "FS25 Mods Editor"), `LICENSE-ART.md` (ícone e arte: todos os direitos reservados), `README.md` (uso, build, seção "Agradecimentos" citando `FS25_ShopSearch` como inspiração, sem código derivado), `CHANGELOG.md` (entrada `1.0.0 — não lançado`), `docs/THIRD_PARTY.md` ("Nenhum código de terceiros incorporado. Referência técnica: w33zl/FS25_ShopSearch @ d4166f7, usada apenas para identificar APIs do jogo, ADR-01").

**Create**: `docs/adr/0001-clean-room.md` … `docs/adr/0012-modhub-catalog-source.md` — um arquivo por ADR do PRD §4 (Status: Aceito; Contexto; Decisão; Consequências). Também `docs/adr/0013-offline-core-first.md` (S-01) e `docs/adr/0014-phrase-fuzzy.md` (L6).

#### Rastreabilidade e limitações

**Create**: `docs/traceability.md` — cópia do Apêndice A deste spec. Formato de linha **obrigatório** para o parser:
```markdown
| RF-016 | FuzzyMatcher, TrigramIndex | unit:fuzzy_spec, golden:fuzzy-trtor | F3 |
```

**Create**: `docs/api-limitations.md`
```markdown
# Funcionalidades condicionais (requisitos §3.9, §25.3)

| Id | Funcionalidade | Status | Evidência | Data/versão FS25 |
|---|---|---|---|---|
| RF-002 | Atalho configurável | pending | | |
| RF-009 | Busca por nome do mod | pending | | |
| RF-010 | Busca por autor | pending | | |
| RF-011 | Specs pesquisáveis | pending | | |
| RF-046 | Specs como filtros | pending | | |
| RF-047 | Origem base/DLC/mod | pending | | |
| RF-048 | Relações de compatibilidade | pending | | |
| RF-052 | Exibição de explicações | pending | | |
| RF-053 | Investigação ModHub | pending | | |
| RF-054 | Integração ModHub | pending | | |
| G7 | Busca incremental embutida | pending | | |
| S-03 | Placeables | pending | | |
```
Valores válidos de `Status`: `pending` | `implemented` | `unavailable`. `unavailable` exige a coluna Evidência preenchida (link para a seção de `api-findings`).

**Create**: `tools/check_trace.py`
```python
"""Falha se algum requisito não está rastreado ou se há condicionais pendentes em modo release."""
import re, sys, pathlib
ROOT = pathlib.Path(__file__).resolve().parents[1]
REQ = (ROOT / "requisitos.md").read_text(encoding="utf-8")
TRACE = (ROOT / "docs/traceability.md").read_text(encoding="utf-8")
LIMITS = (ROOT / "docs/api-limitations.md").read_text(encoding="utf-8")
ID = re.compile(r"\b(RF|RNF|RMH)-\d{3}\b")

def ids(text): return {m.group(0) for m in ID.finditer(text)}
def rows(text):
    out = {}
    for line in text.splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) >= 3 and re.match(r"^(RF|RNF|RMH|AC|QM|DOD|DEL|PR|REF)-", cells[0]):
            out[cells[0]] = cells
    return out

errors = []
trace = rows(TRACE)
for rid in sorted(ids(REQ)):
    if rid not in trace: errors.append(f"{rid} ausente em docs/traceability.md")
for rid, cells in trace.items():
    if not cells[2] or cells[2] == "-": errors.append(f"{rid} sem verificação")
if "--release" in sys.argv:
    for line in LIMITS.splitlines():
        c = [x.strip() for x in line.strip().strip("|").split("|")]
        if len(c) >= 4 and c[2] == "pending": errors.append(f"{c[0]} ainda pending em api-limitations.md")
        if len(c) >= 4 and c[2] == "unavailable" and not c[3]: errors.append(f"{c[0]} unavailable sem evidência")
print("\n".join(errors) or "traceability OK")
sys.exit(1 if errors else 0)
```
Na F1 as linhas `AC-*`, `QM-*`, `DOD-*`, `DEL-*`, `PR-*` e `REF-*` também são checadas quanto à presença: a lista esperada fica fixa em `tools/trace_expected.txt`, gerada a partir do Apêndice A.

#### Lints de arquitetura e offline-first (L1)

**Create**: `tools/check_deps.py`
```python
import re, sys, pathlib
SRC = pathlib.Path(__file__).resolve().parents[1] / "src"
CORE_FORBIDDEN = [r"\bg_[A-Za-z]", r"\bShopMenu\b", r"\bUtils\.", r"\bXMLFile\b", r"\bgetXML",
                  r"\bsource\s*\(", r"\bprint\s*\(", r"adapters[/.]", r"\bos\.", r"\bio\."]
APP_FORBIDDEN = [r"\bg_[A-Za-z]", r"\bShopMenu\b", r"\bXMLFile\b", r"adapters[/.]", r"\bio\."]
ALL_FORBIDDEN = [r"\bloadstring\s*\(", r"\bload\s*\(", r"\bdofile\s*\(", r"\brequire\s*\(",
                 r"\bos\.execute", r"\bio\.", r"https?://", r"\bsocket\b", r"\bHTTP", r"\bgoto\b",
                 r"//", r"\butf8\."]
def scan(glob, patterns, label, errors):
    for f in SRC.glob(glob):
        for n, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
            code = line.split("--", 1)[0]
            for p in patterns:
                if re.search(p, code): errors.append(f"{f.relative_to(SRC)}:{n}: [{label}] {p}")
errors = []
scan("core/**/*.lua", CORE_FORBIDDEN, "core-purity", errors)
scan("app/**/*.lua", APP_FORBIDDEN, "app-purity", errors)
scan("**/*.lua", ALL_FORBIDDEN, "offline/lua51", errors)
print("\n".join(errors) or "deps OK"); sys.exit(1 if errors else 0)
```
Remover comentários antes do regex evita falso positivo com `//` em comentários. Strings com `//` são proibidas em `src/`, o que também cobre URLs, vedadas pelo ModHub.

#### Build e verificação do pacote

**Create**: `tools/build.py` — implementa o §12.2 do PRD, mais:
- `--verify`: executa as validações sem gravar em `dist/` e, em seguida, faz o build num diretório temporário e o reabre (contagem + SHA-256 por arquivo).
- Validação do `modDesc.xml` (via `xml.etree`): raiz `modDesc` com `descVersion`; `author`, `version` (regex `^\d+\.\d+\.\d+\.\d+$`), `title/en`, `title/br` ou `title/pt`, `description/en`, `iconFilename` existente, `multiplayer supported="true"`, `l10n filenamePrefix`, `extraSourceFiles/sourceFile filename="main.lua"` único, `actions/action name="SMART_SHOP_SEARCH"`, `inputBinding/actionBinding action="SMART_SHOP_SEARCH"`.
- Proíbe URLs (`http`, `www.`) em `description` e em qualquer `.lua` (conformidade §17 PRD).
- Lê `src/manifest.lua` por regex (`"([%w_/]+%.lua)"`) e exige: todo arquivo listado existe; todo `.lua` de `src/` (exceto `main.lua` e `manifest.lua`) está listado.
- Traduções: coleta `sss_[a-z0-9_]+` usados em `src/**/*.lua` e `gui/*.xml`; falha se faltar em `translation_en.xml`; avisa por idioma.
- Allowlist de extensões `.lua .xml .dds .ogg .i3d .i3d.shapes`; nome `FS25_SmartShopSearch.zip`; caminhos com `/`; sem diretórios vazios; gera `dist/FS25_SmartShopSearch-<versão>.zip` + `dist/SHA256SUMS`.
- Checa `CHANGELOG.md` com cabeçalho `## <versão semver>`.
- `--release`: executa também `check_trace.py --release`, que exige nenhuma condicional `pending`.

#### Esqueleto do mod

**Create**: `src/modDesc.xml`
```xml
<?xml version="1.0" encoding="utf-8" standalone="no"?>
<modDesc descVersion="96">
    <author>FS25 Mods Editor</author>
    <version>1.0.0.0</version>
    <title>
        <en>Smart Shop Search</en>
        <br>Pesquisa Inteligente da Loja</br>
    </title>
    <description>
        <en><![CDATA[Smart search for the shop: typo tolerance, brands, categories, specs, prices and ranges.]]></en>
        <br><![CDATA[Pesquisa inteligente na loja: tolera erros de digitação, marcas, categorias, especificações, preços e faixas.]]></br>
    </description>
    <iconFilename>icon_SmartShopSearch.dds</iconFilename>
    <multiplayer supported="true"/>
    <l10n filenamePrefix="translations/translation"/>
    <extraSourceFiles>
        <sourceFile filename="main.lua"/>
    </extraSourceFiles>
    <actions>
        <action name="SMART_SHOP_SEARCH" category="ONFOOT VEHICLE" axisType="HALF"/>
    </actions>
    <inputBinding>
        <actionBinding action="SMART_SHOP_SEARCH">
            <binding device="KB_MOUSE_DEFAULT" input="KEY_lctrl KEY_f"/>
        </actionBinding>
    </inputBinding>
</modDesc>
```
`descVersion` e `category` da action serão confirmados na F5 (Q-02). O `<br>` dentro de `title` segue a convenção de código de idioma do FS e também é confirmado na F5 (S-06).

**Create**: `src/manifest.lua`
```lua
-- Ordem de carga fixa. Lida por main.lua, tests/support/load.lua e tools/build.py.
SmartShopSearch.manifest = {
    "core/util/Table.lua",
    "core/util/Hash.lua",
    "core/model/Models.lua",
    -- F2+: core/text, core/index, core/match, core/rank
    -- F3+: core/lang/AliasResolver.lua, core/index/TrigramIndex.lua, core/match/FuzzyMatcher.lua
    -- F4+: core/lang/*Parser.lua, core/rank/FilterEngine.lua
    -- F8 : core/compat/CompatibilityResolver.lua
    "app/SafeCall.lua",
    "app/StateMachine.lua",
    "app/Diagnostics.lua",
    "app/IndexLifecycle.lua",
    "app/SearchService.lua",
    "app/Console.lua",
    "adapters/GameLogger.lua",
    "adapters/HookRegistry.lua",
    "adapters/SettingsStore.lua",
    "adapters/GameLocale.lua",
    "adapters/GameBootstrap.lua",
}
```

**Create**: `src/main.lua`
```lua
-- FS25_SmartShopSearch — ponto de entrada único (extraSourceFiles)
local MOD_DIR = g_currentModDirectory
local MOD_NAME = g_currentModName

SmartShopSearch = {
    MOD_DIR = MOD_DIR,
    MOD_NAME = MOD_NAME,
    VERSION = "1.0.0",
    core = {}, app = {}, adapters = {}, data = {},
}

source(MOD_DIR .. "manifest.lua")
for _, rel in ipairs(SmartShopSearch.manifest) do
    source(MOD_DIR .. rel)
end

SmartShopSearch.adapters.GameBootstrap.install(SmartShopSearch)
```

**Create**: `src/app/SafeCall.lua`
```lua
local NS = SmartShopSearch
local SafeCall = { failures = {}, maxFailures = 3 }

--- Executa fn protegida; em falha registra, conta e devolve nil.
---@param context string  identificador estável ("hook:ShopMenu.onOpen")
function SafeCall.run(context, fn, ...)
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
    local n = (SafeCall.failures[context] or 0) + 1
    SafeCall.failures[context] = n
    local log = NS.app.logger
    if log then log:error("safecall", "%s falhou (%d): %s", context, n, tostring(a)) end
    if n >= SafeCall.maxFailures and NS.app.state then
        NS.app.state:degrade("falhas repetidas em " .. context)
    end
    return nil
end

NS.app.SafeCall = SafeCall
```

**Create**: `src/app/StateMachine.lua` — estados `loaded → ready → indexed`, mais `degraded`, `disabled-dedicated` e `unloaded`. Transições inválidas são ignoradas com `debug` no log. `degrade(reason)` é idempotente, grava `reason` e loga **uma** linha `error`. Listeners `onChange(fn)` notificam o adapter de GUI para ocultar botão e hotkey.
```lua
local NS = SmartShopSearch
local StateMachine = {}
StateMachine.__index = StateMachine
local ALLOWED = {
    loaded = { ready = true, ["disabled-dedicated"] = true, degraded = true, unloaded = true },
    ready = { indexed = true, degraded = true, unloaded = true },
    indexed = { indexed = true, degraded = true, unloaded = true, ready = true },
    degraded = { unloaded = true },
    ["disabled-dedicated"] = { unloaded = true },
}
function StateMachine.new(logger)
    return setmetatable({ current = "loaded", reason = nil, logger = logger, listeners = {} }, StateMachine)
end
function StateMachine:set(to)
    if not (ALLOWED[self.current] or {})[to] then
        self.logger:debug("state", "transição ignorada %s→%s", self.current, to)
        return false
    end
    self.current = to
    for _, fn in ipairs(self.listeners) do pcall(fn, to) end
    return true
end
function StateMachine:degrade(reason)
    if self.current == "degraded" then return end
    self.reason = reason
    self.logger:error("state", "modo degradado: %s", reason)
    self:set("degraded")
end
function StateMachine:is(s) return self.current == s end
function StateMachine:onChange(fn) self.listeners[#self.listeners + 1] = fn end
NS.app.StateMachine = StateMachine
```

**Create**: `src/adapters/GameLogger.lua` — implementa a porta `Logger` (`error/warning/info/debug(key, fmt, ...)`). Usa `Logging.info/warning/error` se existirem [A VALIDAR na F5] e `print` como fallback, com prefixo `[SmartShopSearch]`. Rate limit por `key..fmt` de 60 s, com contagem de supressões emitida na próxima linha permitida. O nível vem de `SettingsStore` (padrão `info`). Relógio: `getTimeSec` se existir, senão `os.clock` **apenas neste adapter**.

**Create**: `src/adapters/HookRegistry.lua` (ADR-03)
```lua
local NS = SmartShopSearch
local HookRegistry = { hooks = {}, enabled = true }

---@param spec {id:string, target:table, method:string, kind:"append"|"prepend"|"overwrite", fn:function}
function HookRegistry.add(spec)
    if HookRegistry.hooks[spec.id] then return true end -- idempotente
    local target = spec.target
    if type(target) ~= "table" or type(target[spec.method]) ~= "function" then
        NS.app.logger:warning("hook", "alvo ausente: %s", spec.id)
        return false
    end
    local entry = { id = spec.id, active = true, failures = 0 }
    local body = spec.fn
    local function guarded(...)
        if not (HookRegistry.enabled and entry.active) or NS.app.state:is("degraded") then return end
        local ok, err = pcall(body, ...)
        if not ok then
            entry.failures = entry.failures + 1
            NS.app.logger:error("hook", "%s: %s", spec.id, tostring(err))
            if entry.failures >= 3 then entry.active = false end
        end
    end
    if spec.kind == "append" then
        target[spec.method] = Utils.appendedFunction(target[spec.method], guarded)
    elseif spec.kind == "prepend" then
        target[spec.method] = Utils.prependedFunction(target[spec.method], guarded)
    else -- overwrite: body recebe (self, superFunc, ...) e DEVE chamar superFunc; em falha chama superFunc
        target[spec.method] = Utils.overwrittenFunction(target[spec.method], function(self, superFunc, ...)
            if not (HookRegistry.enabled and entry.active) or NS.app.state:is("degraded") then
                return superFunc(self, ...)
            end
            local res = { pcall(body, self, superFunc, ...) }
            if res[1] then return unpack(res, 2) end
            entry.failures = entry.failures + 1
            NS.app.logger:error("hook", "%s: %s", spec.id, tostring(res[2]))
            if entry.failures >= 3 then entry.active = false end
            return superFunc(self, ...)
        end)
    end
    HookRegistry.hooks[spec.id] = entry
    return true
end

function HookRegistry.uninstall() HookRegistry.enabled = false end -- lógico (§7.1 passo 12)
function HookRegistry.status()
    local out = {}
    for id, e in pairs(HookRegistry.hooks) do out[#out + 1] = { id = id, active = e.active, failures = e.failures } end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end
NS.adapters.HookRegistry = HookRegistry
```
Observação: o `overwrite` com falha de `body` chama `superFunc` de novo apenas se `body` falhou **antes** de chamá-lo. Para garantir isso, o `body` de overwrite deve chamar `superFunc` na primeira linha e guardar o retorno. Essa regra fica registrada como comentário e é verificada em revisão.

**Create**: `src/adapters/GameBootstrap.lua` — `install(NS)`: cria `logger`, `state`, `settings`, e chama `addModEventListener(listener)`. O listener implementa:
- `loadMap()`: se `g_dedicatedServer ~= nil`, estado `disabled-dedicated` e retorna. Senão carrega settings, `GameLocale`, dados linguísticos (a partir da F3), registra comandos de console e instala os hooks de loja (a partir da F6). Estado `ready`. Loga **uma** linha `info`: "v1.0.0 carregado".
- `deleteMap()`: `HookRegistry.uninstall()`, remove comandos de console, `IndexLifecycle:release()`, estado `unloaded`.
- Tudo dentro de `SafeCall.run("bootstrap:<evento>", ...)`. Uma falha no bootstrap chama `state:degrade`.

**Create**: `src/adapters/SettingsStore.lua` — lê `g_modSettingsDirectory .. "FS25_SmartShopSearch/settings.xml"` [A VALIDAR nome do global na F5] com `XMLFile.loadIfExists`. Chaves: `debug#enabled`, `debug#logLevel`, `ui#showReasons` (padrão `false`), `ui#incremental` (padrão `true`), `search#maxResults` (padrão `300`). Grava somente quando o usuário altera preferências. Nunca escreve dentro do pacote (§10.3 PRD).

**Create**: `src/adapters/GameLocale.lua` — `LANG_MAP = { br = "pt", pt = "pt", en = "en", de = "de", fr = "fr" }`; `current()` lê `g_languageShort` [A VALIDAR]; `dataLocales()` retorna `{mapped, "en"}` sem duplicatas (S-06).

**Create**: `src/app/Console.lua` — registra `sssStatus` e `sssReindex` via a porta `ConsoleRegistrar`, implementada por um adapter fino dentro de `GameBootstrap` que usa `addConsoleCommand`. `sssStatus` imprime estado, motivo de degradação, versão, tamanho do índice, `HookRegistry.status()` e `SafeCall.failures`.

**Create**: `src/app/Diagnostics.lua`, `src/app/IndexLifecycle.lua`, `src/app/SearchService.lua` — stubs com a API final documentada (implementação na F2).

**Create**: `src/core/util/Table.lua` (`copyShallow`, `keys`, `sortedKeys`, `contains`), `src/core/util/Hash.lua` (hash determinístico sem bitops):
```lua
local NS = SmartShopSearch
local Hash = {}
local MOD = 2147483647
function Hash.string(s, h)
    h = h or 5381
    for i = 1, #s do h = (h * 33 + string.byte(s, i)) % MOD end
    return h
end
NS.core.Hash = Hash
```

**Create**: `src/core/model/Models.lua` — anotações LuaLS de `RawItem`, `IndexedItem`, `IndexedField`, `SpecValue`, `Query`, `QueryTerm`, `QueryConcept`, `Constraint`, `QueryContext`, `UiFilters`, `SearchResult`, `MatchReason`, `CompatInfo` (§6 PRD, com os acréscimos deste spec em §2.2, §4.4 e §8.1), mais construtores `Models.result()` e `Models.reason()`.

**Create**: `src/translations/translation_en.xml`, `translation_br.xml`, `translation_pt.xml`, `translation_de.xml`, `translation_fr.xml` com as chaves iniciais: `input_SMART_SHOP_SEARCH`, `sss_button_search`, `sss_dialog_title`, `sss_results_header`, `sss_results_empty`, `sss_clear`, `sss_state_degraded`.

**Create**: `src/icon_SmartShopSearch.dds` gerado por `tools/make_icon.sh` (ImageMagick: `convert art/icon.png -resize 512x512 -define dds:compression=dxt5 src/icon_SmartShopSearch.dds`). A fonte fica em `art/icon.png`, fora do pacote. O tamanho final é validado na F5.

#### Testes: suporte

**Create**: `tests/support/load.lua`
```lua
-- Carrega o mod fora do jogo, na mesma ordem do manifesto, apenas core/ e app/.
local M = {}
function M.load(opts)
    opts = opts or {}
    SmartShopSearch = { MOD_DIR = "src/", VERSION = "test", core = {}, app = {}, adapters = {}, data = {} }
    dofile("src/manifest.lua")
    for _, rel in ipairs(SmartShopSearch.manifest) do
        if rel:match("^core/") or rel:match("^app/") then dofile("src/" .. rel) end
    end
    return SmartShopSearch
end
return M
```
**Create**: `tests/support/xml.lua` — parser XML mínimo em Lua 5.1 (elementos, atributos, texto, CDATA, entidades básicas) usado **somente** para carregar `src/data/**` e fixtures/golden nos testes. Em jogo, o equivalente é o adapter `XmlDataLoader` (F3).
**Create**: `tests/stubs/MemoryLogger.lua`, `tests/stubs/FakeClock.lua`, `tests/stubs/FixtureCatalogSource.lua` (lê fixture XML → `RawItem[]`).
**Create**: `tests/unit/app_spec.lua` — StateMachine (transições válidas/ inválidas, `degrade` idempotente com 1 linha de log), SafeCall (captura erro, conta falhas, degrada após 3).

#### CI

**Create**: `.github/workflows/ci.yml`
```yaml
name: ci
on: [push, pull_request]
jobs:
  quality:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: leafo/gh-actions-lua@v10
        with: { luaVersion: "5.1" }
      - uses: leafo/gh-actions-luarocks@v4
      - run: luarocks install busted && luarocks install luacheck
      - uses: JohnnyMorganz/stylua-action@v4
        with: { token: "${{ secrets.GITHUB_TOKEN }}", version: latest, args: --check src tests }
      - uses: actions/setup-python@v5
        with: { python-version: "3.11" }
      - run: make lint deps trace test bench verify LUA=lua BUSTED=busted LUACHECK=luacheck
      - uses: actions/upload-artifact@v4
        with: { name: mod-zip, path: dist/*.zip }
  testrunner:
    if: startsWith(github.ref, 'refs/tags/v') || github.event_name == 'workflow_dispatch'
    runs-on: [self-hosted, windows]
    needs: quality
    steps:
      - uses: actions/checkout@v4
      - run: python tools/build.py --release
      - run: pwsh tools/run_testrunner.ps1 -Zip (Get-ChildItem dist/*.zip | Select-Object -First 1).FullName
```
Adicionar `workflow_dispatch:` a `on`. Sem runner self-hosted, o job fica pendente e o mesmo script é executado localmente (S-04).

**Create**: `tools/run_testrunner.ps1` — parâmetros `-Zip`, `-TestRunnerPath` (padrão `$env:FS25_TESTRUNNER`), `-OutDir dist/testrunner/<versão>`. Executa o TestRunner com o ZIP e arquiva o relatório. Retorna código ≠ 0 se o relatório contiver erros. A linha de comando exata do TestRunner é confirmada na F5 e fica registrada em `api-findings`.

**Create**: `tools/dev_link.sh` e `tools/dev_link.ps1` — link de `src/` para `<Documents>/My Games/FarmingSimulator2025/mods/FS25_SmartShopSearch`.

**Create**: `docs/release-checklist.md` — esqueleto com as seções Smoke G1–G12, Matriz §16, Conformidade §17, TestRunner, Remoção do mod, Revisão das regras do ModHub (com data), DoD §25 (itens `DOD-01..10`).

**Command**: `git init && git add -A && git commit` (mensagem conforme a skill `/commit` do projeto), após `make ci` verde.

### Success Criteria

#### Automated Verification
- [x] `make setup` instala Lua 5.1, busted e luacheck localmente. (feito via hererocks + luarocks; StyLua via release binária — sem cargo disponível)
- [x] `make fmt-check lint` passa.
- [x] `make deps` passa. Um arquivo temporário `src/core/x.lua` com `g_storeManager` faz o comando falhar (teste manual do lint, depois apagar).
- [x] `make trace` passa com todos os `RF/RNF/RMH` presentes em `docs/traceability.md`.
- [x] `make unit` passa (`app_spec`).
- [x] `make verify` gera o ZIP em diretório temporário e valida o `modDesc.xml`, o manifesto, as traduções e a allowlist.
- [ ] CI do GitHub verde no primeiro push. — **não aplicável neste ambiente**: sem remoto GitHub configurado/push feito; além disso `make ci` só fecha totalmente a partir da F2 (tests/prop, tests/golden e tests/bench ainda não existem na F1).

#### Manual Verification
- [ ] Ler `docs/traceability.md` e confirmar que ele espelha o Apêndice A.
- [ ] Conferir o conteúdo do ZIP (`unzip -l`): somente `modDesc.xml`, ícone, `main.lua`, `manifest.lua`, `core/`, `app/`, `adapters/`, `translations/`.

**⏸ PAUSE**: após a verificação automática, aguardar confirmação humana antes da Fase 2. O teste do esqueleto em jogo acontece na Fase 5.

---

## Phase 2: Núcleo textual, índice e ranking base

### Goal
Busca textual exata/prefixo sobre índice invertido, com normalização UTF-8, tokenização, score normalizado com pesos por campo e cobertura, `reasons` sempre preenchido e resiliência a dados ruins, tudo verificado por golden sobre o catálogo sintético.

### Changes

#### 2.1 Texto

**Create**: `src/core/text/Utf8.lua`
- `Utf8.FOLD`: tabela `sequência de bytes → ASCII` para Latin-1 Suplementar (U+00C0–U+00FF) e Latin Extended-A (U+0100–U+017F), gerada por `tools/gen_fold_table.py` (Python `unicodedata.normalize("NFKD")` sem marcas combinantes, mais os casos especiais `ß→ss`, `æ→ae`, `ø→o`, `đ→d`, `ł→l`, `œ→oe`, `þ→th`) e gravada como literal Lua. Assim o arquivo não depende de nada em tempo de execução.
- `Utf8.fold(s)`: percorre bytes. Se o byte ≥ 0xC0, lê a sequência de 2 bytes (e de 3/4 bytes só para pular) e substitui se estiver em `FOLD`. Senão copia. Usa buffer de tabela + `table.concat`.
- `Utf8.len(s)`: conta bytes que não sejam de continuação (`b < 0x80 or b >= 0xC0`).

**Create**: `src/core/text/TextNormalizer.lua` — `TextNormalizer.new(cfg)`, com `cfg.protected` (lista de pares `{from, to}` vindos de `units.xml`, ex. `{"km/h","kmh"}`, `{"m³","m3"}`, `{"r$"," r$ "}`) e `cfg.currency` (`{"r$","$","€","£"}`).
`normalize(s)` (idempotente), na ordem:
1. `s = s:gsub("%$[%x][%x][%x][%x][%x][%x]", "")` para remover códigos de cor, e remover bytes de controle `%c`.
2. `Utf8.fold`.
3. `string.lower` (ASCII).
4. Sequências protegidas (`plain find/replace`, ordenadas da mais longa para a mais curta).
5. Símbolos monetários isolados por espaços (L8).
6. Fronteira letra↔dígito: `gsub("(%a)(%d)", "%1 %2")` e `gsub("(%d)(%a)", "%1 %2")`, mas **não** dentro de tokens protegidos de unidade (`m3`, `kmh`). Para isso, aplicar antes a substituição por marcadores `\1n\1` e restaurar depois.
7. Pontuação → espaço, exceto `.` e `,` entre dígitos (`gsub("(%d)([%.,])(%d)", "%1\0%2%3")` com marcador temporário), e exceto `$` e `€` isolados.
8. `gsub("%s+", " ")` + trim.

API adicional `normalizeForIndex(s)` retorna `{norm, joined}`, onde `joined` é a versão sem a separação letra↔dígito (`6r`), guardada como token secundário (§6.2 item 4 do PRD).

**Create**: `src/core/text/Tokenizer.lua`
```lua
---@return {text:string, s:integer, e:integer}[]  -- posições em bytes na string normalizada
function Tokenizer.tokenize(norm)
    local out, pos = {}, 1
    while true do
        local s, e = string.find(norm, "[^ ]+", pos)
        if not s then break end
        out[#out + 1] = { text = string.sub(norm, s, e), s = s, e = e }
        pos = e + 1
    end
    return out
end
```
Os `span`s da `Query` referem-se à string normalizada. `Query.raw` guarda o original; para diagnóstico basta mostrar o trecho normalizado.

#### 2.2 Índice

Acréscimo ao contrato `IndexedItem` (PRD §6.1): `fields.species`, `fields.category` com `id` (nome interno, ex. `TRACTORSM`), `brandId` (ex. `JOHNDEERE`), `phrases` (lista de frases normalizadas multi-palavra do item, usada em F3).

**Create**: `src/core/index/IndexBuilder.lua`
- `IndexBuilder.new(normalizer, opts)`. `opts.fieldIds = { name=1, brand=2, category=4, mod=8, author=16, dlc=32, spec=64 }`. Não usa bitmask real: cada posting guarda uma tabela `{[fieldName]=true}`, porque o Lua 5.1 não tem bitops (desvio consciente do PRD §6.1, com o mesmo efeito).
- `begin(rawItems)` → estado. `step(state, budgetSec, clock)` processa itens até estourar o orçamento e retorna `done:boolean`. `build(rawItems)` = `begin` + `step` sem limite.
- Por item, dentro de `pcall` (RF-062): valida `xmlFilename` (string não vazia; se faltar, o item é descartado com motivo `no-id`). Normaliza cada campo textual presente (RF-061: campo ausente = ignorado), tokeniza, registra postings/vocabulário/facets, copia `price` e `specs` válidos (número finito ≥ 0, senão descartado com contador `invalid-spec:<id>`).
- Diagnóstico: `state.skipped[reason] = n`.
- Ao final: ordena `numeric[spec]` por valor e calcula `idf[token] = log(1 + N / df)`.

**Create**: `src/core/index/SearchIndex.lua`
```lua
---@class SearchIndex
---@field items IndexedItem[]
---@field postings table<string, table<integer, table<string, boolean>>>
---@field vocabulary table<string, integer>   -- df
---@field idf table<string, number>
---@field prefixes table<string, string[]>    -- prefixo (2..6 bytes) → tokens
---@field facets {brand:table, category:table, origin:table, species:table}
---@field numeric table<string, {value:number, id:integer}[]>
---@field signature string
function SearchIndex:tokensWithPrefix(p) end   -- via prefixes, limitado a 50
function SearchIndex:postingsFor(token) end
function SearchIndex:rangeIds(spec, min, max) end -- busca binária em numeric[spec]
```
`prefixes` indexa prefixos de 2 a 6 bytes de cada token do vocabulário. Tokens com mais de 6 bytes usam o prefixo de 6 e filtram com `string.sub`.

**Create**: `src/core/index/Signature.lua` — `Signature.of(rawItems)` = `#items .. ":" .. Hash.string(concat de xmlFilename na ordem recebida)`.

#### 2.3 Matching

**Create**: `src/core/match/ExactMatcher.lua` — para um token de consulta: postings exatos (`kind="exact"`) e, se `#token >= 2`, tokens com o prefixo (`kind="prefix"`), com `sim = #token / #indexedToken`, limitado a no mínimo 0.5.
**Create**: `src/core/match/FieldMatcher.lua` — dado `candidates[token] = {itemId → {field → {kind, sim, matched}}}`, escolhe por item e por termo o melhor `(campo, tipo)` segundo `wCampo · wTipo · sim` e gera o `MatchReason`.

#### 2.4 Ranking

**Create**: `src/core/rank/Weights.lua` — valores iniciais do PRD §6.6 como tabela Lua única (`fields`, `types`, `fuzzyMaxByLen`, `minScoreRel = 0.25`, `minScoreAbs = 0.15`, `concept = 0.9`, `coverageFloor = 0.5`, `penalty = { shortToken = 0.1, secondaryOnly = 0.1, fuzzyFar = 0.15 }`). A F9 calibra esses valores.

**Create**: `src/core/rank/SearchScorer.lua` (L11)
```lua
-- raw(item) = Σ_t best_t(item) + Σ_c wConcept·conf_c·sat_c(item)
-- max       = Σ_t (1.0·1.0·1·idf_t) + Σ_c wConcept·conf_c        (máximo teórico da consulta)
-- coverage  = (termos satisfeitos + conceitos satisfeitos) / (termos + conceitos)
-- score     = clamp01( raw/max · (floor + (1-floor)·coverage) − penalidades )
function SearchScorer.score(query, item, termHits, conceptHits, W)
    local raw, max, hit, total, reasons = 0, 0, 0, 0, {}
    for i, term in ipairs(query.terms) do
        local idf = term.idf or 1
        max = max + idf
        total = total + 1
        local h = termHits[i]
        if h then
            raw = raw + h.value * idf
            hit = hit + 1
            reasons[#reasons + 1] = h.reason
        end
    end
    for _, c in ipairs(query.concepts) do
        local w = W.concept * c.confidence
        max = max + w
        total = total + 1
        local h = conceptHits[c]
        if h then
            raw = raw + w
            hit = hit + 1
            reasons[#reasons + 1] = h
        end
    end
    if total == 0 then return 1, 1, reasons end -- consulta só com constraints/filtros
    local coverage = hit / total
    local s = (raw / max) * (W.coverageFloor + (1 - W.coverageFloor) * coverage)
    s = s - SearchScorer.penalties(query, termHits, W)
    if s < 0 then s = 0 elseif s > 1 then s = 1 end
    return s, coverage, reasons
end
```
`penalties`: soma `W.penalty.fuzzyFar` por hit fuzzy com distância igual ao máximo permitido, `shortToken` por hit de prefixo em token ≤ 3, `secondaryOnly` se todos os hits do item estão em `mod`/`author`/`dlc`.

**Create**: `src/core/rank/Ranker.lua` — ordena por `score` desc, depois `coverage` desc, depois `fields.name.norm` asc (determinístico). Corta por `score >= max(minScoreAbs, minScoreRel·best)` e por `maxResults`.

#### 2.5 Serviço

**Modify**: `src/app/SearchService.lua` — implementação:
```lua
---@param deps {catalog:CatalogSource, logger:Logger, clock:Clock, data:LinguisticData, settings:table}
function SearchService.new(deps) end
function SearchService:ensureIndex(budgetSec) end   -- delega a IndexLifecycle; true quando pronto
---@param text string
---@param ui UiFilters|nil
---@return SearchResult[] results, Query query
function SearchService:search(text, ui) end
```
Na F2, `QueryParser` ainda não existe. `search` monta uma `Query` mínima (`terms` = tokens normalizados, `concepts = {}`, `constraints = {}`). Consulta vazia ou só com espaços retorna `{}` sem erro (RF-005). Todo o `search` roda dentro de `SafeCall.run("search", ...)`; em erro devolve `{}` e loga uma linha (RF-060).

**Modify**: `src/app/IndexLifecycle.lua` — `ensure(budget)`: calcula `Signature.of(catalog:items())`, reconstrói se a assinatura mudou, suporta `step` fatiado e registra em `Diagnostics` o tempo, os itens, os tokens e a memória (`collectgarbage("count")` antes/depois). `release()` zera referências. O `collectgarbage` é permitido em `app/`.

**Modify**: `src/app/Diagnostics.lua` — tempos de build; anel das últimas 100 latências de consulta (p50/p95); itens ignorados por motivo; cobertura por spec (`nº de itens com spec X / total`).

#### 2.6 Fixtures e golden

**Create**: `tests/fixtures/catalog/synthetic.xml` — cerca de 80 itens `RawItem` cobrindo:
- Tratores de várias marcas e potências (John Deere 6R 150/185/250, 7R, 8R; Fendt 700/900; New Holland T7; Case IH; Massey; Valtra), com `categoryId` `TRACTORSS/M/L`, `price` e `specs.power` em kW.
- Pulverizadores, semeadeiras, plantadeiras, reboques/carretas, colheitadeiras, enfardadeiras, com `capacity` (L), `workingWidth` (m), `neededPower` (kW).
- Itens de mod com `modName`, `modTitle`, `author`; itens de DLC com `dlcTitle`.
- Itens malformados: sem marca, sem categoria, `name` vazio, `price="abc"`, `power=-1`, `power=NaN`, sem `xmlFilename`. Um item cujo `name` contém `%()-.[` (regressão de D3).
- Nomes com acento (`Pulverizador Autopropelido Série X`) e caixa mista.

Formato:
```xml
<catalog profile="synthetic">
  <item xmlFilename="data/vehicles/johnDeere/6r/6r250.xml" name="6R 250" brand="JOHNDEERE" brandTitle="John Deere"
        categoryId="TRACTORSM" categoryTitle="Tratores M" species="vehicle" price="248000" origin="base">
      <spec id="power" value="184" unit="kw"/><spec id="maxSpeed" value="50" unit="kmh"/>
  </item>
</catalog>
```

**Create**: `tests/golden/runner.lua` + `tests/golden/golden_spec.lua` — lê `tests/golden/queries.<lang>.xml` e cada `tests/fixtures/catalog/*.xml`. Os casos declaram `fixtures="synthetic"` (padrão) ou `fixtures="base,base+dlc,base+mods"`. Tipos de expectativa:

| Tag | Semântica |
|---|---|
| `<expectTop n minHits category brand name>` | entre os top `n`, ≥ `minHits` itens satisfazem os atributos (`*` como curinga de prefixo) |
| `<expectAll top category brand>` | todos os top `top` satisfazem |
| `<expectFirst name>` | o primeiro resultado tem o nome |
| `<expectRankBefore a b>` | o item de nome `a` vem antes de `b` |
| `<expectEmpty/>` | nenhum resultado, sem erro |
| `<expectMaxScore value>` | score máximo ≤ value (ou lista vazia) |
| `<expectConstraint spec op min max>` | a `Query` contém a constraint (tolerância 0.1) |
| `<expectConcept kind value>` | a `Query` contém o conceito |
| `<expectTerms>a b</expectTerms>` | termos remanescentes exatamente iguais |
| `<expectReasons field kind>` | o top-1 tem `MatchReason` com campo/tipo |
| `<expectNoError/>` | `search` não lança erro e o logger não tem `error` |

Todo `<case>` tem atributo `ac="AC-..."` (ids do Apêndice A.4) ou `req="RF-..."`. O `check_trace.py` cruza esses ids com a matriz. As métricas agregadas (precisão@5, MRR, taxa de consultas vazias) são impressas ao final e gravadas em `dist/golden-metrics.txt`.

**Create**: `tests/golden/queries.pt.xml` — casos da F2 (os demais entram nas fases seguintes):
```xml
<golden lang="pt">
  <case id="txt-trator" ac="AC-TXT-01" query="6r"><expectTop n="5" minHits="3" brand="JOHNDEERE"/></case>
  <case id="txt-upper" ac="AC-TXT-02" query="FENDT 900"><expectAll top="3" brand="FENDT"/></case>
  <case id="txt-accent" ac="AC-TXT-03" query="serie x"><expectFirst name="Pulverizador Autopropelido Série X"/></case>
  <case id="txt-spaces" ac="AC-TXT-04" query="   john    6r  "><expectAll top="3" brand="JOHNDEERE"/></case>
  <case id="cmp-multi" ac="AC-CMP-01" query="john 6r 250"><expectFirst name="6R 250"/></case>
  <case id="mod-name" ac="AC-MOD-02" query="agromods"><expectAll top="2" origin="mod"/></case>
  <case id="mod-author" ac="AC-MOD-03" query="farmerbr"><expectTop n="3" minHits="1" origin="mod"/></case>
  <case id="mod-indexed" ac="AC-MOD-01" query="custom trailer 24t"><expectTop n="3" minHits="1" origin="mod"/></case>
  <case id="res-empty" ac="AC-RES-01" query="zzzzqqqq"><expectEmpty/><expectNoError/></case>
  <case id="res-magic" req="RF-062" query="%()-.[ ^$"><expectNoError/></case>
  <case id="rank-field" ac="AC-RNK-04" query="deere"><expectReasons field="brand" kind="exact"/></case>
</golden>
```
"trator" (AC-TXT-01) depende de alias e é concluído na F3. Na F2 o caso usa `6r` e fica marcado `phase="2"`. O caso definitivo `txt-trator` entra na F3.

**Create**: `tests/unit/text_spec.lua`, `tests/unit/index_spec.lua`, `tests/unit/rank_spec.lua`, `tests/unit/resilience_spec.lua`:
- Utf8: `fold("ÁÉÍÓÚáéíóúçãõâêô")` = `"aeiouaeiouçao..."` equivalente ASCII; bytes inválidos preservados.
- Normalizer: casos da §6.2 do PRD, incluindo `"200cv"→"200 cv"`, `"40.000 L"→"40.000 l"`, `"R$150 mil"→"r$ 150 mil"`, `"km/h"→"kmh"`.
- IndexBuilder: item sem marca continua indexado por nome (AC-RES-02). Item com `price="abc"` não tem preço, conta `invalid-spec:price`, e o índice continua íntegro. Item sem `xmlFilename` é ignorado com `no-id`.
- **Não mutação** (D2): congelar os `RawItem.ref` com metatable `__newindex = error` e construir o índice sem erro.
- Scorer: exato > prefixo com o mesmo campo; mais termos satisfeitos → score maior (AC-RNK-02); hits só em `author` recebem penalidade.
- Resiliência: `SearchService:search` com um catálogo cujo `items()` lança erro → retorna `{}`, loga uma vez e não propaga (AC-RES-03).

**Create**: `tests/prop/normalizer_prop_spec.lua` — 2000 strings aleatórias (bytes 0–255, seed fixa): `normalize(normalize(s)) == normalize(s)`, sem erro. O tokenizer nunca produz token vazio.

**Create**: `tests/bench/gen_catalog.lua` (gera 3000 `RawItem` sintéticos determinísticos), `tests/bench/run.lua` (mede build, p50/p95 de 200 consultas simples e 200 compostas com `os.clock`; `--compare` falha se regredir > 20% em relação a `tests/bench/baseline.lua`; `--write-baseline` grava a baseline) e `tests/bench/baseline.lua` inicial.

**Modify**: `src/manifest.lua` — adicionar, em ordem: `core/text/Utf8.lua`, `core/text/TextNormalizer.lua`, `core/text/Tokenizer.lua`, `core/index/Signature.lua`, `core/index/SearchIndex.lua`, `core/index/IndexBuilder.lua`, `core/match/ExactMatcher.lua`, `core/match/FieldMatcher.lua`, `core/rank/Weights.lua`, `core/rank/SearchScorer.lua`, `core/rank/Ranker.lua`, antes de `app/`.

**Modify**: `docs/traceability.md` — marcar a verificação concreta (nomes dos specs/casos) de RF-006..015, RF-037..042 (parcial), RF-060..062 e AC-TXT-*, AC-MOD-*, AC-RES-01..03.

### Success Criteria

#### Automated Verification
- [x] `make unit prop` passa.
- [x] `make golden` passa (todos os casos `phase="2"`) e imprime as métricas.
- [x] `make bench`: build de 3000 itens ≤ 150 ms (~130 ms na máquina de dev) e consulta simples p95 ≤ 5 ms; baseline gravada em `tests/bench/baseline.lua`.
- [x] `make deps lint trace verify` continuam verdes.

#### Manual Verification
- [x] Rodar `lua tools/query.lua "john 6r"`, script de dev que imprime a `Query`, o top 10, os scores e os `reasons` sobre o catálogo sintético, e avaliar se a ordem faz sentido. — ordem coerente: os 5 itens que satisfazem os 3 termos empatam em score e desempatam por nome; os que só satisfazem 2 termos vêm depois.

**⏸ PAUSE**: aguardar confirmação humana antes da Fase 3.

---

## Phase 3: Fuzzy e vocabulário

### Goal
Tolerância a remoção, inserção, substituição e transposição com custo controlado; fuzzy de frase para marcas/categorias multi-palavra; aliases e sinônimos por idioma carregados de dados.

### Changes

**Create**: `src/core/match/Osa.lua` — distância Damerau-Levenshtein restrita com limite e *early exit*, em bytes:
```lua
local NS = SmartShopSearch
local Osa = {}
local byte, abs = string.byte, math.abs
function Osa.distance(a, b, max)
    local la, lb = #a, #b
    if a == b then return 0 end
    if abs(la - lb) > max then return max + 1 end
    local prev2, prev, cur = {}, {}, {}
    for j = 0, lb do prev[j] = j end
    for i = 1, la do
        cur[0] = i
        local rowMin = i
        local ai, ap = byte(a, i), (i > 1) and byte(a, i - 1) or nil
        for j = 1, lb do
            local bj = byte(b, j)
            local v = prev[j] + 1
            local t = cur[j - 1] + 1
            if t < v then v = t end
            t = prev[j - 1] + ((ai == bj) and 0 or 1)
            if t < v then v = t end
            if ap and j > 1 and ai == byte(b, j - 1) and ap == bj then
                t = prev2[j - 2] + 1
                if t < v then v = t end
            end
            cur[j] = v
            if v < rowMin then rowMin = v end
        end
        if rowMin > max then return max + 1 end
        prev2, prev, cur = prev, cur, prev2
    end
    return prev[lb]
end
NS.core.Osa = Osa
```

**Create**: `src/core/index/TrigramIndex.lua` — `build(vocabulary)`: para cada token com 3 bytes ou mais, gera os trigramas de `"$" .. token .. "$"` e mapeia `trigram → {token,...}`. `candidates(q, maxDist)`: conta trigramas compartilhados. Um token vira candidato se `shared >= max(1, #grams(q) - 3*maxDist)` **e** `|len diff| <= maxDist`. Retorna no máximo 200 candidatos, ordenados por `shared` desc. O índice é construído ao fim do `IndexBuilder` sobre `vocabulary`, sobre as `phrases` (chave com espaço) e sobre os termos de alias.

**Create**: `src/core/match/FuzzyMatcher.lua`
- `maxDistFor(len)` lê `Weights.fuzzyMaxByLen` (`≤3:0`, `4–5:1`, `6–9:2`, `≥10:3`; `len` = `Utf8.len`) — RF-021/022.
- `matchToken(q)`: se `maxDist == 0`, retorna vazio (curtos só com exato/prefixo). Senão pega os candidatos por trigrama e calcula `Osa.distance`. Resultado `{token, dist, sim = 1 - dist/max(#q,#token)}` com `wTipo` `fuzzy d=1` ou `fuzzy d=2+` (`Weights.types.fuzzy1/fuzzy2`).
- **Fuzzy de frase (L6)** `matchPhrase(tokens, i)`: para janelas `w = 3, 2` a partir de `i`, junta `tokens[i..i+w-1]` com espaço e compara contra `phrases` e aliases multi-palavra. O limiar vem do comprimento sem espaços (`jon dere` → 7 → `maxDist 2`). A janela vencedora consome os tokens (evita dupla contagem) e vira hit no campo de origem (`brand`/`category`) ou conceito (alias).
- Ordem por token: exato → prefixo → alias → fuzzy. O fuzzy só roda se não houver hit exato no mesmo campo (economia).

**Create**: `src/core/lang/AliasResolver.lua`
```lua
---@class AliasData  -- já parseado (portas DataLoader); nunca lê arquivo
---@field concepts {kind:string, id:string, terms:string[]}[]
function AliasResolver.new(normalizer, dataList) end  -- dataList: pt + en (S-06)
---@return {kind:string, id:string, confidence:number, span:integer[], consumed:integer}|nil
function AliasResolver:resolveAt(tokens, i, fuzzy) end
```
- Na construção, normaliza todos os termos; os de uma palavra vão para `single[term]` e os multi-palavra para `multi[firstToken]`, ordenados por tamanho desc.
- `resolveAt`: tenta frase multi exata (maior primeiro), depois single exato (`confidence 1.0`), depois fuzzy sobre os termos de alias (`confidence = sim`) usando o `TrigramIndex` dos aliases e o mesmo limiar por tamanho.
- `id` aceita curinga de prefixo (`TRACTORS*`). `IdMatcher.matches(id, value)` fica em `core/util/Table.lua`.
- Conceitos `kind` ∈ `category | brand | species | origin`. `origin` cobre "dlc", "mod", "base/original"; `species` cobre "construção"/"placeable" (S-03).

**Create**: `src/app/LinguisticData.lua` — agrega os dados por locale vindos da porta `DataLoader` (`load(locale, name) → table|nil`) e expõe `aliases`, `units`, `numbers`, `comparators`, `stopwords` e `context` (F4) já mesclados: idioma do jogo primeiro, depois `en`. Arquivo ausente = conjunto vazio, com um `warning` único.

**Create**: `src/adapters/XmlDataLoader.lua` — implementa `DataLoader` em jogo com `XMLFile.load(key, MOD_DIR.."data/"..locale.."/"..name..".xml")`, percorrendo com `xmlFile:iterate` [A VALIDAR a API de iteração na F5] e convertendo para tabelas simples. Os testes usam `tests/stubs/FileDataLoader.lua` com `tests/support/xml.lua`.

**Create**: `src/data/pt/aliases.xml`, `src/data/en/aliases.xml`, `src/data/de/aliases.xml`, `src/data/fr/aliases.xml` — formato do PRD §14. Conteúdo mínimo obrigatório:
- **Categorias** (pt): trator/tratores/trator agrícola → `TRACTORS*`; pulverizador/pulverizadores/autopropelido → `SPRAYERS*`; semeadeira/plantadeira → `SEEDERS*`/`PLANTERS*`; reboque/carreta/trailer → `TRAILERS*`; colheitadeira/colhedora/ceifadeira → `HARVESTERS*`; enfardadeira → `BALERS*`; grade/arado/subsolador → `CULTIVATORS*`/`PLOWS*`/`SUBSOILERS*`; pá carregadeira/telescópica → `WHEELLOADERS*`/`TELELOADERS*`; caminhão → `TRUCKS*`. Os ids reais são confirmados na F5 e corrigidos só aqui, nos dados.
- **Marcas** (en, carregado sempre): john deere/jd/deere/jhon deere → `JOHNDEERE`; new holland/nh; case ih/case; massey ferguson/massey/mf; fendt; claas; valtra; kuhn; horsch; amazone; lemken; krone; väderstad/vaderstad; jacto; stara; baldan; jan; tatu; kverneland; pöttinger/pottinger.
- **Espécie/origem**: construção/construções/placeable → `species:placeable`; dlc/expansão → `origin:dlc`; mod/mods → `origin:mod`; original/base → `origin:base`.

**Modify**: `src/core/index/IndexBuilder.lua` — gerar `phrases` a partir de `brandTitle`, `categoryTitle` e `modTitle` normalizados com 2+ tokens; construir o `TrigramIndex` ao final.
**Modify**: `src/app/SearchService.lua` — injetar `AliasResolver` e `FuzzyMatcher`. Até a F4, a `Query` recebe conceitos por alias e termos restantes.
**Modify**: `src/manifest.lua` — `core/match/Osa.lua`, `core/index/TrigramIndex.lua`, `core/match/FuzzyMatcher.lua`, `core/lang/AliasResolver.lua`, `app/LinguisticData.lua`, `adapters/XmlDataLoader.lua`.

**Modify**: `tests/golden/queries.pt.xml` — adicionar:
```xml
<case id="txt-trator" ac="AC-TXT-01" query="trator"><expectTop n="10" minHits="8" category="TRACTORS*"/></case>
<case id="txt-trator-upper" ac="AC-TXT-02" query="TRATOR"><expectTop n="10" minHits="8" category="TRACTORS*"/></case>
<case id="fuzzy-trtor" ac="AC-FUZ-01" query="trtor"><expectTop n="10" minHits="8" category="TRACTORS*"/></case>
<case id="fuzzy-tratro" ac="AC-FUZ-02" query="tratro"><expectTop n="10" minHits="8" category="TRACTORS*"/></case>
<case id="fuzzy-jon-dere" ac="AC-FUZ-03" query="jon dere"><expectAll top="5" brand="JOHNDEERE"/></case>
<case id="fuzzy-jhon-deere" ac="AC-FUZ-04" query="jhon deere"><expectAll top="5" brand="JOHNDEERE"/></case>
<case id="fuzzy-john-dere" req="RF-020" query="john dere"><expectAll top="5" brand="JOHNDEERE"/></case>
<case id="fuzzy-pulverizdor" ac="AC-FUZ-05" query="pulverizdor"><expectTop n="5" minHits="3" category="SPRAYERS*"/></case>
<case id="fuzzy-insert" req="RF-017" query="tratorr"><expectTop n="10" minHits="8" category="TRACTORS*"/></case>
<case id="fuzzy-subst" req="RF-018" query="trayor"><expectTop n="10" minHits="8" category="TRACTORS*"/></case>
<case id="neg-noise" ac="AC-FUZ-06" query="xqzw"><expectMaxScore value="0.2"/></case>
<case id="neg-short" req="RF-022" query="ox"><expectMaxScore value="0.2"/></case>
<case id="neg-unrelated" ac="AC-FUZ-06" query="banana"><expectMaxScore value="0.2"/></case>
<case id="rank-exact-fuzzy" ac="AC-RNK-01" query="fendt"><expectRankBefore a="Fendt 942 Vario" b="Fent Custom Trailer"/></case>
<case id="rank-weak" ac="AC-RNK-03" query="pulverizadr"><expectReasons field="category" kind="alias"/></case>
<case id="cmp-cat-brand" ac="AC-CMP-03" query="trator fendt"><expectAll top="3" brand="FENDT" category="TRACTORS*"/></case>
<case id="alias-carreta" req="RF-023" query="carreta"><expectTop n="5" minHits="3" category="TRAILERS*"/></case>
</golden>
```
O fixture sintético ganha o item "Fent Custom Trailer" (mod) para o caso `rank-exact-fuzzy`. Criar também `tests/golden/queries.en.xml` com `tractor`, `trailer`, `baler`, `sprayer` e `tratcor` (RF-025).

**Create**: `tests/unit/fuzzy_spec.lua` — tabela de casos da OSA (`trtor/trator=1`, `tratro/trator=1`, `jhon/john=1`, `pulverizdor/pulverizador=1`, `abc/xyz=3`, early exit retorna `max+1`). Limiar por tamanho. Frase `jon dere` × `john deere` = 2 aceita, `jo de` × `john deere` rejeitada.
**Create**: `tests/prop/osa_prop_spec.lua` — simetria `d(a,b)=d(b,a)`; `d ≤ Levenshtein` (implementação de referência lenta só no teste); `d(a,a)=0`; desigualdade de tamanho.
**Create**: `tests/unit/alias_spec.lua` — carregar `pt` + `en`; `resolveAt` de uma e várias palavras; troca de idioma sem mudar código (RF-025/059): o mesmo teste roda com `data/de` e resolve `schlepper → TRACTORS*`.

### Success Criteria

#### Automated Verification
- [ ] `make unit prop golden` passa, incluindo todos os `AC-FUZ-*`, `AC-TXT-01/02`, `AC-RNK-01/03` e `AC-CMP-03`.
- [ ] `make bench`: consulta simples com fuzzy p95 ≤ 5 ms; build ≤ 150 ms (com trigramas).
- [ ] `make deps lint trace verify` verdes; o ZIP contém `data/`.

#### Manual Verification
- [ ] Revisar os 20 primeiros resultados de `trtor`, `jon dere` e `pulverizdor` via `tools/query.lua` e confirmar que não há falsos positivos gritantes.

**⏸ PAUSE**: aguardar confirmação humana antes da Fase 4.

---

## Phase 4: Linguagem estruturada, specs e filtros

### Goal
Interpretar números, unidades, dinheiro, comparadores, intervalos e frases de contexto numa `Query` AST. Aplicar constraints e filtros de UI via facets e faixas numéricas, mantendo como termos as partes não compreendidas.

### Changes

#### 4.1 Dados linguísticos

**Create**: `src/data/common/units.xml`
```xml
<units>
  <quantity id="power" canonical="kw" specs="power neededPower">
      <unit alias="kw" factor="1"/><unit alias="cv" factor="0.7355"/><unit alias="ps" factor="0.7355"/>
      <unit alias="hp" factor="0.7457"/>
  </quantity>
  <quantity id="volume" canonical="l" specs="capacity">
      <unit alias="l" factor="1"/><unit alias="lt" factor="1"/><unit alias="m3" factor="1000"/>
      <unit alias="gal" factor="3.785"/>
  </quantity>
  <quantity id="length" canonical="m" specs="workingWidth"><unit alias="m" factor="1"/><unit alias="ft" factor="0.3048"/></quantity>
  <quantity id="speed" canonical="kmh" specs="maxSpeed"><unit alias="kmh" factor="1"/><unit alias="mph" factor="1.609"/></quantity>
  <quantity id="mass" canonical="kg" specs="weight"><unit alias="kg" factor="1"/><unit alias="t" factor="1000"/><unit alias="ton" factor="1000"/></quantity>
  <quantity id="money" canonical="money" specs="price">
      <unit alias="r$" factor="1"/><unit alias="$" factor="1"/><unit alias="€" factor="1"/>
  </quantity>
  <protected from="km/h" to="kmh"/><protected from="m³" to="m3"/><protected from="r$" to=" r$ "/>
</units>
```
**Create**: `src/data/pt/units.xml` (aliases localizados: `litro/litros → l`, `metro/metros → m`, `tonelada(s) → t`, `quilo(s) → kg`, `cavalo(s) → cv`, `pés → ft`, `reais/real → r$`). O mesmo vale para `en/de/fr/units.xml`.
**Create**: `src/data/pt/numbers.xml` — `<numbers decimal="," thousands=".">`; multiplicadores `mil=1000`, `k=1000`, `mi=1e6`, `milhao=1e6`, `milhoes=1e6`; por extenso `um=1 … dez=10, vinte=20, cem=100, duzentos=200, trezentos=300, quinhentos=500`. O `en` usa `decimal="." thousands=","`, `k`, `thousand`, `million`, `one..ten`.
**Create**: `src/data/pt/comparators.xml`
```xml
<comparators>
  <op id="gt"><p>acima de</p><p>mais de</p><p>maior que</p><p>mais que</p><p>superior a</p><p>&gt;</p></op>
  <op id="gte"><p>a partir de</p><p>no minimo</p><p>pelo menos</p><p>&gt;=</p></op>
  <op id="lt"><p>abaixo de</p><p>menos de</p><p>menor que</p><p>inferior a</p><p>&lt;</p></op>
  <op id="lte"><p>ate</p><p>no maximo</p><p>&lt;=</p></op>
  <op id="approx"><p>cerca de</p><p>aproximadamente</p><p>uns</p><p>~</p></op>
  <range><p>entre {a} e {b}</p><p>de {a} a {b}</p><p>{a} a {b}</p><p>{a}-{b}</p></range>
</comparators>
```
Os padrões são armazenados já normalizados (sem acento) e comparados por sequência de tokens. `{a}`/`{b}` = expressão numérica (§4.2). `approx` gera `between [v·0.9, v·1.1]`.
**Create**: `src/data/pt/stopwords.xml` (`de do da dos das e com para por o a os as um uma em no na que`). O mesmo para `en/de/fr` (L7).
**Create**: `src/data/pt/context.xml` (L4)
```xml
<context>
  <compat><p>compativel com</p><p>compativeis com</p><p>serve no</p><p>serve na</p><p>para o</p><p>para a</p></compat>
  <self><p>este</p><p>esta</p><p>esse</p><p>essa</p><p>este trator</p><p>selecionado</p></self>
</context>
```

#### 4.2 Parsers (core/lang)

**Create**: `src/core/lang/NumberParser.lua`
```lua
---@return {value:number, consumed:integer}|nil
function NumberParser:parseAt(tokens, i)
```
Regras, em ordem, sobre `tokens[i]` (e seguintes):
1. Numeral por extenso (`duzentos`) → valor.
2. Dígitos com separadores: se `thousands` = `.` e todos os grupos após o primeiro têm 3 dígitos (`40.000`, `1.250.000`), remove os separadores. Se houver `decimal` (`1,5`), converte para `.`. Grupo que não tem 3 dígitos após `.` em pt (`1.5`) é tratado como decimal (tolerância). Em `en`, espelhado.
3. Multiplicador no token seguinte (`150 mil`, `1,2 mi`) ou colado (`150k`, que o normalizer separa em `150 k`) → multiplica e soma `consumed`.
4. Números inválidos (`1..2`) → `nil`, e o token segue como termo (RF-036).

**Create**: `src/core/lang/UnitParser.lua` — `parseAt(tokens, i)` casa o alias de unidade (1 ou 2 tokens, maior primeiro) e retorna `{quantity, factor, consumed}`. `toCanonical(value, unit)` converte.
**Create**: `src/core/lang/ComparatorParser.lua` — `parseAt(tokens, i, number, unit)`:
- Padrões `range` com `{a}`/`{b}`: casa tokens literais e chama `NumberParser` nos marcadores. A unidade pode vir após `b` (`entre 200 e 300 cv`), após ambos, ou antes (`r$ 100 mil a 200 mil`). A unidade de `b` se aplica a `a` quando só `b` tem unidade (RF-033).
- Padrões de `op`: casa a sequência, seguida de `[moeda] número [unidade]`.
- Número isolado seguido de unidade (`200 cv`) → `approx`? **Não**: vira `eq` com tolerância de ±5% (`between`), com `MatchReason.detail` "≈". Isso cumpre RF-027 sem descartar itens próximos.
- Retorna `Constraint{quantity, op, min, max, span, consumed}`.

**Create**: `src/core/lang/ContextParser.lua` — reconhece `compat` (+ `self` opcional) e produz `QueryContext{kind="compatibleWith", target="selected"|"query", targetTerms=string[], span}`. Os tokens após o padrão `compat` que não sejam `self` viram `targetTerms` (ex.: "compatíveis com 6r 250").

**Create**: `src/core/lang/QueryParser.lua` — orquestra (equivalente ao fluxo §22 dos requisitos):
```text
normalize → tokenize → varredura esquerda→direita com consumo:
   ContextParser → ComparatorParser (inclui Number/Unit) → [moeda] Number [Unit] isolado
   → AliasResolver.resolveAt (frase/single/fuzzy) → senão token fica "pendente"
pendentes: remove stopwords → QueryTerm{text, span, fuzzyMax=FuzzyMatcher.maxDistFor(len)}
constraints sem quantidade → regra L9
warnings: números sem unidade descartados, padrões incompletos ("entre 200"), constraint duplicada
```
**Regra L9** (constraint sem unidade): se houver símbolo monetário, multiplicador (`mil`, `k`, `mi`) ou valor ≥ 1000 → `quantity="money"`. Senão, o número volta a ser termo (`6r`, `250`) e entra `warning`. Assim, `menos de 150 mil` vira `price < 150000` e `john 250` mantém `250` como termo.

Acréscimos ao contrato `Query` (PRD §6.4): `Constraint.quantity` (em vez de `spec`; L10), `Query.context: QueryContext|nil`.

**Create**: `src/core/rank/FilterEngine.lua`
```lua
---@param query Query
---@param ui UiFilters|nil   -- {category={ids}, brand={ids}, origin={...}, species={...}, price={min,max}, specs={[quantity]={min,max}}}
---@return table<integer, boolean>|nil allowed  -- nil = sem restrição
---@return table<integer, MatchReason[]> reasons
function FilterEngine.apply(index, query, ui, units)
```
- Para cada `Constraint` e cada faixa de `ui.specs`/`ui.price`: resolve a spec do item pela lista `units[quantity].specs`. Na prática, a união de `index:rangeIds(spec, min, max)` para cada spec da lista, respeitando que o item só é avaliado pela **primeira** spec que possui (L10). Itens sem nenhuma spec da grandeza são excluídos (PRD §6.6), sem erro. O `MatchReason{kind="constraint", field="spec.power", detail="184 kW (250 cv) ∈ [147.1, 220.7]"}` usa a conversão inversa para a unidade da consulta.
- Filtros de UI de facet (`category`, `brand`, `origin`, `species`) são interseções eliminatórias (RF-043/044/047). Os conceitos textuais **não** são eliminatórios: somam score e cobertura (RF-041).
- Interseção de todos os conjuntos. Se o resultado for vazio, devolve o conjunto vazio (estado vazio, RF-005).

**Modify**: `src/app/SearchService.lua` — pipeline final:
```lua
function SearchService:search(text, ui)
    return SafeCall.run("search", function()
        local q = self.parser:parse(text, self.locale)
        local allowed, cReasons = FilterEngine.apply(self.index, q, ui, self.data.units)
        local termHits, conceptHits = self.engine:match(q, allowed) -- Exact/Prefix/Alias/Fuzzy/Field
        local results = {}
        local ids = SearchService.candidateIds(q, allowed, termHits, conceptHits)
        for _, id in ipairs(ids) do
            local item = self.index.items[id]
            local s, cov, reasons = SearchScorer.score(q, item, termHits[id] or {}, conceptHits[id] or {}, Weights)
            for _, r in ipairs(cReasons[id] or {}) do reasons[#reasons + 1] = r end
            results[#results + 1] = Models.result(item, s, cov, reasons)
        end
        return Ranker.rank(results, Weights, self.settings.maxResults), q
    end) or {}, nil
end
```
`candidateIds`: se há termos/conceitos, usa a união dos itens com hit, intersectada com `allowed`. Se só há constraints/filtros, usa `allowed` inteiro. Se `q.context` existe, a F8 aplica o filtro de compatibilidade (até lá, `warning` "compatibilidade indisponível").

**Modify**: `src/core/index/IndexBuilder.lua` — `numeric[spec]` para todas as specs presentes, mais `price`. Os facets `origin` e `species` já existem desde a F2.

**Create**: `src/core/index/SpecRegistry.lua` — registro `id → {quantity, canonicalUnit}` (`power`, `neededPower`, `maxSpeed`, `capacity`, `workingWidth`, `weight`, `price`), usado pelo builder para validar o `RawItem.specs` e pelo adapter da F6. Uma nova spec é uma nova entrada (RNF-006).

**Modify**: `src/manifest.lua` — `core/index/SpecRegistry.lua`, `core/lang/NumberParser.lua`, `core/lang/UnitParser.lua`, `core/lang/ComparatorParser.lua`, `core/lang/ContextParser.lua`, `core/lang/QueryParser.lua`, `core/rank/FilterEngine.lua`.

**Modify**: `tests/golden/queries.pt.xml` — adicionar:
```xml
<case id="composite-01" req="RF-034" query="trtor jon dere entre 200 e 300 cv por menos de 150 mil">
    <expectConcept kind="category" value="TRACTORS*"/><expectConcept kind="brand" value="JOHNDEERE"/>
    <expectConstraint spec="power" op="between" min="147.1" max="220.7"/>
    <expectConstraint spec="money" op="lt" max="150000"/>
    <expectTerms></expectTerms>
    <expectAll top="3" brand="JOHNDEERE" category="TRACTORS*"/>
</case>
<case id="num-int" ac="AC-NUM-01" query="acima de 200 cv"><expectConstraint spec="power" op="gt" min="147.1"/></case>
<case id="num-mil" ac="AC-NUM-02" query="menos de 150 mil"><expectConstraint spec="money" op="lt" max="150000"/></case>
<case id="num-local" ac="AC-NUM-03" query="reboque acima de 40.000 litros"><expectConstraint spec="volume" op="gt" min="40000"/></case>
<case id="num-local-dec" ac="AC-NUM-03" query="largura acima de 7,5 m"><expectConstraint spec="length" op="gt" min="7.5"/></case>
<case id="num-rs" req="RF-029" query="trator ate R$ 150 mil"><expectConstraint spec="money" op="lte" max="150000"/></case>
<case id="unit-power" ac="AC-UNI-01" query="trator 200cv"><expectConstraint spec="power" op="between" min="139.7" max="154.5"/></case>
<case id="unit-hp" req="RF-027" query="tractor 200 hp"><expectConstraint spec="power" op="between" min="141.7" max="156.6"/></case>
<case id="unit-cap" ac="AC-UNI-02" query="carreta 40 mil litros"><expectConstraint spec="volume" op="between" min="38000" max="42000"/></case>
<case id="unit-conv" ac="AC-UNI-03" query="tanque acima de 20 m3"><expectConstraint spec="volume" op="gt" min="20000"/></case>
<case id="cmp-gt" ac="AC-CMP2-01" query="mais de 300 cv"><expectConstraint spec="power" op="gt" min="220.6"/></case>
<case id="cmp-lt" ac="AC-CMP2-02" query="abaixo de 150000"><expectConstraint spec="money" op="lt" max="150000"/></case>
<case id="cmp-range" ac="AC-CMP2-03" query="entre 200 e 300 cv"><expectConstraint spec="power" op="between" min="147.1" max="220.7"/></case>
<case id="partial" ac="AC-CMP-02" query="trator verde acima de 200 cv"><expectTerms>verde</expectTerms></case>
<case id="partial-bad" req="RF-036" query="fendt entre 200"><expectConcept kind="brand" value="FENDT"/><expectNoError/></case>
<case id="filter-empty" req="RF-005" query="trator acima de 5000 cv"><expectEmpty/><expectNoError/></case>
<case id="ctx-compat" req="RF-049" query="implementos compativeis com este trator"><expectNoError/></case>
<case id="origin-dlc" req="RF-047" query="dlc pulverizador"><expectConcept kind="origin" value="dlc"/></case>
</golden>
```
Em `en`: `over 200 hp`, `under 150k`, `between 200 and 300 hp`, `40,000 l`.

**Create**: `tests/unit/parser_spec.lua` — uma tabela de ≥ 60 casos `entrada → {concepts, constraints, terms, warnings}` para Number/Unit/Comparator/Context/QueryParser, incluindo: `200cv`, `200 cv`, `200 hp`, `40.000 litros`, `40 mil litros`, `150.000`, `150 mil`, `R$ 150 mil`, `1,5 mi`, `de 100 a 200 cv`, `100-200 cv`, `entre 200`, `acima de`, `menos de 150 mil cv` (unidade vence → power), `6r 250` (termos), números gigantes (`1e308` como texto), negativos.
**Create**: `tests/unit/filter_spec.lua` — interseções de facets; itens sem spec excluídos sem erro; `power` × `neededPower` (L10); UI `price` + constraint textual `price` → interseção.
**Create**: `tests/prop/parser_prop_spec.lua` — 5000 consultas aleatórias montadas de tokens do vocabulário, números, unidades e lixo: `parse` nunca lança erro; todo token está em exatamente um de terms/concepts/constraints/context/stopword/warning (conservação de spans).

### Success Criteria

#### Automated Verification
- [ ] `make unit prop golden` passa, incluindo `composite-01`, `AC-NUM-*`, `AC-UNI-*`, `AC-CMP2-*` e `AC-CMP-02`.
- [ ] `make bench`: consulta composta (5+ termos, 2 constraints) p95 ≤ 15 ms; memória do índice de 3000 itens ≤ 8 MB.
- [ ] `make deps lint trace verify` verdes.

#### Manual Verification
- [ ] `lua tools/query.lua "trtor jon dere entre 200 e 300 cv por menos de 150 mil"` imprime a AST igual à do Desired End State §4 e `reasons` legíveis.

**⏸ PAUSE**: aguardar confirmação humana antes da Fase 5.

---

## Phase 5: Spike de plataforma em jogo (paralelizável a partir do fim da F1)

### Goal
Validar em FS25 real todos os itens `[A VALIDAR]` do PRD e deste spec, gerar os dumps de catálogo dos três perfis e responder às questões 1–4, 13–15 e 18–20 dos requisitos, registrando tudo em `docs/api-findings/`. Esta é a única fase que depende majoritariamente de execução humana no jogo.

### Changes

**Create**: `spike/FS25_SSS_Spike/` — mod descartável, **fora de `src/`** e ignorado pelo build, com `modDesc.xml` + `spike.lua`. Ele:
1. Registra um comando de console `sssSpikeProbe` que imprime `type()` de cada API candidata: `ShopMenu.onOpen/onClose/updateButtonsPanel`, `g_shopMenu.pageShopItemDetails.setDisplayItems/setCategory/resetListSelection`, `pushDetail/popDetail`, `g_shopController.makeDisplayItem`, `TextInputDialog.createFromExistingGui/show`, `g_brandManager.getBrandByIndex`, `g_storeManager.getCategoryByName/getSpecTypes`, `storeItem.specs`, `XMLFile.load/iterate`, `Logging.*`, `g_modSettingsDirectory`, `g_languageShort`, `StoreSpecies.*`.
2. Registra `sssSpikeDump`, que grava `modSettings/FS25_SSS_Spike/dumps/catalog_<perfil>.xml` **no formato exato de `tests/fixtures/catalog`** (§2.6), incluindo todas as chaves de `storeItem.specs` encontradas e, para uma amostra de 50 itens, os caminhos XML candidatos de §9.2/§9.3 do PRD (`storeData.specs.*`, `fillUnit`, `workingWidth`, `attacherJoints`, `inputAttacherJoints`, combinações).
3. Protótipo G1–G6, G11, G12: botão + diálogo + categoria virtual com 3 itens fixos ordenados de forma não alfabética (prova que a ordem é respeitada), além da lista vazia.
4. Mede o tempo de iterar `getItems()` e de ler o XML de 100 itens (base para os orçamentos §15).

**Create**: `docs/api-findings/TEMPLATE.md` e `docs/api-findings/fs25-<versão>.md` — seções obrigatórias:
```markdown
# FS25 <versão> — achados de API (data)
## 0. Ambiente (versão do jogo, descVersion aceito, SO, PC de referência → Q-02, Q-05)
## 1. Tabela [A VALIDAR] (id, item, resultado, evidência: trecho do LUADOC/log)
## 2. Questões dos requisitos §24: Q1, Q2, Q3, Q4, Q13, Q14, Q15, Q18, Q19, Q20
## 3. Análise da referência (requisitos §2.3): bootstrap, Shop GUI, hooks, busca, StoreItem, campos,
##    atualização visual, teclado/input, conflitos com outros mods, limitações a não reproduzir
## 4. Códigos de idioma (Q-03) e tecla padrão (Q-06/S-05)
## 5. ModHub: tela/catálogo acessível por script? (RF-053/Q-08) — decisão implement|unavailable
## 6. Placeables (S-03) — decisão implement|unavailable
## 7. Busca incremental embutida (G7) — viável sem hacks? decisão
## 8. Specs disponíveis: tabela spec → origem (specs/XML) → % de itens com valor em cada perfil
## 9. Compatibilidade: estrutura de combinações e joints encontrada
## 10. Linha de comando do TestRunner e relatório do esqueleto da F1
## 11. Ícone: tamanho/formato aceito
```

**Modify**: `tests/fixtures/catalog/` — adicionar `base.xml`, `base+dlc.xml` e `base+mods.xml` (≥ 50 mods populares, incluindo ao menos 5 com metadados incompletos) a partir dos dumps.
**Modify**: `docs/api-limitations.md` — preencher RF-053/054, G7 e S-03 com `implemented` (planejado) ou `unavailable` + evidência.
**Modify**: `src/data/*/aliases.xml` — corrigir os ids de categoria/marca conforme o dump real.
**Modify**: `src/modDesc.xml` — `descVersion` real (Q-02), tecla final (S-05), códigos de idioma confirmados (S-06).
**Modify**: `src/adapters/GameLocale.lua` — `LANG_MAP` conforme os achados.
**Modify**: `tools/fs25_globals.lua` — adicionar os globais confirmados.
**Modify**: `tools/run_testrunner.ps1` — linha de comando confirmada.

**Regras de decisão da F5 (evitam questões abertas):**
- Uma API marcada `[A VALIDAR]` que não existe → usar a alternativa listada no PRD. Se não houver alternativa, a funcionalidade vai para `api-limitations.md` como `unavailable`, com a evidência.
- G1: se `ShopMenu.onOpen` não existir como método próprio, hook em `ShopMenu.onOpen` herdado **via** `ShopMenu` (não na classe base) e checagem `self == g_shopMenu` no corpo.
- ModHub: se nenhum ponto de extensão documentado ou estável existir para a tela de mods/ModHub, `RF-054 = unavailable` e `ModHubCatalogSource` não é criado (ADR-12).

### Success Criteria

#### Automated Verification
- [ ] `make golden` continua verde com os novos fixtures reais (os casos que declaram `fixtures="base,..."` rodam neles). Se algum caso falhar por diferença de ids, corrigir **somente os dados** de aliases.
- [ ] `make trace` passa; `docs/api-limitations.md` não tem `unavailable` sem evidência.
- [ ] O esqueleto da F1 passou no TestRunner (relatório arquivado em `dist/testrunner/`).

#### Manual Verification
- [ ] Esqueleto da F1 instalado: o jogo carrega o savegame sem erros do mod no `log.txt` e mostra só a linha `info` de carga.
- [ ] Spike: botão, diálogo, categoria virtual ordenada, lista vazia e "voltar" funcionam na loja.
- [ ] `docs/api-findings/fs25-<ver>.md` completo, com todas as seções preenchidas.

**⏸ PAUSE**: aguardar confirmação humana antes da Fase 6.

---

## Phase 6: Adapters de jogo e GUI básica

### Goal
Ligar o motor ao jogo: catálogo real, specs, botão e hotkey, diálogo de texto, resultados ordenados por score na categoria virtual, estado vazio, limpar busca, comandos de console completos e fallback seguro.

### Changes

**Create**: `src/adapters/StoreCatalogSource.lua` — implementa `CatalogSource:items() → RawItem[]`:
```lua
function StoreCatalogSource:items()
    local out = {}
    local items = g_storeManager:getItems()
    for i = 1, #items do
        local si = items[i]
        local ok, raw = pcall(StoreCatalogSource.toRaw, self, si)
        if ok and raw then out[#out + 1] = raw
        elseif not ok then self.diag:skip("extract-error") end
    end
    return out
end
function StoreCatalogSource:inScope(si)
    if not si.showInStore or si.isBundleItem then return false end
    local sp = si.species
    return sp == StoreSpecies.VEHICLE or sp == StoreSpecies.HANDTOOL
        or (self.includePlaceables and sp == StoreSpecies.PLACEABLE) -- S-03
end
```
`toRaw` preenche os campos do PRD §9.1 com proteção a `nil` em cada acesso (`brand` via `g_brandManager`, `category` via `g_storeManager:getCategoryByName`, `mod`/`author` via `g_modManager.nameToMod[si.customEnvironment]`, `origin` pela regra confirmada na F5). `ref = si`, nunca escrito. `specs` vem do `SpecExtractor.primary(si)`.

**Create**: `src/adapters/SpecExtractor.lua` — camada primária (`storeItem.specs` / spec types, conforme a F5) mapeada para `SpecRegistry` com conversão para a unidade canônica. A camada secundária (leitura de XML) é executada **fatiada** pelo `IndexLifecycle` após o build primário e fora da abertura da loja, com cache por `xmlFilename`, e só para specs com cobertura primária < 80% no dump. Valores inválidos são descartados e contados.

**Create**: `src/adapters/ShopGuiAdapter.lua`
- `install()`: via `HookRegistry.add`:
  - `ShopMenu.onOpen` (append) → `SafeCall`: `ensureIndex(0.008)` (orçamento de frame, ADR-04), registra a action com `InputAdapter:bind()`, `ensureButton()`.
  - `ShopMenu.onClose` (append) → `InputAdapter:unbind()`.
  - `ShopMenu.updateButtonsPanel` (append) → visibilidade do botão por página elegível (G3, lista `ELIGIBLE_PAGES` centralizada) e ocultação em `degraded`.
- `ensureButton()`: clona **uma vez** por instância de `g_shopMenu` o primeiro botão do `buttonsPanel`, com texto `g_i18n:getText("sss_button_search")` e `onClickCallback` → `openInput()`. A referência fica em `self.ui[g_shopMenu]` (tabela fraca `setmetatable({}, {__mode="k"})`), **não** em campo de `g_shopMenu` (§8.2 PRD).
- `openInput()`: `TextInputDialog.createFromExistingGui({ text = state.text, maxCharacters = 80, callback = ... })` com a assinatura confirmada na F5. Desativa o filtro de palavrões só se a propriedade existir (D8).
- `show(results, query)`:
  ```lua
  local display = {}
  for i = 1, #results do
      local ok, di = pcall(g_shopController.makeDisplayItem, g_shopController, results[i].item.ref)
      if ok and di then display[#display + 1] = di end
  end
  -- ordem de `display` = ordem do Ranker (ADR-07)
  local page = g_shopMenu.pageShopItemDetails
  if not state.prevCategory then state.prevCategory = GuiState.captureCurrent(g_shopMenu) end
  page:setDisplayItems(display)
  page:setCategory("SSS_SEARCH", headerText(query, #display), ShopMenu.SLICE_ID.VEHICLES)
  -- pushDetail/popDetail conforme G6 (popDetail antes se a página atual já é SSS_SEARCH)
  ```
  Toda chamada de GUI tem guarda `type(x) == "function"` (P7). A falha de qualquer guarda chama `state:degrade("gui: <função>")`.
- **Estado vazio (RF-005/G11)**: com `#display == 0`, a categoria virtual abre vazia com cabeçalho `sss_results_empty` (texto "Nenhum resultado para “…”"). Se a F5 mostrar que a página não aceita lista vazia, exibe uma notificação (`g_currentMission:showBlinkingWarning` ou equivalente confirmado) e mantém a listagem atual.
- **Limpar (RF-004, L3)**: `clear()` = `SearchState:clear()` (texto, filtros de UI, contexto) + `popDetail()` + restauração de `prevCategory`. É acionado por um segundo botão `sss_clear`, visível só quando há busca ativa, e por consulta vazia no diálogo.
- `state:onChange` → em `degraded`, oculta o botão, desliga o input e faz `popDetail` se `SSS_SEARCH` estiver aberta.

**Create**: `src/app/SearchState.lua` — `{text, ui = UiFilters, context, prevCategory}`; `clear()`; `isActive()`.

**Create**: `src/adapters/InputAdapter.lua` — `bind()`: se não estiver registrado, `g_inputBinding:registerActionEvent(InputAction.SMART_SHOP_SEARCH, self, cb, false, true, false, true)`, guarda o `eventId`, e aplica `setActionEventTextVisibility`/`setActionEventTextPriority`. `unbind()`: `removeActionEvent(eventId)`. Idempotente (corrige D7). Registrado no contexto do menu conforme a F5 (RF-002).

**Modify**: `src/app/Console.lua` — completar os comandos do PRD §13.2: `sssQuery <texto>` (AST + top 10 + score + `reasons`), `sssExplain <xmlFilename> <texto>`, `sssDumpCatalog` (reaproveita o formato do spike, agora via `StoreCatalogSource`) e `sssBench <n>` (consultas embutidas de `app/BenchQueries.lua`). Os três últimos exigem `settings.debug.enabled`.

**Modify**: `src/adapters/GameBootstrap.lua` — em `loadMap`: instanciar `StoreCatalogSource`, `XmlDataLoader`, `LinguisticData` e `SearchService`, depois `ShopGuiAdapter.install()`. Tudo em `SafeCall`.

**Modify**: `src/manifest.lua` — `app/SearchState.lua`, `app/BenchQueries.lua`, `adapters/SpecExtractor.lua`, `adapters/StoreCatalogSource.lua`, `adapters/InputAdapter.lua`, `adapters/ShopGuiAdapter.lua`.

**Modify**: `src/translations/translation_*.xml` — `sss_button_search`, `sss_clear`, `sss_results_header` ("Pesquisa: %s (%d)"), `sss_results_empty`, `sss_indexing`.

**Modify**: `docs/release-checklist.md` — roteiros de smoke G1–G6, G11, G12, cada um com passos e resultado esperado, e "contagem de linhas `[SmartShopSearch]` no log após 20 buscas ≤ 3" (RNF-009, AC-PUB-02).

**Create**: `tests/unit/searchstate_spec.lua` — `clear()` zera todos os campos (L3).

### Success Criteria

#### Automated Verification
- [ ] `make ci` verde.
- [ ] `make verify`: o manifesto inclui todos os adapters; as traduções têm as novas chaves.

#### Manual Verification
- [ ] Na loja: o botão aparece só nas páginas elegíveis; a hotkey (rebindável em Controles) abre o diálogo (RF-001/002).
- [ ] `trtor jon dere entre 200 e 300 cv por menos de 150 mil` mostra tratores John Deere da faixa, na ordem do `sssQuery` (RF-003, ADR-07).
- [ ] Consulta sem resultado mostra o estado vazio sem erro (RF-005).
- [ ] "Limpar" volta à listagem anterior e a próxima busca não herda filtros (RF-004).
- [ ] Compra e detalhes de um item a partir da categoria virtual funcionam normalmente.
- [ ] Forçar erro (settings de debug `simulateFailure="gui"`, suportado por `ShopGuiAdapter` somente em debug) → a loja continua funcional, o botão some e o log tem uma única linha de erro (RF-060, AC-RES-03).
- [ ] `log.txt` sem erros; ≤ 3 linhas `info` do mod na sessão.

**⏸ PAUSE**: aguardar confirmação humana antes da Fase 7.

---

## Phase 7: GUI avançada (busca incremental, filtros, explicações)

### Goal
Entregar busca incremental, painel de filtros estruturados e exibição discreta de explicações, cada um implementado ou formalmente registrado como indisponível.

### Changes

**Create**: `src/gui/SmartShopSearchFrame.xml` + `src/gui/profiles.xml` — somente se a F5 marcou G7/G8 como viáveis: elemento `TextInput` com perfil derivado do perfil nativo de campo de texto e botões de filtro (Categoria, Marca, Preço, Potência, Capacidade, Origem, Tipo), usando os perfis nativos existentes (§8.2: não re-estilizar nativos).

**Modify**: `src/adapters/ShopGuiAdapter.lua`
- **Incremental (G7/ADR-08)**: se viável e `settings.ui.incremental`, o `onTextChanged` do campo embutido agenda a busca com *debounce* de 150 ms via um contador por frame registrado **só** enquanto a loja está aberta (sem `update(dt)` permanente, §15 PRD). Se não for viável, `TextInputDialog` continua sendo o modo suportado e `api-limitations.md` registra G7 como `unavailable` com evidência. RF-003 continua atendido, porque a lista atualiza a cada confirmação sem reiniciar a loja.
- **Filtros (G8, RF-043..047)**: cada botão abre uma seleção (`MultiTextOption` ou diálogo de opções nativo confirmado na F5) com valores dos facets do índice: categorias e marcas presentes, `origin` base/dlc/mod (se RF-047 = implemented), espécie (se S-03). Faixas de preço/specs em degraus predefinidos por grandeza (`app/FilterPresets.lua`: preço 0–50k/50–150k/150–300k/300k+; potência 0–100/100–200/200–300/300–400/400+ cv exibidos na unidade do jogador; capacidade idem). Só aparecem specs com cobertura ≥ 30% no índice atual (RF-046: "expostos de forma consistente"). Qualquer mudança dispara `search(state.text, state.ui)` (RF-003).
- **Explicações (G9, RF-052)**: com `settings.ui.showReasons = true` (opção no menu de configurações do mod, ou `sssSet showReasons 1` se não houver UI de settings), o detalhe do item selecionado mostra até 4 linhas `✓ <campo>: <detalhe>`, geradas por `app/ReasonFormatter.lua` a partir de `MatchReason` com textos traduzidos (`sss_reason_exact`, `sss_reason_fuzzy`, `sss_reason_alias`, `sss_reason_constraint`, `sss_reason_compat`). Ponto de inserção conforme G9 da F5. Se inviável, `api-limitations.md` RF-052 = `unavailable`, e o `sssExplain` continua expondo as explicações.

**Create**: `src/app/FilterPresets.lua`, `src/app/ReasonFormatter.lua`, `tests/unit/reason_formatter_spec.lua` (formato das linhas; unidade de exibição métrica/imperial; nunca lança erro com `reason` incompleto).

**Modify**: `src/adapters/SettingsStore.lua` — persistir `showReasons` e `incremental`.
**Modify**: `src/translations/translation_*.xml` — chaves de filtros, presets e razões.
**Modify**: `src/manifest.lua` — novos arquivos.
**Modify**: `docs/api-limitations.md` — G7, RF-046, RF-047 e RF-052 com status final.

### Success Criteria

#### Automated Verification
- [ ] `make ci` verde; `build.py` valida que os XML de `gui/` são bem-formados e que todas as chaves `sss_` existem em `en`.

#### Manual Verification
- [ ] Digitação incremental atualiza a lista sem travar (ou limitação registrada) — RF-003, RNF-001.
- [ ] Filtros de categoria, marca, preço, specs e origem restringem os resultados e se combinam com a consulta textual — RF-043..047.
- [ ] Explicações aparecem discretamente só com a opção ativa — RF-052.
- [ ] Limpar zera texto **e** filtros — RF-004.

**⏸ PAUSE**: aguardar confirmação humana antes da Fase 8.

---

## Phase 8: Compatibilidade entre equipamentos

### Goal
Responder "compatíveis com este veículo" (GUI e texto) usando somente evidências de dados do jogo, com a evidência em cada `MatchReason`.

### Changes

**Create**: `src/core/compat/CompatibilityResolver.lua` (Lua puro)
```lua
---@class CompatInfo
---@field attach table<string, boolean>       -- tipos de junta que o veículo oferece
---@field inputAttach table<string, boolean>  -- tipos de junta que o implemento aceita
---@field power number|nil                    -- kW
---@field neededPower number|nil              -- kW
---@field combinations table<string, boolean> -- xmlFilename declarados

---@return {level:"declared"|"joint", evidence:string[], powerOk:boolean|nil}|nil
function CompatibilityResolver.evaluate(vehicle, implement)
    local ev = {}
    local level
    if implement.combinations[vehicle.xmlFilename] or vehicle.combinations[implement.xmlFilename] then
        level = "declared"; ev[#ev + 1] = "combinação declarada"
    end
    for jt in pairs(implement.inputAttach) do
        if vehicle.attach[jt] then
            level = level or "joint"; ev[#ev + 1] = "engate " .. jt
        end
    end
    if not level then return nil end -- RF-050: sem evidência técnica, sem compatibilidade
    local powerOk = nil
    if vehicle.power and implement.neededPower then powerOk = vehicle.power >= implement.neededPower end
    return { level = level, evidence = ev, powerOk = powerOk }
end
```
Regras: `level=declared` soma `W.compat.declared = 1.0`, `joint` soma `0.7`. `powerOk == false` **não** exclui, mas penaliza (`0.3`) e aparece no motivo ("potência insuficiente: precisa 150 cv"). Texto nunca entra na decisão.

**Create**: `src/adapters/CompatibilityExtractor.lua` — sob demanda, com cache por `xmlFilename`: lê do XML do item (caminhos confirmados na F5 §9) os `attacherJoints`/`inputAttacherJoints` (tipo de junta) e as combinações declaradas. `neededPower`/`power` vêm do índice. É executado fatiado ao abrir a consulta de compatibilidade: primeiro o alvo, depois os candidatos das categorias de implemento, com indicador `sss_indexing` enquanto processa. Falha por item → sem `CompatInfo` → item não aparece como compatível (conservador).

**Modify**: `src/app/SearchService.lua` — quando `q.context.kind == "compatibleWith"`:
- `target="selected"`: o alvo vem de `ShopGuiAdapter:selectedItem()` (G10). Se não houver seleção, `warning` + a consulta segue sem o contexto.
- `target="query"`: busca `targetTerms` e usa o top-1 **só** se `score ≥ 0.6` e a distância para o 2º for ≥ 0.1; senão emite `warning` "alvo ambíguo" e mostra os alvos candidatos. A escolha do alvo usa texto, mas a compatibilidade em si não (RF-050).
- Candidatos = itens com `CompatibilityResolver.evaluate(target, item) ~= nil`, depois os termos/filtros restantes, e `reasons` com `kind="compat"` e o `detail` da evidência.

**Modify**: `src/adapters/ShopGuiAdapter.lua` — botão contextual `sss_compat_button` ("Compatíveis") na página de detalhes quando o item selecionado é veículo motorizado ou implemento (G10), que executa a busca com `context={kind="compatibleWith", target="selected"}`.

**Modify**: `src/manifest.lua`, `src/translations/*`, `src/data/*/context.xml` (frases de `en/de/fr`).

**Create**: `tests/fixtures/compat/joints.xml` — pares de veículo/implemento com joints e combinações (compatível declarado, compatível por junta, incompatível, sem dados, potência insuficiente, e um par com nomes idênticos sem evidência).
**Create**: `tests/unit/compat_spec.lua` — cada cenário. **Caso obrigatório RF-050**: itens com nome/marca iguais e sem joints/combinações → `nil`.
**Modify**: `tests/golden/queries.pt.xml` — `ctx-compat` passa a validar, com o alvo sintético selecionado no stub, que só retornam implementos com evidência.

**Modify**: `docs/api-limitations.md` — RF-048 com status final (se a F5 não encontrou joints/combinações acessíveis: `unavailable` + evidência. O parser e o resolver permanecem, atendendo RF-049 "permitir evolução").

### Success Criteria

#### Automated Verification
- [ ] `make ci` verde; `compat_spec` inclui o caso "sem evidência → não compatível".

#### Manual Verification
- [ ] Selecionar um trator → "Compatíveis" lista implementos com engate compatível; o detalhe mostra a evidência (RF-048, RF-051).
- [ ] "implementos compatíveis com este trator" no diálogo, com o trator selecionado, dá o mesmo resultado (RF-049).
- [ ] O tempo até exibir fica ≤ 1 s em catálogo base, com indicador durante o processamento.

**⏸ PAUSE**: aguardar confirmação humana antes da Fase 9.

---

## Phase 9: Endurecimento, calibração e release

### Goal
Cumprir a Definição de Pronto (requisitos §25): calibração do ranking sobre os dumps reais, traduções completas, performance com 100+ mods, matriz de compatibilidade, TestRunner, checklist ModHub vigente e pacote 1.0.0.

### Changes

**Modify**: `src/core/rank/Weights.lua` — calibrar com `tools/calibrate.lua` (grid search limitado sobre `wCampo`, `wTipo`, `minScoreRel` e penalidades, maximizando o MRR do corpus sem piorar nenhum caso). Os valores finais são registrados em `docs/adr/0015-ranking-weights.md` (responde à calibração exigida em RF-040).
**Create**: `tools/calibrate.lua` — reutiliza `tests/golden/runner.lua`.
**Modify**: `tests/golden/queries.*.xml` — marcar os casos-chave com `fixtures="synthetic,base,base+dlc,base+mods"`; adicionar ≥ 20 consultas reais observadas nos smoke tests.
**Modify**: `tests/bench/run.lua` — usar também `base+mods.xml` e registrar metas no PC de referência (Q-05). Os orçamentos do PRD §15 viram a baseline final (RNF-001..003, RMH-008, DoD-06).
**Modify**: `src/translations/translation_*.xml` e `src/data/{pt,en,de,fr}/*` — revisão completa. O `build.py` falha se alguma chave usada faltar em `en`, `br` ou `pt` (RF-057/058).
**Modify**: `docs/release-checklist.md` — executar e assinar (com data):
- Smoke G1–G12 (§8.1 PRD) em SP.
- MP host+cliente e servidor dedicado (P5): o dedicado registra `disabled-dedicated` e nenhum erro.
- Matriz de compatibilidade do PRD §16.2, incluindo `FS25_ShopSearch` ativo simultaneamente, Enhanced Shop Sorting, Garage Menu, Vehicle Years, mods incompletos e pacote de 100+ mods (RMH-009).
- Remoção do mod: savegame usado com o mod carrega sem erros e a loja fica normal (RNF-010, AC-RES-04).
- Log: zero erros/avisos do mod; ≤ 3 linhas `info` (RMH-005, RNF-009).
- Checklist de conformidade do PRD §17 revisado contra as regras do ModHub **vigentes na data** (RMH-011, DoD-10).
- DoD-01..10 marcados.
**Modify**: `docs/api-limitations.md` — nenhum `pending` (o `build.py --release` falha caso contrário; DoD-03).
**Modify**: `CHANGELOG.md` → `## 1.0.0 — <data>`; `src/modDesc.xml` version `1.0.0.0`; revisão final de título/descrição/ícone (RMH-002).
**Command**: `python tools/build.py --release` → `pwsh tools/run_testrunner.ps1 -Zip dist/FS25_SmartShopSearch-1.0.0.zip` (RMH-004) → tag `v1.0.0` → GitHub Release com ZIP + `SHA256SUMS` → upload manual no ModHub.

### Success Criteria

#### Automated Verification
- [ ] `make ci` verde com fixtures reais; as métricas golden não pioram em relação à F8.
- [ ] `python tools/build.py --release` passa (inclui `check_trace.py --release`: zero `pending`, 100% dos ids rastreados).
- [ ] TestRunner: zero erros; avisos justificados no checklist.
- [ ] `make bench` dentro das metas do PRD §15 no PC de referência.

#### Manual Verification
- [ ] `docs/release-checklist.md` 100% executado e assinado, com data.
- [ ] Todos os `AC-*` do Apêndice A.4 com status "ok" em `docs/traceability.md`.

**⏸ PAUSE**: release só após aprovação humana do checklist.

---

## Testing Strategy

### Unit Tests
- `tests/unit/`: `app_spec` (estados, SafeCall), `text_spec` (Utf8, normalizer, tokenizer), `index_spec` (builder, signature, não mutação, dados ausentes/malformados), `fuzzy_spec` (OSA, trigramas, limiares, frase), `alias_spec` (multi-idioma), `parser_spec` (≥ 60 casos), `filter_spec` (facets, faixas, L10), `rank_spec` (pesos, cobertura, penalidades, ordenação determinística), `resilience_spec` (falhas injetadas), `searchstate_spec`, `reason_formatter_spec`, `compat_spec`.
- Edge cases obrigatórios: consulta vazia/espaços; só stopwords; só números; 80 caracteres; caracteres mágicos Lua; bytes UTF-8 inválidos; catálogo vazio; catálogo com 1 item; itens duplicados por `xmlFilename`; specs NaN/negativas/string.

### Property Tests (`tests/prop/`)
Idempotência da normalização; OSA simétrica e ≤ Levenshtein; `parse` total (nunca lança) e conservação de spans; `search` nunca lança com consultas aleatórias sobre o fixture sintético.

### Golden / Integration Tests
- `tests/golden/queries.{pt,en}.xml` × fixtures (`synthetic` desde a F2; `base`, `base+dlc`, `base+mods` desde a F5). Todo `AC-*` tem ao menos um caso ou item de smoke nominal. Métricas: precisão@5, MRR, taxa de vazios.
- Integração em jogo: smoke G1–G12, matriz de compatibilidade, MP/dedicado, remoção do mod (`docs/release-checklist.md`).

### Performance
`tests/bench/run.lua` em todo PR (tolerância 20%) e `sssBench` em jogo antes da release.

### Migration & Rollback
- Sem dados persistentes além de `modSettings/FS25_SmartShopSearch/settings.xml` (opcional). Não há migração de savegame.
- Rollback = remover ou substituir o ZIP; o savegame não referencia o mod (ADR-09).
- Em patch do FS25 que quebre a GUI: o mod entra em `degraded` automaticamente (loja intacta). A correção se restringe a `adapters/` e a uma nova entrada em `docs/api-findings/`.

## Environment Considerations
- **CI/CD**: GitHub Actions (job Linux em todo PR; job Windows TestRunner em tags `v*`/`workflow_dispatch`, runner self-hosted opcional).
- **Migrations**: nenhuma.
- **Config/Secrets**: nenhum segredo. `FS25_TESTRUNNER` (caminho do executável) no runner Windows. `settings.xml` de debug só na máquina do desenvolvedor, nunca no pacote.
- **Multi-environment**: dev Linux (núcleo, CI); Windows/Proton (jogo, TestRunner); em jogo, SP, MP host/cliente e servidor dedicado (sem GUI → `disabled-dedicated`).

## Dependencies & Risks
- **F5 condiciona F6–F8**: APIs `[A VALIDAR]` inexistentes → alternativa do PRD ou registro `unavailable` (regras de decisão da F5). R1/R5 do PRD.
- **Ids reais de categoria/marca** só com os dumps: o corpus sintético usa ids plausíveis. A correção é só de dados (aliases), sem mudança de código.
- **Custo de XML** (specs secundárias, compatibilidade): sempre fatiado, sob demanda e com cache (R4).
- **Diferença entre Lua 5.1 de referência e o runtime do jogo** (R11): o smoke em jogo exercita o `core/` via `sssQuery`/`sssBench` com o mesmo corpus.
- **Coexistência com `FS25_ShopSearch`**: action própria e tecla distinta (S-05), sem campos em `g_shopMenu`.
- **Regras do ModHub vigentes** (R8): revisão datada no checklist.

## References
- PRD: `docs/PRD-base-tecnica.md`
- Requisitos: `requisitos.md` v1.1
- Referência técnica: https://github.com/w33zl/FS25_ShopSearch @ d4166f7 (somente estudo; ADR-01)

---

## Apêndice A — Matriz de cobertura dos requisitos

Formato idêntico a `docs/traceability.md` (Id | Componente | Verificação | Fase). Esta é a garantia de que o spec cobre **todos** os itens de `requisitos.md`.

### A.1 Requisitos funcionais

| Id | Componente | Verificação | Fase |
|---|---|---|---|
| RF-001 | ShopGuiAdapter (botão), InputAdapter | smoke:G1,G2 | F6 |
| RF-002 | InputAdapter, modDesc action SMART_SHOP_SEARCH | smoke:G4 (rebind em Controles); api-limitations | F6 |
| RF-003 | SearchService, ShopGuiAdapter (show, incremental, filtros) | smoke:G6,G7,G8 | F6/F7 |
| RF-004 | SearchState.clear, ShopGuiAdapter.clear | unit:searchstate_spec; smoke:G12 | F6/F7 |
| RF-005 | SearchService (vazio), ShopGuiAdapter (estado vazio) | golden:res-empty,filter-empty; smoke:G11 | F2/F6 |
| RF-006 | StoreCatalogSource, IndexBuilder (name) | golden:cmp-multi | F2/F6 |
| RF-007 | IndexBuilder (brand), AliasResolver | golden:txt-upper,fuzzy-jon-dere | F2/F3 |
| RF-008 | IndexBuilder (category), AliasResolver | golden:txt-trator | F3 |
| RF-009 | StoreCatalogSource (modTitle), IndexBuilder (mod) | golden:mod-name; api-limitations | F2/F6 |
| RF-010 | StoreCatalogSource (author), IndexBuilder (author) | golden:mod-author; api-limitations | F2/F6 |
| RF-011 | SpecExtractor, SpecRegistry, IndexBuilder (specs) | golden:unit-power,unit-cap; api-findings §8 | F4/F6 |
| RF-012 | TextNormalizer | unit:text_spec; golden:txt-upper,txt-trator-upper | F2 |
| RF-013 | Utf8.fold, TextNormalizer | unit:text_spec; golden:txt-accent | F2 |
| RF-014 | TextNormalizer (colapso/trim) | unit:text_spec; golden:txt-spaces | F2 |
| RF-015 | Tokenizer | unit:text_spec; prop:normalizer_prop | F2 |
| RF-016 | FuzzyMatcher, Osa (remoção) | unit:fuzzy_spec; golden:fuzzy-trtor | F3 |
| RF-017 | FuzzyMatcher, Osa (inserção) | golden:fuzzy-insert | F3 |
| RF-018 | FuzzyMatcher, Osa (substituição) | golden:fuzzy-subst | F3 |
| RF-019 | Osa (transposição) | unit:fuzzy_spec; golden:fuzzy-tratro | F3 |
| RF-020 | FuzzyMatcher.matchPhrase, AliasResolver | golden:fuzzy-jon-dere,fuzzy-jhon-deere,fuzzy-john-dere | F3 |
| RF-021 | Weights.fuzzyMaxByLen, Ranker minScore | golden:neg-noise,neg-unrelated | F3 |
| RF-022 | FuzzyMatcher.maxDistFor (≤3 → 0), penalty.shortToken | golden:neg-short; unit:fuzzy_spec | F3 |
| RF-023 | AliasResolver + data/<lang>/aliases.xml | unit:alias_spec; golden:alias-carreta | F3 |
| RF-024 | data/*/aliases.xml (categorias FS25/agro, marcas) | golden:alias-carreta,fuzzy-pulverizdor | F3/F5 |
| RF-025 | LinguisticData (por locale) | unit:alias_spec (de); golden:queries.en | F3 |
| RF-026 | NumberParser | unit:parser_spec; golden:num-int | F4 |
| RF-027 | UnitParser (power), units.xml | golden:unit-power,unit-hp | F4 |
| RF-028 | UnitParser (volume), NumberParser (mil) | golden:unit-cap,num-local | F4 |
| RF-029 | NumberParser, TextNormalizer (moeda, L8), regra L9 | golden:num-mil,num-rs | F4 |
| RF-030 | UnitParser.toCanonical, units.xml | golden:unit-conv; unit:parser_spec | F4 |
| RF-031 | ComparatorParser (gt/gte) | golden:cmp-gt | F4 |
| RF-032 | ComparatorParser (lt/lte) | golden:cmp-lt | F4 |
| RF-033 | ComparatorParser (range) | golden:cmp-range | F4 |
| RF-034 | QueryParser, FilterEngine | golden:composite-01 | F4 |
| RF-035 | QueryParser (concepts+constraints+terms) | golden:composite-01,cmp-cat-brand | F4 |
| RF-036 | QueryParser (termos remanescentes, warnings) | golden:partial,partial-bad; prop:parser_prop | F4 |
| RF-037 | SearchScorer | unit:rank_spec | F2 |
| RF-038 | Weights.types (exact>fuzzy) | golden:rank-exact-fuzzy | F3 |
| RF-039 | FuzzyMatcher.sim, Weights.types.fuzzy1/2 | unit:rank_spec,fuzzy_spec | F3 |
| RF-040 | Weights.fields; calibração | unit:rank_spec; golden:rank-field; adr:0015 | F2/F9 |
| RF-041 | SearchScorer (coverage) | unit:rank_spec; golden:cmp-multi | F2 |
| RF-042 | SearchScorer.penalties | unit:rank_spec; golden:rank-weak | F2/F3 |
| RF-043 | FilterEngine (facet category), painel G8 | unit:filter_spec; smoke:G8 | F4/F7 |
| RF-044 | FilterEngine (facet brand), painel G8 | unit:filter_spec; smoke:G8 | F4/F7 |
| RF-045 | FilterEngine (price), FilterPresets | unit:filter_spec; smoke:G8 | F4/F7 |
| RF-046 | FilterEngine (specs, cobertura ≥30%) | unit:filter_spec; smoke:G8; api-limitations | F4/F7 |
| RF-047 | IndexBuilder (origin), facet origin | golden:origin-dlc; smoke:G8; api-limitations | F4/F7 |
| RF-048 | CompatibilityExtractor, CompatibilityResolver | unit:compat_spec; smoke:G10; api-limitations | F8 |
| RF-049 | ContextParser, SearchService (context), botão G10 | golden:ctx-compat; smoke:G10 | F4/F8 |
| RF-050 | CompatibilityResolver (sem evidência → nil) | unit:compat_spec (caso obrigatório) | F8 |
| RF-051 | MatchReason, SearchScorer, FilterEngine | unit:rank_spec (reasons sempre); golden:rank-field; console:sssQuery | F2/F4 |
| RF-052 | ReasonFormatter, ShopGuiAdapter (G9) | unit:reason_formatter_spec; smoke:G9; api-limitations | F7 |
| RF-053 | Spike F5 | api-findings §5 | F5 |
| RF-054 | ModHubCatalogSource (condicional, ADR-12) | api-limitations | F5/F9 |
| RF-055 | Porta CatalogSource (adaptador separado) | check_deps; revisão ADR-12 | F1/F5 |
| RF-056 | ADR-12; check_deps (sem rede) | deps; api-limitations (evidência) | F1/F5 |
| RF-057 | translations/translation_br.xml, data/pt | build.py (chaves br/pt) | F1/F9 |
| RF-058 | translations/*.xml, data/<lang> (fora do código) | build.py (chaves); deps | F1 |
| RF-059 | LinguisticData, data/<lang>/aliases.xml | unit:alias_spec (troca de locale) | F3 |
| RF-060 | SafeCall, StateMachine.degrade, HookRegistry | unit:app_spec,resilience_spec; smoke simulateFailure | F1/F6 |
| RF-061 | IndexBuilder (campos opcionais) | unit:index_spec (sem marca) | F2 |
| RF-062 | IndexBuilder (pcall por item), StoreCatalogSource | unit:index_spec; golden:res-magic | F2/F6 |

### A.2 Requisitos não funcionais

| Id | Componente | Verificação | Fase |
|---|---|---|---|
| RNF-001 | IndexBuilder.step fatiado, debounce, sem update permanente | bench; smoke G7 | F2/F7 |
| RNF-002 | SearchIndex, TrigramIndex | bench (p95 ≤5/15 ms) | F2–F4 |
| RNF-003 | IndexedItem.ref somente leitura, strings uma vez | bench (≤8 MB); unit:index_spec (não mutação) | F2 |
| RNF-004 | Núcleo local; sem rede (L1) | deps:offline/lua51 | F1 |
| RNF-005 | core/text, lang, index, match, rank, compat; adapters/GUI | deps:core-purity; revisão | F1–F8 |
| RNF-006 | SpecRegistry, units.xml, data/<lang>, Weights | unit:alias_spec (novo idioma só dados) | F3/F4 |
| RNF-007 | HookRegistry (append preferencial, específicos) | revisão; matriz compat | F1/F6/F9 |
| RNF-008 | GameLogger, Diagnostics | smoke (log) | F1/F6 |
| RNF-009 | GameLogger (rate limit, ≤3 info) | smoke (contagem de linhas) | F1/F6 |
| RNF-010 | ADR-09 (sem savegame), modSettings | smoke remoção do mod | F6/F9 |

### A.3 Requisitos de ModHub

| Id | Componente | Verificação | Fase |
|---|---|---|---|
| RMH-001 | src/modDesc.xml, build.py | verify | F1/F5 |
| RMH-002 | modDesc title/description/icon | verify; checklist | F1/F9 |
| RMH-003 | build.py allowlist | verify | F1 |
| RMH-004 | run_testrunner.ps1, job CI testrunner | relatório TestRunner | F5/F9 |
| RMH-005 | GameLogger | checklist log | F6/F9 |
| RMH-006 | release-checklist (smoke) | checklist | F9 |
| RMH-007 | SafeCall, degraded | checklist; matriz | F9 |
| RMH-008 | bench, orçamentos §15 | bench; sssBench | F9 |
| RMH-009 | matriz §16.2 | checklist | F9 |
| RMH-010 | deps (sem require/rede); sem mods dependentes | deps; verify (modDesc sem dependencies) | F1 |
| RMH-011 | checklist datado; TestRunner atual | checklist | F9 |

### A.4 Critérios de aceitação (requisitos §21)

| Id | Critério | Verificação | Fase |
|---|---|---|---|
| AC-TXT-01 | `trator` encontra tratores | golden:txt-trator | F3 |
| AC-TXT-02 | `TRATOR` equivalente | golden:txt-trator-upper,txt-upper | F2/F3 |
| AC-TXT-03 | acentuação não quebra | golden:txt-accent | F2 |
| AC-TXT-04 | espaços redundantes | golden:txt-spaces | F2 |
| AC-FUZ-01 | `trtor` → trator | golden:fuzzy-trtor | F3 |
| AC-FUZ-02 | `tratro` → trator | golden:fuzzy-tratro | F3 |
| AC-FUZ-03 | `jon dere` → John Deere | golden:fuzzy-jon-dere | F3 |
| AC-FUZ-04 | `jhon deere` → John Deere | golden:fuzzy-jhon-deere | F3 |
| AC-FUZ-05 | `pulverizdor` → pulverizador | golden:fuzzy-pulverizdor | F3 |
| AC-FUZ-06 | não relacionados sem relevância alta | golden:neg-noise,neg-unrelated | F3 |
| AC-CMP-01 | múltiplos termos influenciam ranking | golden:cmp-multi | F2 |
| AC-CMP-02 | partes não interpretadas continuam pesquisáveis | golden:partial | F4 |
| AC-CMP-03 | categoria + marca | golden:cmp-cat-brand | F3 |
| AC-NUM-01 | inteiros identificados | golden:num-int; unit:parser_spec | F4 |
| AC-NUM-02 | `150 mil` normalizado | golden:num-mil | F4 |
| AC-NUM-03 | formatos localizados | golden:num-local,num-local-dec | F4 |
| AC-UNI-01 | potência identificável | golden:unit-power | F4 |
| AC-UNI-02 | capacidade identificável | golden:unit-cap | F4 |
| AC-UNI-03 | unidades equivalentes normalizadas | golden:unit-conv,unit-hp | F4 |
| AC-CMP2-01 | `acima de X` → limite inferior | golden:cmp-gt,num-int | F4 |
| AC-CMP2-02 | `abaixo de X` → limite superior | golden:cmp-lt | F4 |
| AC-CMP2-03 | `entre X e Y` → intervalo | golden:cmp-range | F4 |
| AC-RNK-01 | exato supera fuzzy | golden:rank-exact-fuzzy | F3 |
| AC-RNK-02 | cobertura maior aumenta relevância | unit:rank_spec | F2 |
| AC-RNK-03 | matches fracos penalizados | golden:rank-weak; unit:rank_spec | F3 |
| AC-RNK-04 | pesos de nome/categoria/marca | golden:rank-field; unit:rank_spec | F2 |
| AC-MOD-01 | itens de mods indexados | golden:mod-indexed (+ base+mods F5) | F2/F5 |
| AC-MOD-02 | nome do mod pesquisável | golden:mod-name | F2 |
| AC-MOD-03 | autor pesquisável | golden:mod-author | F2 |
| AC-RES-01 | sem resultado não gera erro | golden:res-empty | F2 |
| AC-RES-02 | metadado ausente não quebra indexação | unit:index_spec | F2 |
| AC-RES-03 | falha interna não inutiliza a loja | unit:resilience_spec; smoke simulateFailure | F2/F6 |
| AC-RES-04 | remoção do mod restaura comportamento | smoke remoção | F9 |
| AC-PUB-01 | TestRunner aprovado | relatório TestRunner | F9 |
| AC-PUB-02 | log sem erros do mod | checklist log | F9 |
| AC-PUB-03 | estrutura do ZIP | verify | F1/F9 |
| AC-PUB-04 | metadados completos | verify; checklist | F9 |
| AC-PUB-05 | testes funcionais antes da submissão | checklist assinado | F9 |

### A.5 Questões obrigatórias (requisitos §24)

| Id | Questão | Resposta / onde | Fase |
|---|---|---|---|
| QM-01 | Ponto de extensão mais seguro da GUI | api-findings §2; ShopGuiAdapter (G1–G6) | F5 |
| QM-02 | Campos confiáveis do StoreItem | api-findings §2, §8 (cobertura por perfil) | F5 |
| QM-03 | Specs indexáveis genericamente | api-findings §8; SpecRegistry | F5 |
| QM-04 | Extração de atributos sem acoplamento | SpecExtractor em camadas (PRD §9.2) | F5/F6 |
| QM-05 | Algoritmo fuzzy | trigramas + OSA + fuzzy de frase (ADR-05, ADR-14) | F3 |
| QM-06 | Limiar por tamanho | Weights.fuzzyMaxByLen | F3 |
| QM-07 | Cálculo do score | SearchScorer (§2.4 deste spec) | F2 |
| QM-08 | Quando construir o índice | IndexLifecycle na 1ª abertura (ADR-04) | F2/F6 |
| QM-09 | Invalidação/reconstrução | Signature + sssReindex | F2 |
| QM-10 | Localização de aliases | LinguisticData, data/<lang> (S-06) | F3 |
| QM-11 | Representação da consulta | Query AST (§4.2 deste spec) | F4 |
| QM-12 | Compatibilidade sem inferência falsa | CompatibilityResolver (F8) | F8 |
| QM-13 | Hooks que minimizam conflito | api-findings §2; HookRegistry | F5 |
| QM-14 | Tela do ModHub acessível | api-findings §5 | F5 |
| QM-15 | Funcionalidades permitidas pelo ModHub | api-findings §2; checklist datado | F5/F9 |
| QM-16 | Regressão automatizada | golden + prop + unit (make test) | F2 |
| QM-17 | TestRunner repetível | run_testrunner.ps1 + job CI | F1/F5 |
| QM-18 | Pontos da referência ainda adequados | api-findings §3 | F5 |
| QM-19 | O que reaproveitar conceitualmente | PRD §2.3/§2.4 + api-findings §3 | F5 |
| QM-20 | Licença vigente da referência | PRD §2.5 + reconfirmação datada em api-findings §2 | F5 |

(`QM-01..20` = questões do §24 dos requisitos. As questões abertas do PRD §21, Q-01..Q-08, estão resolvidas em S-02..S-07.)

### A.6 Definição de pronto (requisitos §25)

| Id | Item | Verificação | Fase |
|---|---|---|---|
| DOD-01 | requisitos aplicáveis implementados | check_trace --release | F9 |
| DOD-02 | critérios de aceitação satisfeitos | A.4 todos ok | F9 |
| DOD-03 | condicionais implementadas ou unavailable com evidência | api-limitations sem pending | F9 |
| DOD-04 | testes funcionais executados | checklist | F9 |
| DOD-05 | regressão de busca aprovada | make golden | F9 |
| DOD-06 | desempenho dentro das metas | make bench; sssBench | F9 |
| DOD-07 | sem erros do mod | checklist log | F9 |
| DOD-08 | pacote preparado | build --release | F9 |
| DOD-09 | TestRunner aprovado | relatório | F9 |
| DOD-10 | requisitos vigentes do ModHub revisados | checklist datado | F9 |

### A.7 Entregáveis da Modelagem (requisitos §26)

| Id | Entregável | Onde |
|---|---|---|
| DEL-01 | arquitetura de componentes | PRD §5; Convenções; manifest.lua |
| DEL-02 | fluxo de inicialização | PRD §7; GameBootstrap (F1/F6) |
| DEL-03 | integração com a API do FS25 | adapters/* (F6); api-findings |
| DEL-04 | integração com a GUI | ShopGuiAdapter (F6/F7) |
| DEL-05 | modelo do índice | SearchIndex (F2) |
| DEL-06 | modelo da consulta | Query AST (F4) |
| DEL-07 | modelo do resultado | SearchResult/MatchReason (F1/F2) |
| DEL-08 | algoritmo fuzzy | Osa/Trigram/Phrase (F3) |
| DEL-09 | algoritmo de scoring | SearchScorer (F2), calibração (F9) |
| DEL-10 | parser de linguagem | core/lang (F4) |
| DEL-11 | estratégia de compatibilidade | F8 |
| DEL-12 | estratégia de localização | S-06, LinguisticData, translations |
| DEL-13 | estratégia de testes | Testing Strategy |
| DEL-14 | pipeline de validação/TestRunner | build.py, CI, run_testrunner.ps1 |
| DEL-15 | estrutura final de arquivos | PRD §5.3/§5.4 + manifesto |
| DEL-16 | mapeamento RF/RNF/RMH → componente → teste | este Apêndice → docs/traceability.md |

### A.8 Princípios e referência (requisitos §2, §3)

| Id | Item | Atendimento |
|---|---|---|
| PR-01 | Sem MVP | 9 fases compõem a 1.0; nada é cortado (condicionais só via evidência) |
| PR-02 | Requisitos compõem o produto | A.1–A.4 |
| PR-03 | Funciona localmente | RNF-004 / deps |
| PR-04 | Erros de digitação não impedem | F3 |
| PR-05 | Relevância calculada | F2/F3 (score) |
| PR-06 | Preserva a loja em falha | RF-060 |
| PR-07 | Compatibilidade com outros mods | RNF-007, matriz §16.2 |
| PR-08 | Exigências do ModHub | RMH-* |
| PR-09 | Funcionalidades dependentes de API só se suportadas | api-limitations (L2) |
| REF-01 | Referência não é dependência | ADR-01; THIRD_PARTY.md |
| REF-02 | Licença verificada antes de reutilizar | PRD §2.5; reconfirmação em F5 (Q-20) |
| REF-03 | Obrigações em caso de reutilização (5 itens) | Não aplicável: nenhuma cópia (clean-room); revisão de PR |
| REF-04 | Análise dos 10 itens do §2.3 | api-findings §3 (F5) |
| REF-05 | Conclusões confrontadas com a doc da GIANTS | api-findings §1 (evidência LUADOC) |
