# ADR-0015: Valores finais dos pesos de ranking

## Status
Aceito (parcial — ver "Consequências")

## Contexto
RF-040 exige que os pesos de campo/tipo do modelo de score (§6.6 do PRD)
sejam calibrados contra o corpus golden. `tools/calibrate.lua` (F9) faz uma
busca em grade sobre `minScoreRel`, `coverageFloor` e as penalidades,
reaproveitando `tests/golden/runner.lua`, maximizando quantos casos golden
passam sem piorar nenhum.

## Decisão
Os pesos iniciais definidos em `src/core/rank/Weights.lua` (F2, valores do
PRD §6.6) foram mantidos sem alteração. Rodando `tools/calibrate.lua`
contra o corpus golden atual (54 casos, catálogo **sintético** — ver
lacuna abaixo), os pesos padrão já passam **54/54** casos, e nenhuma das
seis variações testadas na grade (`minScoreRel` ±0.05/+0.10,
penalidades ±0.05, `coverageFloor` ±0.10) supera esse resultado — todas
empatam em 54/54, porque o corpus atual não tem casos que discriminem
entre elas.

## Consequências
- **Calibração real fica incompleta**: um corpus de 54 casos sobre ~45
  itens sintéticos satura rápido (qualquer conjunto razoável de pesos
  passa); calibração que discrimine de verdade entre configurações de
  pesos precisa do corpus real da Fase 5 (dumps de `base`, `base+dlc`,
  `base+mods`, com ≥ 20 consultas reais observadas em smoke tests, como o
  próprio spec da F9 pede) — **bloqueado neste ambiente** por não haver
  FS25/Windows disponíveis (mesma ressalva registrada nas Fases 5-8).
- `tools/calibrate.lua` fica pronto e funcional para quando esse corpus
  real existir: basta rodar `lua tools/calibrate.lua` de novo depois de
  popular `tests/fixtures/catalog/{base,base+dlc,base+mods}.xml` e
  estender `tests/golden/queries.*.xml` com `fixtures="synthetic,base,..."`
  e as consultas reais observadas.
- Nenhum valor de peso foi alterado nesta fase; `core/rank/Weights.lua`
  permanece igual ao commit da F2.
