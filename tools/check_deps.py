import re, sys, pathlib

SRC = pathlib.Path(__file__).resolve().parents[1] / "src"
CORE_FORBIDDEN = [
    r"\bg_[A-Za-z]",
    r"\bShopMenu\b",
    r"\bUtils\.",
    r"\bXMLFile\b",
    r"\bgetXML",
    r"\bsource\s*\(",
    r"\bprint\s*\(",
    r"adapters[/.]",
    r"\bos\.",
    r"\bio\.",
]
APP_FORBIDDEN = [r"\bg_[A-Za-z]", r"\bShopMenu\b", r"\bXMLFile\b", r"adapters[/.]", r"\bio\."]
ALL_FORBIDDEN = [
    r"\bloadstring\s*\(",
    r"\bload\s*\(",
    r"\bdofile\s*\(",
    r"\brequire\s*\(",
    r"\bos\.execute",
    r"\bio\.",
    r"https?://",
    r"\bsocket\b",
    r"\bHTTP",
    r"\bgoto\b",
    r"//",
    r"\butf8\.",
]


def scan(glob, patterns, label, errors):
    for f in SRC.glob(glob):
        for n, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
            code = line.split("--", 1)[0]
            for p in patterns:
                if re.search(p, code):
                    errors.append(f"{f.relative_to(SRC)}:{n}: [{label}] {p}")


errors = []
scan("core/**/*.lua", CORE_FORBIDDEN, "core-purity", errors)
scan("app/**/*.lua", APP_FORBIDDEN, "app-purity", errors)
scan("**/*.lua", ALL_FORBIDDEN, "offline/lua51", errors)
print("\n".join(errors) or "deps OK")
sys.exit(1 if errors else 0)
