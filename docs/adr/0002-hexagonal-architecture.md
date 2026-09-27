# ADR-0002: Arquitetura hexagonal (core / app / adapters)

## Status
Aceito

## Contexto
A referência é um monólito de ~220 linhas que mistura extração de dados,
matching e GUI. Isso torna o motor de busca impossível de testar fora do jogo
e frágil a mudanças de patch da GUI (D12).

## Decisão
`src/core/` é Lua 5.1 puro, determinístico e sem nenhum global do jogo.
`src/adapters/` é a única camada que toca APIs do FS25. `src/app/` orquestra
`core/` via portas injetadas, sem conhecer o jogo diretamente. Regra de
dependência verificada por `tools/check_deps.py`.

## Consequências
- O motor de busca (texto, fuzzy, parser, ranking) é testável 100% em CI
  Linux, sem o jogo.
- Mudanças de patch do FS25 (GUI) afetam só `adapters/`.
- Exige disciplina de não vazar globais do jogo para `core/`/`app/`, imposta
  por lint automatizado.
