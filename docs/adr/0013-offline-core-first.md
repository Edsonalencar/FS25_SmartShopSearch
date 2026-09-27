# ADR-0013: Núcleo offline primeiro, spike em jogo paralelizável

## Status
Aceito

## Contexto
O motor de busca (texto, fuzzy, vocabulário, linguagem estruturada, filtros)
é testável 100% fora do jogo (ADR-0002). O spike em jogo (validação de APIs
`[A VALIDAR]`, dumps reais) depende de execução humana em Windows/FS25 e não
bloqueia o desenvolvimento do núcleo.

## Decisão (S-01)
Ordem de construção: Fases 1–4 (infraestrutura + motor completo) sobre um
catálogo sintético versionado, antes do spike. A Fase 5 (spike) pode rodar em
paralelo a partir do fim da Fase 1 e produz os dumps reais. As Fases 6–8
(ligação ao jogo) só começam após a Fase 5 responder as APIs `[A VALIDAR]`.

## Consequências
- Reduz o risco de retrabalho: o motor é validado por golden tests antes de
  qualquer dependência do jogo real.
- Os ids de categoria/marca do catálogo sintético são plausíveis, não reais;
  a correção após a Fase 5 é só de dados (`data/<lang>/aliases.xml`), sem
  mudança de código.
