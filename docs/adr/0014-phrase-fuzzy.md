# ADR-0014: Fuzzy de frase para marcas/categorias multi-palavra

## Status
Aceito

## Contexto
O limiar "≤3 chars: só exato" (RF-022) impede que `jon dere` combine com
"John Deere", porque `jon` isolado tem 3 caracteres e cairia no limiar mais
restrito (lacuna L6 do spec). Marcas e categorias multi-palavra precisam de
tolerância a erro considerando a frase inteira, não cada token isolado.

## Decisão
`FuzzyMatcher.matchPhrase` compara janelas de 2–3 tokens consecutivos da
consulta contra frases do vocabulário (marcas/categorias/aliases
multi-palavra), com limiar de distância calculado pelo comprimento da frase
sem espaços (não pelo comprimento do token isolado). A janela vencedora
consome os tokens, evitando dupla contagem no score.

## Consequências
- `jon dere` (7 caracteres sem espaço) usa o limiar de frase, não o de token
  curto, e casa com "john deere" a distância 2.
- Exige um `TrigramIndex` também sobre as frases do vocabulário
  (`IndexedItem.fields.phrases`) e sobre os termos de alias multi-palavra.
- A ordem de matching por token passa a ser: exato → prefixo → alias →
  fuzzy de frase → fuzzy de token.
