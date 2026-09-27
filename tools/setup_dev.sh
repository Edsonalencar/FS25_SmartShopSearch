#!/usr/bin/env bash
set -euo pipefail
python3 -m pip install --user hererocks
hererocks .lua -l5.1 -rlatest
.lua/bin/luarocks install busted
.lua/bin/luarocks install luacheck
command -v stylua >/dev/null || echo "Instale StyLua: cargo install stylua  (ou release binária)"
