# ADR-0001: Implementação clean-room, sem Weezls Mod Lib

## Status
Aceito

## Contexto
`w33zl/FS25_ShopSearch` (@ `d4166f7`) não tem arquivo de licença no código
principal (todos os direitos reservados). As bibliotecas auxiliares
(`scripts/modLib/*`, "Weezls Mod Lib") são licenciadas sob CC BY-NC-SA 4.0,
que exige atribuição, é não comercial e *share-alike* — incompatível com os
objetivos do projeto (PRD §2.5). A referência também tem defeitos conhecidos
(PRD §2.4) que não devem ser reproduzidos.

## Decisão
Nenhum trecho de código da referência é copiado. A referência é usada
exclusivamente para identificar quais APIs do jogo existem e como se
comportam. Nomes de APIs do jogo (`g_storeManager`, `ShopMenu`, etc.)
pertencem à GIANTS, não à referência.

## Consequências
- Elimina as obrigações de atribuição/share-alike do CC BY-NC-SA.
- Todo o motor de busca é escrito do zero, com arquitetura própria.
- README cita a referência como inspiração (cortesia, não obrigação legal).
- Se no futuro houver interesse em reutilizar algo, exige licença explícita
  do autor, registrada em `docs/THIRD_PARTY.md`.
