# ADR-0011: Um único global `SmartShopSearch`

## Status
Aceito

## Contexto
Cada mod do FS25 roda em ambiente próprio com globais do jogo acessíveis;
outros mods podem sobrescrever as mesmas funções (P3). Múltiplos globais
próprios aumentam o risco de colisão de nomes com outros mods.

## Decisão
Um único global é exportado: `SmartShopSearch`. Todos os módulos internos são
tabelas locais por arquivo, registradas em `NS.core`/`NS.app`/`NS.adapters`/
`NS.data` (namespace interno), nunca globais soltos.

## Consequências
- `luacheck` com `allow_defined_top = false` e `globals = {"SmartShopSearch"}`
  detecta qualquer vazamento de global novo.
- Reduz a zero o risco de colisão de nomes com outros mods.
