# FS25 \<versão\> — achados de API (\<data\>)

> Copie este arquivo para `docs/api-findings/fs25-<versão>.md` ao rodar a
> Fase 5 (spike em jogo, `spike/FS25_SSS_Spike/`). Cada seção deve ser
> preenchida com evidência real (trecho do LUADOC, saída de
> `sssSpikeProbe`/`sssSpikeDump`/`sssSpikeBench`, ou captura de tela),
> nunca deixada como suposição.

## 0. Ambiente

- Versão do jogo (build):
- `descVersion` aceito pelo jogo:
- Sistema operacional / método (Windows nativo, Proton):
- PC de referência (Q-05) — CPU, RAM, armazenamento:

## 1. Tabela [A VALIDAR]

| Id | Item | Resultado (`type()`/comportamento) | Evidência |
|---|---|---|---|
| A1 | `ShopMenu.onOpen` existe como método próprio? | | |
| A2 | `ShopMenu.onClose` | | |
| A3 | `ShopMenu.updateButtonsPanel` | | |
| A4 | `g_shopMenu.pageShopItemDetails.setDisplayItems` | | |
| A5 | `g_shopMenu.pageShopItemDetails.setCategory` | | |
| A6 | `g_shopMenu.pageShopItemDetails.resetListSelection` | | |
| A7 | `pushDetail` / `popDetail` | | |
| A8 | `g_shopController.makeDisplayItem` | | |
| A9 | `TextInputDialog.createFromExistingGui` (assinatura exata) | | |
| A10 | `TextInputDialog.INSTANCE.textElement.applyProfanityFilter` | | |
| A11 | `g_brandManager.getBrandByIndex` | | |
| A12 | `g_storeManager.getCategoryByName` | | |
| A13 | `g_storeManager.getSpecTypes` | | |
| A14 | `storeItem.specs` (estrutura) | | |
| A15 | `XMLFile.load` / `XMLFile.loadIfExists` (assinatura) | | |
| A16 | `xmlFile:iterate` (assinatura exata — usada por XmlDataLoader) | | |
| A17 | `Logging.info/warning/error` | | |
| A18 | `g_modSettingsDirectory` | | |
| A19 | `g_languageShort` | | |
| A20 | `StoreSpecies.PLACEABLE` | | |
| A21 | `addConsoleCommand` (assinatura exata) | | |
| A22 | Ícone: tamanho/formato aceito | | |

(Preencher/estender conforme necessário — ver `CANDIDATES` em `spike.lua`.)

## 2. Questões dos requisitos §24

| Id | Questão | Resposta |
|---|---|---|
| QM-01 | Ponto de extensão mais seguro da GUI | |
| QM-02 | Campos confiáveis do StoreItem | |
| QM-03 | Specs indexáveis genericamente | |
| QM-04 | Extração de atributos sem acoplamento | |
| QM-13 | Hooks que minimizam conflito | |
| QM-14 | Tela do ModHub acessível | |
| QM-15 | Funcionalidades permitidas pelo ModHub | |
| QM-18 | Pontos da referência ainda adequados | |
| QM-19 | O que reaproveitar conceitualmente | |
| QM-20 | Licença vigente da referência | |

## 3. Análise da referência (requisitos §2.3)

- Bootstrap:
- Shop GUI:
- Hooks:
- Busca:
- StoreItem:
- Campos:
- Atualização visual:
- Teclado/input:
- Conflitos com outros mods:
- Limitações a não reproduzir:

## 4. Códigos de idioma (Q-03) e tecla padrão (Q-06/S-05)

- Código real de pt-BR:
- Código real de pt-PT:
- `KEY_lctrl KEY_f` conflita com algum binding padrão? Se sim, usar `KEY_lalt KEY_f`.

## 5. ModHub: tela/catálogo acessível por script? (RF-053/Q-08)

- Decisão: `implement` | `unavailable`
- Evidência:

## 6. Placeables (S-03)

- Decisão: `implement` | `unavailable`
- Evidência (ex.: `makeDisplayItem`/`pageShopItemDetails` exibem placeables sem erro?):

## 7. Busca incremental embutida (G7)

- Viável sem hacks? Decisão:

## 8. Specs disponíveis

| Spec | Origem (specs/XML) | % de itens com valor — base | base+dlc | base+mods |
|---|---|---|---|---|
| power | | | | |
| neededPower | | | | |
| maxSpeed | | | | |
| capacity | | | | |
| workingWidth | | | | |
| weight | | | | |

## 9. Compatibilidade

- Estrutura de combinações declaradas:
- Estrutura de `attacherJoints` / `inputAttacherJoints`:

## 10. TestRunner

- Linha de comando exata:
- Relatório do esqueleto da F1 (anexar ou linkar):

## 11. Ícone

- Tamanho/formato aceito pelo ModHub:
