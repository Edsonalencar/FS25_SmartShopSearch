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

### Pendente (bloqueado por falta de ambiente FS25/Windows)
- Validação em jogo de todos os itens `[A VALIDAR]` do PRD (Fase 5).
- GUI de busca incremental e painel de filtros (G7/G8, Fase 7).
- Verificação de `attacherJoints`/combinações reais (Fase 8).
- TestRunner, checklist de release assinado, submissão ao ModHub (Fase 9).
