# Changelog

Todas as mudanças notáveis deste projeto são documentadas neste arquivo.
Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/);
versionamento [SemVer](https://semver.org/lang/pt-BR/).

## 1.0.0 — não lançado

Núcleo de busca (Fases 1-4) completo e testado (fuzzy, vocabulário
multi-idioma, linguagem estruturada, filtros). Adapters de jogo e GUI
básica, avançada e compatibilidade (Fases 6-8) implementados seguindo as
suposições `[A VALIDAR]` do PRD, mas **não verificados contra o FS25
real** — a Fase 5 (spike em jogo) não pôde ser executada neste ambiente de
desenvolvimento (sem Windows/FS25 instalado). `docs/api-limitations.md`
mantém as condicionais em `pending`; `tools/build.py --release` bloqueia
corretamente o release enquanto isso não for resolvido em jogo.

### Adicionado
- Infraestrutura do repositório, toolchain e CI (Fase 1).
- Núcleo textual, índice invertido e ranking (Fase 2).
- Fuzzy matching (OSA + trigramas) e vocabulário multi-idioma via alias (Fase 3).
- Linguagem estruturada: números, unidades, comparadores, contexto, filtros (Fase 4).
- Scaffold do spike de investigação em jogo, não executado (Fase 5).
- Adapters de catálogo, specs e GUI básica da loja (Fase 6).
- `ReasonFormatter` e `FilterPresets`, reutilizáveis para a GUI avançada (Fase 7).
- Resolução de compatibilidade entre equipamentos por evidência de dados (Fase 8).
- `tools/calibrate.lua` (Fase 9); pesos de ranking mantidos nos valores iniciais do PRD.
- Métricas golden (precisão@5, MRR, taxa de consultas vazias) em
  `dist/golden-metrics.txt`; `tools/calibrate.lua` passa a maximizar o MRR.
- Specs secundárias lidas do XML, fatiadas, só para specs com cobertura < 80%.
- Indicador "Indexando itens…" durante o build fatiado e a busca de compatíveis.
- `debug#simulateFailure="gui"` para testar a degradação em jogo.
- Comando `sssSet` (`showReasons`, `incremental`).
- Fuzzy de frase contra títulos de itens (marca/categoria/mod multi-palavra).
- Motivo de constraint na unidade da consulta ("184 kW (250 cv)").
- `types/fs25.lua` com anotações LuaLS dos globais do jogo.
- Catálogo sintético com 80 itens, incluindo specs de massa.

### Alterado
- Índice ~42% menor (13,8 → 8,0 MB para 3000 itens), build ~2x mais rápido.
- Consultas com constraints ~4x mais rápidas; a busca não relê mais o
  catálogo a cada consulta.
- Benchmark: mediana de 5 execuções, memória do índice isolada, falha só
  pelas metas absolutas do PRD §15 (regressão relativa só avisa, `--strict`
  para falhar).
- Teste de propriedade do parser com 5000 consultas.

### Corrigido
- `SettingsStore` gravava as chaves como `settings.debug.#enabled`; o
  formato do XMLFile é `settings.debug#enabled`.
- `InputAdapter` guardava o primeiro retorno de `registerActionEvent`
  (`success`) como id do evento.

### Pendente (bloqueado por falta de ambiente FS25/Windows)
- Validação em jogo de todos os itens `[A VALIDAR]` do PRD (Fase 5).
- GUI de busca incremental e painel de filtros (G7/G8, Fase 7).
- Verificação de `attacherJoints`/combinações reais (Fase 8).
- TestRunner, checklist de release assinado, submissão ao ModHub (Fase 9).
