#!/usr/bin/env bash
# Gera src/icon_SmartShopSearch.dds a partir de art/icon.png (fora do pacote).
# O tamanho final e o formato de compressão aceitos pelo ModHub são validados
# na Fase 5; até lá isto produz um ícone de placeholder válido.
set -euo pipefail
SRC_PNG="art/icon.png"
OUT_DDS="src/icon_SmartShopSearch.dds"

if command -v convert >/dev/null 2>&1; then
    convert "$SRC_PNG" -resize 512x512 -define dds:compression=dxt5 "$OUT_DDS"
else
    echo "ImageMagick 'convert' não encontrado; usando Pillow (DXT não aplicado, ver F5)." >&2
    python3 - "$SRC_PNG" "$OUT_DDS" <<'PY'
import sys
from PIL import Image
src, out = sys.argv[1], sys.argv[2]
img = Image.open(src).convert("RGBA").resize((512, 512))
img.save(out)
PY
fi
echo "Gerado: $OUT_DDS"
