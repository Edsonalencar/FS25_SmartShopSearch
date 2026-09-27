# ADR-0012: Integração com o ModHub atrás de porta `CatalogSource`, condicional

## Status
Aceito

## Contexto
RF-053..056 pedem busca por itens do ModHub (não instalados), mas RF-056
proíbe scraping/hacks e o mod deve ser offline-first (RNF-004). Não há, a
priori, garantia de que existe uma API suportada para o catálogo do ModHub
acessível por script.

## Decisão
Uma eventual integração com o ModHub vive atrás da mesma porta
`CatalogSource` usada por `StoreCatalogSource`. `ModHubCatalogSource` só é
criado se a Fase 5 (spike) comprovar um ponto de extensão documentado e
estável. Caso contrário, RF-053/054 ficam registrados como `unavailable` em
`docs/api-limitations.md`, com evidência.

## Consequências
- Nenhum código de scraping ou acesso a rede é escrito preventivamente.
- A decisão de implementar ou não é tomada com evidência, na Fase 5, e
  documentada — nunca assumida.
