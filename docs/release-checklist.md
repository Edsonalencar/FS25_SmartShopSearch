# Checklist de release — FS25 Smart Shop Search

> Preenchido e assinado (com data) na Fase 9, após a Fase 5 (spike em jogo)
> responder os itens `[A VALIDAR]`. Requer Windows/FS25 instalado —
> não executável neste ambiente de desenvolvimento (núcleo Linux).

## Smoke G1–G12 (PRD §8.1)

- [ ] G1 — abertura/fechamento da loja detectada
- [ ] G2 — botão "Pesquisar" aparece no painel
- [ ] G3 — botão só nas páginas elegíveis
- [ ] G4 — hotkey configurável (rebind em Controles)
- [ ] G5 — diálogo de texto recebe entrada
- [ ] G6 — resultados exibidos ordenados por score
- [ ] G7 — busca incremental (ou limitação registrada)
- [ ] G8 — painel de filtros (categoria, marca, preço, specs, origem)
- [ ] G9 — explicações de match (opcional, com `showReasons`)
- [ ] G10 — "compatíveis com este veículo"
- [ ] G11 — estado vazio sem erro
- [ ] G12 — "limpar" volta à listagem anterior
- [ ] Degradação: com `<debug enabled="true" simulateFailure="gui"/>` em
  `modSettings/FS25_SmartShopSearch/settings.xml`, abrir a loja degrada o mod
  (uma linha de erro no log) e a loja original continua funcionando
- [ ] Indicador "Indexando itens…" aparece no botão de busca durante o
  build fatiado e a busca de compatíveis, e some ao terminar
- [ ] `sssSet showReasons 1` / `sssSet incremental 0` gravam em `settings.xml`

## Multiplayer / dedicado

- [ ] SP: todos os fluxos acima
- [ ] MP host + cliente: todos os fluxos acima
- [ ] Servidor dedicado: `disabled-dedicated`, nenhum erro, nenhuma GUI registrada

## Matriz de compatibilidade (PRD §16.2)

| Mod / cenário | Resultado |
|---|---|
| `FS25_ShopSearch` ativo simultaneamente | |
| Enhanced Shop Sorting | |
| Garage Menu | |
| Vehicle Years | |
| Mods com `storeItem` incompletos | |
| Pacote com 100+ mods de veículos | |

## Remoção do mod

- [ ] Savegame usado com o mod carrega sem erros após remover o mod
- [ ] Loja volta ao comportamento nativo (RNF-010, AC-RES-04)

## Log

- [ ] Zero erros/avisos do mod nos fluxos acima
- [ ] ≤ 3 linhas `info` do mod por sessão (RNF-009)

## Conformidade ModHub (PRD §17)

- [ ] Nome do mod/ZIP `FS25_SmartShopSearch`, apenas `[A-Za-z0-9_]`
- [ ] `modDesc.xml` válido (`descVersion` vigente, título/descrição, sem URLs)
- [ ] Ícone `.dds` no tamanho/formato exigido, sem marca d'água
- [ ] Sem código ofuscado, sem `loadstring` externo, sem acesso a rede
- [ ] Sem dependências obrigatórias
- [ ] Sem arquivos de desenvolvimento no ZIP
- [ ] Revisão das regras do ModHub vigentes na data da submissão (RMH-011)
  - Data da revisão: \_\_\_\_-\_\_-\_\_

## TestRunner

- [ ] `tools/run_testrunner.ps1` executado sobre o ZIP de release
- [ ] Zero erros; avisos justificados abaixo:
  - \_\_\_

## Definição de Pronto (requisitos §25)

- [ ] DOD-01 — requisitos aplicáveis implementados
- [ ] DOD-02 — critérios de aceitação satisfeitos (Apêndice A.4)
- [ ] DOD-03 — condicionais implementadas ou `unavailable` com evidência
- [ ] DOD-04 — testes funcionais executados
- [ ] DOD-05 — regressão de busca aprovada (`make golden`)
- [ ] DOD-06 — desempenho dentro das metas (`make bench`, `sssBench`)
- [ ] DOD-07 — sem erros do mod
- [ ] DOD-08 — pacote preparado (`build.py --release`)
- [ ] DOD-09 — TestRunner aprovado
- [ ] DOD-10 — requisitos vigentes do ModHub revisados

---

Assinado por: **\ـ**\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_ Data: \_\_\_\_-\_\_-\_\_
