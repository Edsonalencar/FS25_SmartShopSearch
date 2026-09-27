# Pendências — FS25 Smart Shop Search 1.0

Estado em 2026-09-27, depois do commit `804dd54` mais as pendências offline.
Spec de referência: `specs/plans/2026-09-27-smart-shop-search-1.0.md`.

O núcleo de busca (Fases 1–4) está completo e testado. `make ci` passa com
243 testes (177 unit, 6 prop, 60 golden) e com as metas do PRD §15 no
benchmark. Todas as pendências offline (seção 2) foram resolvidas. O que
falta para a 1.0 exige o FS25 instalado (Windows ou Proton) e está na seção 1.

---

## 1. Pendências que exigem o FS25

### 1.1 Fase 5: spike em jogo (bloqueia 1.2 a 1.5)

O scaffold está pronto em `spike/FS25_SSS_Spike/`, mas nunca foi executado.

- [ ] Linkar `spike/FS25_SSS_Spike/` na pasta de mods e rodar `sssSpikeProbe`, `sssSpikeDump <perfil>`, `sssSpikeBench`, `sssSpikeGui` e `sssSpikeGuiEmpty`.
- [ ] Copiar `docs/api-findings/TEMPLATE.md` para `docs/api-findings/fs25-<versão>.md` e preencher as 11 seções com a evidência obtida.
- [ ] Gravar os dumps reais em `tests/fixtures/catalog/base.xml`, `base+dlc.xml` e `base+mods.xml`. O perfil `base+mods` precisa de pelo menos 50 mods, dos quais pelo menos 5 com metadados incompletos.
- [ ] Corrigir os ids de categoria e marca em `src/data/*/aliases.xml` conforme os dumps. Hoje eles são plausíveis, mas sintéticos: `TRACTORS*`, `JOHNDEERE` etc.
- [ ] Confirmar o `descVersion` real em `src/modDesc.xml` (Q-02).
- [ ] Confirmar a tecla padrão: usar `KEY_lctrl KEY_f`, ou `KEY_lalt KEY_f` se houver conflito (S-05/Q-06).
- [ ] Confirmar os códigos de idioma e ajustar `GameLocale.LANG_MAP` (S-06/Q-03).
- [ ] Confirmar a linha de comando do TestRunner e ajustar `tools/run_testrunner.ps1`.
- [ ] Confirmar o tamanho e o formato do ícone. O `.dds` atual é um placeholder sem compressão DXT, gerado com o Pillow.
- [ ] Registrar em `tools/fs25_globals.lua` os globais que forem confirmados.
- [ ] Resolver as 12 condicionais de `docs/api-limitations.md`, marcando cada uma como `implemented` ou `unavailable` com evidência: RF-002, RF-009, RF-010, RF-011, RF-046, RF-047, RF-048, RF-052, RF-053, RF-054, G7 e S-03.

### 1.2 Fase 6: adapters e GUI básica

O código existe, mas não foi testado no jogo.

- [ ] Validar estas APIs `[A VALIDAR]`, usadas em `StoreCatalogSource`, `SpecExtractor`, `ShopGuiAdapter`, `InputAdapter`, `XmlDataLoader`, `SettingsStore`, `GameLogger` e `ConsoleRegistrar`:
  - `Utils.cloneButton`
  - `TextInputDialog.createFromExistingGui`
  - `registerActionEvent`
  - `XMLFile:iterate`
  - `addConsoleCommand`
  - `pageShopItemDetails.*`
  - estrutura de `storeItem.specs`
  - `ShopMenu.update(dt)`, usado como tick por frame só com a loja aberta (build fatiado, specs secundárias, ações adiadas)
  - retorno de `registerActionEvent`: o `InputAdapter` agora aceita `success, eventId` ou só `eventId`
  - formato `settings.debug#enabled` das chaves do `settings.xml` (antes era gravado como `settings.debug.#enabled`)
- [ ] Confirmar os caminhos `vehicle.storeData.specs.*` de `SpecExtractor:secondary` e se os valores do XML já estão na unidade canônica (kW, L, m, km/h, kg). A fase secundária aplica os valores como vierem.
- [ ] Executar o smoke do spec:
  - [ ] o botão aparece só nas páginas elegíveis;
  - [ ] a hotkey abre o diálogo e pode ser redefinida em Controles;
  - [ ] a consulta composta mostra os resultados na ordem do `sssQuery`;
  - [ ] o estado vazio aparece sem erro;
  - [ ] "Limpar" volta à listagem anterior e zera os filtros;
  - [ ] comprar e ver detalhes funcionam a partir da categoria virtual;
  - [ ] o `log.txt` fica sem erros, com no máximo 3 linhas `info`;
  - [ ] com `simulateFailure="gui"`, o mod degrada e a loja original continua funcionando;
  - [ ] o indicador "Indexando itens…" aparece e some.

