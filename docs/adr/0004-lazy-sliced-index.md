# ADR-0004: Índice invertido construído sob demanda e fatiado

## Status
Aceito

## Contexto
A referência varre o catálogo inteiro a cada busca (D5): O(n·m) por consulta,
inviável para fuzzy. Construir o índice no `loadMap` atrasaria o carregamento
do savegame; itens de mods podem ser registrados tarde.

## Decisão
Índice invertido em memória, construído sob demanda na primeira abertura da
loja após `loadMapFinished`, com possibilidade de construção fatiada entre
frames (orçamento por frame). Invalidado por assinatura do catálogo
(contagem + hash de `xmlFilename`) a cada abertura da loja.

## Consequências
- Não atrasa o carregamento do jogo.
- Consultas passam a ser O(1)/O(log n) por token via postings/prefixos/faixas
  numéricas, em vez de O(n) por busca.
- Exige `IndexLifecycle` para gerenciar o ciclo construção/invalidação e
  `sssReindex` para reconstrução manual.

## Revisão (pendências offline, 2026-09-27)
- **Revalidação só na abertura da loja.** A busca só constrói o índice se
  ele ainda não existe; ela não recalcula mais a assinatura. Recalcular
  relia o catálogo inteiro (`StoreCatalogSource:items()` + hash de 3000
  `xmlFilename`) a cada consulta, e isso respondia pela maior parte da
  latência medida no bench.
- **Tick por frame só com a loja aberta.** O trabalho fatiado avança num
  hook em `ShopMenu.update` (`ShopGuiAdapter.onFrame`, 4 ms por frame) via
  `IndexLifecycle.stepPending`, que continua o trabalho em andamento sem
  reler o catálogo. Com a loja fechada, nada roda (PRD §15: FPS).
  `[A VALIDAR na F5]`: existência de `ShopMenu.update`. Sem ele, o build
  termina na primeira busca, como antes.
- **Fase secundária de specs (PRD §9.2).** Depois do build primário, as specs
  com cobertura abaixo de 80% são lidas do XML dos itens que não as têm,
  fatiadas e aplicadas de uma vez só no fim (`IndexBuilder.applySecondary`).
  Uma busca (`ensure(nil)`) nunca dispara essa leitura.
- **Índice compacto.** O índice passou a compartilhar os `IndexedField`
  repetidos (marca, categoria, mod…) e os conjuntos de campos das postings.
  As faixas numéricas viraram arrays paralelos. Resultado: 13,8 MB → 8,0 MB
  para 3000 itens (delta isolado, após GC completo).
