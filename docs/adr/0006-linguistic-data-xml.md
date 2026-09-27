# ADR-0006: Dados linguísticos em XML por idioma

## Status
Aceito

## Contexto
Aliases, sinônimos, unidades, comparadores e números por extenso variam por
idioma e crescem com o tempo (RF-023, RF-025, RF-058/059). Hardcodar em
tabelas Lua acopla vocabulário a código e dificulta contribuições.

## Decisão
Dados linguísticos vivem em `src/data/<lang>/*.xml`, lidos com a API
`XMLFile` do jogo em produção (`adapters/XmlDataLoader.lua`) e com um leitor
mínimo (`tests/support/xml.lua`) nos testes. O idioma do jogo é sempre
carregado junto com `en` (fallback).

## Consequências
- Ampliar o vocabulário é uma mudança só de dados, sem tocar em código
  (RNF-006).
- Um novo idioma precisa apenas de um novo diretório `data/<lang>/`.
- `check_deps.py` proíbe `XMLFile` em `core/`: o parsing vive em
  `app/LinguisticData.lua` e `adapters/XmlDataLoader.lua`.
