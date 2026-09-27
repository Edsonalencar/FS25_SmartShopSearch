LUA      ?= .lua/bin/lua
BUSTED   ?= .lua/bin/busted
LUACHECK ?= .lua/bin/luacheck
PY       ?= python3

.PHONY: setup fmt fmt-check lint deps trace test unit golden prop bench build verify ci
setup:     ; ./tools/setup_dev.sh
fmt:       ; stylua src tests tools
fmt-check: ; stylua --check src tests
lint:      ; $(LUACHECK) src tests
deps:      ; $(PY) tools/check_deps.py
trace:     ; $(PY) tools/check_trace.py
unit:      ; $(BUSTED) --lua=$(LUA) tests/unit
prop:      ; $(BUSTED) --lua=$(LUA) tests/prop
golden:    ; $(BUSTED) --lua=$(LUA) tests/golden
test: unit prop golden
bench:     ; $(LUA) tests/bench/run.lua --compare tests/bench/baseline.lua
build:     ; $(PY) tools/build.py
verify:    ; $(PY) tools/build.py --verify
ci: fmt-check lint deps trace test bench verify