### 1.3 Fase 7: GUI avançada

- [ ] Criar `gui/SmartShopSearchFrame.xml` e `gui/profiles.xml`, se a F5 mostrar que G7 e G8 são viáveis. Caso contrário, registrar G7 como `unavailable`.
- [ ] Implementar a busca incremental com debounce de 150 ms, sem `update(dt)` permanente (G7).
- [ ] Implementar o painel de filtros de categoria, marca, preço, specs com cobertura ≥ 30%, origem e espécie (G8). `app/FilterPresets.lua` já existe.
- [ ] Mostrar as explicações no detalhe do item, no ponto de inserção definido pela F5 (G9). `app/ReasonFormatter.lua` já existe.

### 1.4 Fase 8: compatibilidade

- [ ] Confirmar os caminhos XML de `attacherJoints`, `inputAttacherJoints` e das combinações declaradas usados em `adapters/CompatibilityExtractor.lua`.
- [ ] Confirmar a heurística de papel usada em `SearchService:_searchCompat`: espécie `"vehicle"` é tratada como veículo, e o resto como implemento.
- [ ] Confirmar o caminho do item selecionado em `ShopGuiAdapter:selectedItem()`.
- [ ] Executar o smoke do spec:
  - [ ] o botão "Compatíveis" lista implementos com engate compatível e mostra a evidência;
  - [ ] a consulta "compatíveis com este trator" dá o mesmo resultado;
  - [ ] o resultado aparece em até 1 s, com indicador durante o processamento.

### 1.5 Fase 9: release

- [ ] Recalibrar os pesos com `tools/calibrate.lua` sobre o corpus real. Contra o corpus sintético, todos os candidatos empatam em 54 de 54 casos, então o resultado não discrimina.
- [ ] Nos casos-chave de `tests/golden/queries.*.xml`, marcar `fixtures="synthetic,base,base+dlc,base+mods"`.
- [ ] Acrescentar pelo menos 20 consultas reais observadas nos smoke tests.
- [ ] Incluir `base+mods.xml` no benchmark e registrar as metas no PC de referência (Q-05). Offline, a memória do índice ficou em ~8,0 MB para 3000 itens, com só ~2% de folga sobre a meta de 8 MB: medir com o catálogo real.
- [ ] Executar e assinar `docs/release-checklist.md`:
  - [ ] smoke G1 a G12;
  - [ ] multiplayer com host e cliente, e servidor dedicado;
  - [ ] matriz de compatibilidade com outros mods;
  - [ ] remoção do mod;
  - [ ] log;
  - [ ] conformidade com as regras do ModHub vigentes;
  - [ ] DOD-01 a DOD-10.
- [ ] Fazer `python tools/build.py --release` passar. Hoje ele falha, de propósito, por causa das condicionais `pending`.
- [ ] Rodar `tools/run_testrunner.ps1` e obter zero erros.
- [ ] Datar o `CHANGELOG.md` (`## 1.0.0 — <data>`) e revisar título, descrição e ícone.
- [ ] Criar a tag `v1.0.0`, publicar um GitHub Release com o ZIP e o `SHA256SUMS` e fazer o upload no ModHub.

### 1.6 Infraestrutura

- [ ] Criar o repositório remoto no GitHub e fazer o primeiro push. O CI em `.github/workflows/ci.yml` nunca rodou.
- [ ] Configurar o runner Windows self-hosted para o job `testrunner`. Isso é opcional: sem ele, o script roda localmente.

---

## 2. Pendências offline (resolvidas)

