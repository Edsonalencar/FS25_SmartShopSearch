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
