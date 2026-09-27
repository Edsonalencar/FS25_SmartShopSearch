# ADR-0003: HookRegistry central para todos os hooks no jogo

## Status
Aceito

## Contexto
A referência sobrescreve funções diretamente, com defeitos: retorno original
descartado (D1), hook em classe base afetando outros menus (D6), registro de
eventos sem remoção (D7). Isso quebra compatibilidade com outros mods
(RNF-007).

## Decisão
Todo hook passa por `HookRegistry`: usa `Utils.appendedFunction` /
`prependedFunction` preferencialmente; `overwrittenFunction` só quando for
necessário alterar o retorno; envolve o corpo em `pcall`; é idempotente;
desativa o hook após N falhas consecutivas.

## Consequências
- Um hook instalado duas vezes não duplica comportamento.
- Uma falha num hook não propaga para o jogo nem para outros mods.
- `sssStatus` expõe o estado de cada hook (ativo/falhas) para diagnóstico.
