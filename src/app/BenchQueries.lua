-- Consultas embutidas usadas pelo comando de console `sssBench <n>` (PRD
-- §13.2): roda as mesmas N consultas repetidas vezes e imprime p50/p95,
-- sem depender de arquivos externos no pacote publicado.
local NS = SmartShopSearch
local BenchQueries = {
    "trator",
    "trtor",
    "john deere",
    "jon dere",
    "fendt",
    "pulverizador",
    "pulverizdor",
    "carreta",
    "acima de 200 cv",
    "menos de 150 mil",
    "entre 200 e 300 cv",
    "trtor jon dere entre 200 e 300 cv por menos de 150 mil",
    "trator 200cv",
    "reboque acima de 40.000 litros",
    "dlc pulverizador",
}

NS.app.BenchQueries = BenchQueries
