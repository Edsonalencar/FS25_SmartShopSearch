<#
.SYNOPSIS
  Executa o FS25 TestRunner sobre um ZIP do mod e arquiva o relatório.

  A linha de comando exata do TestRunner (nome do executável, flags de saída)
  é [A VALIDAR na Fase 5] e fica registrada em docs/api-findings/fs25-<ver>.md
  assim que confirmada. Este script assume uma convenção plausível de CLI
  (parâmetro de ZIP + diretório de relatório) até lá.
#>
param(
    [Parameter(Mandatory = $true)][string]$Zip,
    [string]$TestRunnerPath = $env:FS25_TESTRUNNER,
    [string]$OutDir = "dist/testrunner"
)

if (-not $TestRunnerPath) {
    Write-Error "FS25_TESTRUNNER não definido e -TestRunnerPath não informado."
    exit 1
}
if (-not (Test-Path $TestRunnerPath)) {
    Write-Error "TestRunner não encontrado em: $TestRunnerPath"
    exit 1
}
if (-not (Test-Path $Zip)) {
    Write-Error "ZIP não encontrado: $Zip"
    exit 1
}

$version = [System.IO.Path]::GetFileNameWithoutExtension($Zip) -replace '^FS25_SmartShopSearch-', ''
$reportDir = Join-Path $OutDir $version
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
$reportPath = Join-Path $reportDir "report.txt"

# [A VALIDAR na F5]: assinatura real do executável do TestRunner.
& $TestRunnerPath --zip $Zip --report $reportPath
$exitCode = $LASTEXITCODE

if (Test-Path $reportPath) {
    $report = Get-Content $reportPath -Raw
    if ($report -match '(?i)error') {
        Write-Error "TestRunner reportou erros. Ver $reportPath"
        exit 1
    }
}

exit $exitCode
