# Rastreabilidade — FS25 Smart Shop Search 1.0

Cópia do Apêndice A do spec `specs/plans/2026-09-27-smart-shop-search-1.0.md`.
Verificada automaticamente por `tools/check_trace.py` (`make trace`).

Formato de linha obrigatório para o parser: `| Id | Componente | Verificação | Fase |`.

## A.1 Requisitos funcionais

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
| RF-011 | SpecExtractor, SpecRegistry, IndexBuilder (specs), IndexLifecycle (fase secundária) | golden:unit-power,unit-cap,mass-gt; unit:pending_spec,adapters_spec; api-findings §8 | F4/F6 |
| RF-012 | TextNormalizer | unit:text_spec; golden:txt-upper,txt-trator-upper | F2 |
| RF-013 | Utf8.fold, TextNormalizer | unit:text_spec; golden:txt-accent | F2 |
| RF-014 | TextNormalizer (colapso/trim) | unit:text_spec; golden:txt-spaces | F2 |
| RF-015 | Tokenizer | unit:text_spec; prop:normalizer_prop | F2 |
| RF-016 | FuzzyMatcher, TrigramIndex (remoção) | unit:fuzzy_spec; golden:fuzzy-trtor | F3 |
| RF-017 | FuzzyMatcher, Osa (inserção) | golden:fuzzy-insert | F3 |
| RF-018 | FuzzyMatcher, Osa (substituição) | golden:fuzzy-subst | F3 |
| RF-019 | Osa (transposição) | unit:fuzzy_spec; golden:fuzzy-tratro | F3 |
| RF-020 | FuzzyMatcher.matchPhraseWindow/matchItemPhrases, AliasResolver | golden:fuzzy-jon-dere,fuzzy-jhon-deere,fuzzy-john-dere; unit:pending_spec | F3 |
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
| RF-052 | ReasonFormatter, ShopGuiAdapter (G9), Console.set (sssSet showReasons) | unit:reason_formatter_spec,pending_spec; smoke:G9; api-limitations | F7 |
| RF-053 | Spike F5 | api-findings §5 | F5 |
| RF-054 | ModHubCatalogSource (condicional, ADR-12) | api-limitations | F5/F9 |
| RF-055 | Porta CatalogSource (adaptador separado) | check_deps; revisão ADR-12 | F1/F5 |
| RF-056 | ADR-12; check_deps (sem rede) | deps; api-limitations (evidência) | F1/F5 |
| RF-057 | translations/translation_br.xml, data/pt | build.py (chaves br/pt) | F1/F9 |
| RF-058 | translations/*.xml, data/<lang> (fora do código) | build.py (chaves); deps | F1 |
| RF-059 | LinguisticData, data/<lang>/aliases.xml | unit:alias_spec (troca de locale) | F3 |
| RF-060 | SafeCall, StateMachine.degrade, HookRegistry, ShopGuiAdapter (debug#simulateFailure) | unit:app_spec,resilience_spec,adapters_spec; smoke simulateFailure | F1/F6 |
| RF-061 | IndexBuilder (campos opcionais) | unit:index_spec (sem marca) | F2 |
| RF-062 | IndexBuilder (pcall por item), StoreCatalogSource | unit:index_spec; golden:res-magic | F2/F6 |

## A.2 Requisitos não funcionais

| Id | Componente | Verificação | Fase |
|---|---|---|---|
| RNF-001 | IndexBuilder.step fatiado, IndexLifecycle.stepPending (só com a loja aberta), debounce, sem update permanente | bench; unit:pending_spec,adapters_spec; smoke G7 | F2/F7 |
| RNF-002 | SearchIndex, TrigramIndex | bench (p95 ≤5/15 ms) | F2–F4 |
| RNF-003 | IndexedItem.ref somente leitura, strings uma vez, campos/postings compartilhados | bench (≤8 MB, delta isolado); unit:index_spec (não mutação), pending_spec | F2 |
| RNF-004 | Núcleo local; sem rede (L1) | deps:offline/lua51 | F1 |
| RNF-005 | core/text, lang, index, match, rank, compat; adapters/GUI | deps:core-purity; revisão | F1–F8 |
| RNF-006 | SpecRegistry, units.xml, data/<lang>, Weights | unit:alias_spec (novo idioma só dados) | F3/F4 |
| RNF-007 | HookRegistry (append preferencial, específicos) | revisão; matriz compat | F1/F6/F9 |
| RNF-008 | GameLogger, Diagnostics | smoke (log) | F1/F6 |
| RNF-009 | GameLogger (rate limit, ≤3 info) | smoke (contagem de linhas) | F1/F6 |
| RNF-010 | ADR-09 (sem savegame), modSettings | smoke remoção do mod | F6/F9 |

## A.3 Requisitos de ModHub

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

## A.4 Critérios de aceitação (requisitos §21)

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
| AC-RES-03 | falha interna não inutiliza a loja | unit:resilience_spec,adapters_spec; smoke simulateFailure | F2/F6 |
| AC-RES-04 | remoção do mod restaura comportamento | smoke remoção | F9 |
| AC-PUB-01 | TestRunner aprovado | relatório TestRunner | F9 |
| AC-PUB-02 | log sem erros do mod | checklist log | F9 |
| AC-PUB-03 | estrutura do ZIP | verify | F1/F9 |
| AC-PUB-04 | metadados completos | verify; checklist | F9 |
| AC-PUB-05 | testes funcionais antes da submissão | checklist assinado | F9 |

## A.5 Questões obrigatórias (requisitos §24)

| Id | Questão | Resposta / onde | Fase |
|---|---|---|---|
| QM-01 | Ponto de extensão mais seguro da GUI | api-findings §2; ShopGuiAdapter (G1–G6) | F5 |
| QM-02 | Campos confiáveis do StoreItem | api-findings §2, §8 (cobertura por perfil) | F5 |
| QM-03 | Specs indexáveis genericamente | api-findings §8; SpecRegistry | F5 |
| QM-04 | Extração de atributos sem acoplamento | SpecExtractor em camadas (PRD §9.2) | F5/F6 |
| QM-05 | Algoritmo fuzzy | trigramas + OSA + fuzzy de frase (ADR-05, ADR-14) | F3 |
| QM-06 | Limiar por tamanho | Weights.fuzzyMaxByLen | F3 |
| QM-07 | Cálculo do score | SearchScorer (§2.4 do spec) | F2 |
| QM-08 | Quando construir o índice | IndexLifecycle na 1ª abertura (ADR-04) | F2/F6 |
| QM-09 | Invalidação/reconstrução | Signature + sssReindex | F2 |
| QM-10 | Localização de aliases | LinguisticData, data/<lang> (S-06) | F3 |
| QM-11 | Representação da consulta | Query AST (§4.2 do spec) | F4 |
| QM-12 | Compatibilidade sem inferência falsa | CompatibilityResolver (F8) | F8 |
| QM-13 | Hooks que minimizam conflito | api-findings §2; HookRegistry | F5 |
| QM-14 | Tela do ModHub acessível | api-findings §5 | F5 |
| QM-15 | Funcionalidades permitidas pelo ModHub | api-findings §2; checklist datado | F5/F9 |
| QM-16 | Regressão automatizada | golden + prop + unit (make test) | F2 |
| QM-17 | TestRunner repetível | run_testrunner.ps1 + job CI | F1/F5 |
| QM-18 | Pontos da referência ainda adequados | api-findings §3 | F5 |
| QM-19 | O que reaproveitar conceitualmente | PRD §2.3/§2.4 + api-findings §3 | F5 |
| QM-20 | Licença vigente da referência | PRD §2.5 + reconfirmação datada em api-findings §2 | F5 |

## A.6 Definição de pronto (requisitos §25)

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

## A.7 Entregáveis da Modelagem (requisitos §26)

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
| DEL-13 | estratégia de testes | Testing Strategy do spec |
| DEL-14 | pipeline de validação/TestRunner | build.py, CI, run_testrunner.ps1 |
| DEL-15 | estrutura final de arquivos | PRD §5.3/§5.4 + manifesto |
| DEL-16 | mapeamento RF/RNF/RMH → componente → teste | este Apêndice → docs/traceability.md |

## A.8 Princípios e referência (requisitos §2, §3)

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
