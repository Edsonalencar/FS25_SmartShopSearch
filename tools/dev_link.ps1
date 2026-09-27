<#
.SYNOPSIS
  Cria uma junction de src/ para a pasta de mods do FS25 no Windows.
#>
$root = Split-Path -Parent $PSScriptRoot
$modsDir = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "My Games\FarmingSimulator2025\mods"
$target = Join-Path $modsDir "FS25_SmartShopSearch"

if (-not (Test-Path $modsDir)) {
    New-Item -ItemType Directory -Force -Path $modsDir | Out-Null
}
if (Test-Path $target) {
    Remove-Item $target -Force
}

New-Item -ItemType Junction -Path $target -Target (Join-Path $root "src") | Out-Null
Write-Host "Link criado: $target -> $root\src"
