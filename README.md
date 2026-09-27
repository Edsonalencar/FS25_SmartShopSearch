# FS25 Smart Shop Search

Busca inteligente para a loja do Farming Simulator 25: tolerância a erros de
digitação, marcas, categorias, especificações, preços, faixas e compatibilidade
entre equipamentos — sem sair da loja nativa do jogo.

## Arquitetura

O mod segue uma arquitetura hexagonal (ver `docs/PRD-base-tecnica.md` e
`docs/adr/`):

- `src/core/` — motor de busca em Lua 5.1 puro, testável fora do jogo (texto,
  índice, fuzzy, linguagem estruturada, ranking, compatibilidade).
- `src/app/` — orquestração (ciclo de vida, serviço de busca, diagnósticos)
  injetada por portas.
- `src/adapters/` — única camada que toca APIs do FS25 (GUI, catálogo,
  configurações, idioma, logging).

## Build e desenvolvimento

Pré-requisitos: Lua 5.1, LuaRocks, busted, luacheck, StyLua, Python 3.11+.

```bash
make setup        # instala toolchain Lua local (hererocks) e busted/luacheck
make ci           # fmt-check + lint + deps + trace + test + bench + verify
make build        # gera dist/FS25_SmartShopSearch-<versão>.zip
```

Ver `tools/dev_link.sh` / `tools/dev_link.ps1` para linkar `src/` na pasta de
mods do jogo durante o desenvolvimento.

## Testes

```bash
make unit         # tests/unit (busted)
make prop         # tests/prop (propriedades)
make golden       # tests/golden (regressão de busca sobre catálogo sintético/real)
make bench        # tests/bench (performance)
```

## Rastreabilidade

`docs/traceability.md` mapeia cada requisito de `requisitos.md` a um
componente e a uma verificação concreta. `docs/api-limitations.md` registra
funcionalidades condicionais à API do jogo (`implemented`/`unavailable`).

## Agradecimentos

O mod `w33zl/FS25_ShopSearch` foi usado como referência técnica para
identificar quais APIs do jogo existem e como se comportam (nenhum código foi
copiado — ver `docs/THIRD_PARTY.md` e `docs/adr/0001-clean-room.md`).

## Licença

Código sob MIT (`LICENSE`). Ícone e arte com todos os direitos reservados
(`LICENSE-ART.md`).
