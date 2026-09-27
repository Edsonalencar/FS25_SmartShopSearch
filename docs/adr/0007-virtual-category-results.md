# ADR-0007: Resultados como categoria virtual na página de detalhes

## Status
Aceito

## Contexto
Construir uma tela/diálogo próprio de resultados duplicaria a lógica nativa
de exibição, compra e detalhes de itens da loja, e aumentaria a superfície de
conflito com outros mods de loja.

## Decisão
Resultados são exibidos como uma "categoria virtual" na página de detalhes
existente (técnica observada na referência), encapsulada em
`ShopGuiAdapter`, com a ordem de exibição igual à ordem do `Ranker` (por
score).

## Consequências
- Reaproveita compra, detalhes e navegação nativos da loja sem reimplementar
  nada.
- A ordem exibida é sempre a ordem calculada pelo motor de busca — nunca
  reordenada pela GUI nativa.
- Acoplado à API `pageShopItemDetails`/`pushDetail`/`popDetail`, isolada em
  `adapters/`.
