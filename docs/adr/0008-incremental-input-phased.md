# ADR-0008: Entrada de texto em duas fases (diálogo → campo embutido)

## Status
Aceito

## Contexto
Busca incremental sem diálogo (RF-003, G7) depende de um campo de texto
embutido na página da loja, o que exige GUI XML própria e é
`[A VALIDAR]` na Fase 5. O `TextInputDialog` é comprovadamente funcional na
referência.

## Decisão
Fase 1 (F6): `TextInputDialog.createFromExistingGui` como modo suportado e
sempre disponível. Fase 2 (F7): se a Fase 5 confirmar viabilidade, adicionar
um campo de texto embutido (`TextInput` em `gui/SmartShopSearchFrame.xml`)
com *debounce*, sem substituir o diálogo.

## Consequências
- RF-003 é atendido mesmo se a busca incremental for inviável (a lista
  atualiza a cada confirmação do diálogo).
- Se G7 for `unavailable`, isso fica registrado em `docs/api-limitations.md`
  com evidência, sem bloquear a 1.0.
