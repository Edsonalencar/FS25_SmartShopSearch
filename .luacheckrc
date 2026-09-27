std = "lua51"
allow_defined_top = false
max_line_length = 120
globals = { "SmartShopSearch" }
files["src/adapters"] = { read_globals = dofile("tools/fs25_globals.lua") }
files["src/main.lua"] = { read_globals = dofile("tools/fs25_globals.lua") }
files["tests"] = { std = "+busted", globals = { "SmartShopSearch" } }