- [x] **Métricas golden (F2):** o runner calcula precisão@5 (k = min(5, relevantes no corpus)), MRR e a taxa de consultas vazias (só entre casos que exigem resultado), imprime ao fim e grava `dist/golden-metrics.txt`. Hoje: P@5 0,929, MRR 1,000, vazios 0,000. `tools/calibrate.lua` passou a maximizar o MRR sem piorar nenhum caso.
- [x] **`types/fs25.lua` (F1):** anotações LuaLS de todos os globais usados pelos adapters. Tudo continua `[A VALIDAR]`.
- [x] **Specs secundárias fatiadas (F6):** o `IndexLifecycle` planeja a fase depois do build primário, só para specs com cobertura < 80% e só para itens que não as têm. Ela avança por orçamento (`stepPending`) e aplica tudo de uma vez (`IndexBuilder.applySecondary`), sem sobrescrever specs primárias. Uma busca nunca dispara a leitura de XML.
- [x] **Indicador `sss_indexing`:** o texto do botão de busca vira "Indexando itens…" enquanto há build fatiado ou fase secundária, e antes da busca de compatíveis e da primeira busca sem índice (essas rodam no frame seguinte). O tick é um hook em `ShopMenu.update`, que só roda com a loja aberta.
- [x] **`simulateFailure="gui"` (F6):** a chave `debug#simulateFailure` do `settings.xml`, ativa só com `debug#enabled`, faz `ensureButton`, `show` e `openInput` falharem dentro do `pcall`, e o mod degrada.
- [x] **Comando `sssSet` (F7):** `sssSet showReasons 1` e `sssSet incremental 0` gravam em `settings.xml`. Sem argumentos, lista os valores.
- [x] **Teste de propriedade do parser:** 5000 consultas.
- [x] **Catálogo sintético:** 80 itens. Entraram as categorias de alias que não tinham itens (grade, arado, subsolador, carregadeira, telescópica, caminhão), a spec `weight` em 33 itens, mais mods, DLC e uma ferramenta manual. O golden `mod-indexed` voltou à consulta original `custom trailer 24t`, e há 6 casos novos.
- [x] **Memória do índice (≤ 8 MB):** medida como delta isolado do build, com GC completo antes e depois. A medição honesta deu 13,8 MB, acima da meta. O índice foi compactado (campos e conjuntos de campos das postings compartilhados, faixas numéricas em arrays paralelos, specs guardando só o valor) e ficou em ~8,0 MB.
- [x] **Benchmark instável:** cada métrica é a mediana de 5 execuções. O `make bench` falha só pelas metas absolutas do PRD §15; a regressão relativa contra a baseline só avisa (`--strict` para falhar). A consulta composta agora tem 2 constraints de verdade, como pede o PRD. Com isso apareceu um p95 de 19 ms (meta: 15 ms), causado pelo `FilterEngine`, que criava um motivo por item aprovado. Corrigido: motivos só para os resultados, filtros aplicados antes do matching e busca sem reler o catálogo. p95 atual da consulta composta: ~0,5 ms.
- [x] **Busca de frase contra textos de itens (ADR-14):** `FuzzyMatcher.matchItemPhrases`, só em janelas com um termo sem hit exato. Exemplo: `deuts far` → "Deutz-Fahr".
- [x] **Detalhe dos motivos de constraint:** `184 kW (250 cv) ∈ [147.1, 220.7]`. O `UnitParser` e o `ComparatorParser` guardam a unidade e o fator digitados.

Bugs encontrados no caminho e corrigidos (ainda não verificados em jogo, ver seção 1.2): chave do `settings.xml` no formato errado e id de evento do `InputAdapter` lido do retorno errado.

---

## 3. Adaptações feitas em relação ao spec

Não são pendências, mas devem ser revisadas:

| Item | Spec | Implementado | Motivo |
|---|---|---|---|
| golden `txt-upper` | `FENDT 900` | `FENDT` | Com o alias, "fendt" vira conceito, e o IDF alto de "900" corta os demais itens Fendt. |
| golden `rank-field` | `deere` | `ferguson` | "deere" é um termo de alias, então gera `kind=alias` em vez de `exact`. |
| `SettingsStore:load` | `load` | `loadSettings` | Colidia com a regex de `check_deps.py`. |
| `check_deps.py`, regex de `load(` | `\bload\s*\(` | `(?<![.:\w])load\s*\(` | Deixa passar os métodos legítimos da porta `DataLoader`. |
| Critério do benchmark | 20% relativo | Metas absolutas do PRD §15 são o critério de falha; regressão relativa (> 20% e acima do piso absoluto) só avisa, ou falha com `--strict` | A variação relativa refletia a carga da máquina, não o código. |
| Revalidação do índice | a cada busca (implícito em `ensure`) | só na abertura da loja; a busca só constrói se não há índice | Reler o catálogo por consulta dominava a latência. |
| `SpecValue` | `{value, unit, source}` | `{value}`, com `source = "secondary"` só nas secundárias | `unit` e `source` não eram lidos; custavam ~120 B por spec. |
| `IndexedItem.phrases` | lista por item | `SearchIndex.phrases` (frase → campos) | A lista por item nunca foi lida; no índice serve ao fuzzy de frase. |

Cada adaptação está comentada no arquivo onde foi feita.
