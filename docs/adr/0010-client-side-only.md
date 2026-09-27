# ADR-0010: Mod exclusivamente client-side

## Status
Aceito

## Contexto
Em multiplayer, todos os jogadores baixam os mods do servidor; a loja é UI
local por jogador (P5). Sincronizar buscas por rede não tem valor e
aumentaria a superfície de bugs e de conflito com o RNF-004 (offline-first).

## Decisão
Nenhum evento de rede, nenhuma sincronização multiplayer. `modDesc.xml`
declara `multiplayer supported="true"` porque o mod não altera regras de
jogo nem estado compartilhado — cada cliente busca localmente.

## Consequências
- Servidor dedicado (sem GUI) não precisa registrar nada de GUI
  (`g_dedicatedServer ~= nil` → estado `disabled-dedicated`).
- Nenhum risco de dessincronização entre clientes.
