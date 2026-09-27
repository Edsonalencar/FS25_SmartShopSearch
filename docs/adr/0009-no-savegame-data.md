# ADR-0009: Nenhum dado em savegame

## Status
Aceito

## Contexto
RNF-010 exige que remover o mod não deixe rastro no savegame. Salvar
preferências (explicações, idioma extra) no savegame acoplaria o save ao
mod.

## Decisão
Nenhum dado é gravado no savegame. Preferências do usuário (mostrar
explicações, busca incremental, nível de log) vivem em
`modSettings/FS25_SmartShopSearch/settings.xml`, gerido por
`adapters/SettingsStore.lua`.

## Consequências
- Remover o mod não deixa rastro no savegame (AC-RES-04).
- Preferências persistem entre savegames (por instalação do jogo), não por
  savegame — comportamento aceitável para preferências de UI.
