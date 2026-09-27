#!/usr/bin/env bash
# Cria um link simbólico de src/ para a pasta de mods do FS25 (Linux/Proton).
# Ajuste MODS_DIR se o Steam/Proton usar outro caminho de perfil.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODS_DIR="${FS25_MODS_DIR:-$HOME/.steam/steam/steamapps/compatdata/*/pfx/drive_c/users/steamuser/Documents/My Games/FarmingSimulator2025/mods}"
TARGET="FS25_SmartShopSearch"

resolved_mods_dir=$(compgen -G "$MODS_DIR" | head -n1 || true)
if [ -z "$resolved_mods_dir" ]; then
    echo "Pasta de mods não encontrada. Defina FS25_MODS_DIR manualmente." >&2
    exit 1
fi

ln -sfn "$ROOT/src" "$resolved_mods_dir/$TARGET"
echo "Link criado: $resolved_mods_dir/$TARGET -> $ROOT/src"
