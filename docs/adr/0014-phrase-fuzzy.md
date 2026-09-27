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
- Exige um `TrigramIndex` também sobre as frases dos itens
  (`SearchIndex.phrases`/`phraseTrigram`, de brand/category/mod) e sobre os
  termos de alias multi-palavra.
- A ordem de matching por token passa a ser: exato → prefixo → alias →
  fuzzy de frase → fuzzy de token.

## Revisão (pendências offline, 2026-09-27)
O fuzzy de frase passou a valer também contra os textos dos itens, e não só
contra os aliases (`FuzzyMatcher.matchItemPhrases`). Ele só é tentado em
janelas que contêm um termo sem hit exato. Assim, consultas que já casam
termo a termo mantêm o ranking. Exemplo: em `deuts far`, "far" só casava
por prefixo com um autor ("farmerbr"); agora a janela casa a marca
"Deutz-Fahr" a distância 2 e cobre os dois termos. O hit vale para cada termo
da janela, no campo de origem da frase, e o motivo aparece uma vez só.
