"""Empacota e valida o mod FS25_SmartShopSearch (PRD §12.2 + spec F1).

Uso:
  python tools/build.py            # gera dist/FS25_SmartShopSearch-<versao>.zip
  python tools/build.py --verify   # roda as validações sem gravar em dist/, depois
                                    # constrói num diretório temporário e reabre
                                    # (contagem + SHA-256 por arquivo)
  python tools/build.py --release  # como --verify, mais check_trace.py --release
"""
import hashlib
import pathlib
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
DIST = ROOT / "dist"
MOD_NAME = "FS25_SmartShopSearch"

ALLOWED_EXT = {".lua", ".xml", ".dds", ".ogg", ".i3d", ".shapes"}
VERSION_RE = re.compile(r"^\d+\.\d+\.\d+\.\d+$")
URL_RE = re.compile(r"(https?://|www\.)")
SSS_KEY_RE = re.compile(r"\bsss_[a-z0-9_]+\b")
MANIFEST_FILE_RE = re.compile(r'"([\w/]+\.lua)"')


class BuildError(Exception):
    pass


def semver(version):
    """1.0.0.0 (modDesc) -> 1.0.0 (nome do ZIP / CHANGELOG / tag de release)."""
    return ".".join(version.split(".")[:3])


def fail(errors):
    for e in errors:
        print(f"ERRO: {e}", file=sys.stderr)
    sys.exit(1)


def validate_moddesc(errors):
    path = SRC / "modDesc.xml"
    if not path.exists():
        errors.append("src/modDesc.xml ausente")
        return None
    try:
        tree = ET.parse(path)
    except ET.ParseError as e:
        errors.append(f"modDesc.xml malformado: {e}")
        return None
    root = tree.getroot()
    if root.tag != "modDesc":
        errors.append("modDesc.xml: raiz não é <modDesc>")
    if not root.get("descVersion"):
        errors.append("modDesc.xml: falta descVersion")
    if root.find("author") is None or not (root.find("author").text or "").strip():
        errors.append("modDesc.xml: falta <author>")
    version_el = root.find("version")
    version = None
    if version_el is None or not (version_el.text or "").strip():
        errors.append("modDesc.xml: falta <version>")
    else:
        version = version_el.text.strip()
        if not VERSION_RE.match(version):
            errors.append(f"modDesc.xml: version '{version}' não bate com ^\\d+.\\d+.\\d+.\\d+$")
    title = root.find("title")
    if title is None or title.find("en") is None:
        errors.append("modDesc.xml: falta <title><en>")
    if title is not None and title.find("br") is None and title.find("pt") is None:
        errors.append("modDesc.xml: falta <title><br> ou <title><pt>")
    desc = root.find("description")
    if desc is None or desc.find("en") is None:
        errors.append("modDesc.xml: falta <description><en>")
    else:
        for lang_el in desc:
            text = "".join(lang_el.itertext())
            if URL_RE.search(text or ""):
                errors.append(f"modDesc.xml: description/{lang_el.tag} contém URL (proibido §17)")
    icon_el = root.find("iconFilename")
    if icon_el is None or not (icon_el.text or "").strip():
        errors.append("modDesc.xml: falta <iconFilename>")
    else:
        icon_path = SRC / icon_el.text.strip()
        if not icon_path.exists():
            errors.append(f"modDesc.xml: iconFilename '{icon_el.text.strip()}' não existe em src/")
    mp = root.find("multiplayer")
    if mp is None or mp.get("supported") != "true":
        errors.append("modDesc.xml: falta <multiplayer supported=\"true\"/>")
    l10n = root.find("l10n")
    if l10n is None or not l10n.get("filenamePrefix"):
        errors.append("modDesc.xml: falta <l10n filenamePrefix=.../>")
    esf = root.find("extraSourceFiles")
    main_files = [sf for sf in (esf.findall("sourceFile") if esf is not None else []) if sf.get("filename") == "main.lua"]
    if len(main_files) != 1:
        errors.append("modDesc.xml: extraSourceFiles deve ter exatamente um sourceFile filename=\"main.lua\"")
    actions = root.find("actions")
    action_names = [a.get("name") for a in (actions.findall("action") if actions is not None else [])]
    if "SMART_SHOP_SEARCH" not in action_names:
        errors.append("modDesc.xml: falta <action name=\"SMART_SHOP_SEARCH\"/>")
    ib = root.find("inputBinding")
    binding_actions = [
        ab.get("action") for ab in (ib.findall("actionBinding") if ib is not None else [])
    ]
    if "SMART_SHOP_SEARCH" not in binding_actions:
        errors.append("modDesc.xml: falta <actionBinding action=\"SMART_SHOP_SEARCH\">")
    return version


def validate_no_urls_in_lua(errors):
    for f in SRC.rglob("*.lua"):
        text = f.read_text(encoding="utf-8")
        for n, line in enumerate(text.splitlines(), 1):
            code = line.split("--", 1)[0]
            if URL_RE.search(code):
                errors.append(f"{f.relative_to(SRC)}:{n}: URL proibida em script (§17)")


def validate_manifest(errors):
    manifest_path = SRC / "manifest.lua"
    if not manifest_path.exists():
        errors.append("src/manifest.lua ausente")
        return
    text = manifest_path.read_text(encoding="utf-8")
    listed = MANIFEST_FILE_RE.findall(text)
    listed_set = set(listed)
    for rel in listed:
        if not (SRC / rel).exists():
            errors.append(f"manifest.lua lista '{rel}', mas o arquivo não existe")
    for f in SRC.rglob("*.lua"):
        rel = f.relative_to(SRC).as_posix()
        if rel in ("main.lua", "manifest.lua"):
            continue
        if rel not in listed_set:
            errors.append(f"{rel} existe em src/ mas não está em manifest.lua (código morto no pacote)")


def collect_translation_keys():
    keys = set()
    for f in SRC.rglob("*.lua"):
        keys |= set(SSS_KEY_RE.findall(f.read_text(encoding="utf-8")))
    gui_dir = SRC / "gui"
    if gui_dir.exists():
        for f in gui_dir.rglob("*.xml"):
            keys |= set(SSS_KEY_RE.findall(f.read_text(encoding="utf-8")))
    return keys


def validate_translations(errors, warnings):
    keys = collect_translation_keys()
    trans_dir = SRC / "translations"
    if not trans_dir.exists():
        errors.append("src/translations/ ausente")
        return
    en_path = trans_dir / "translation_en.xml"
    if not en_path.exists():
        errors.append("translations/translation_en.xml ausente")
        return
    en_text = en_path.read_text(encoding="utf-8")
    missing_en = sorted(k for k in keys if k not in en_text)
    if missing_en:
        errors.append(f"chaves sss_ usadas mas ausentes em translation_en.xml: {', '.join(missing_en)}")
    for lang_file in sorted(trans_dir.glob("translation_*.xml")):
        if lang_file.name == "translation_en.xml":
            continue
        text = lang_file.read_text(encoding="utf-8")
        missing = sorted(k for k in keys if k not in text)
        if missing:
            warnings.append(f"{lang_file.name}: faltam chaves {', '.join(missing)}")


def validate_changelog(errors, version):
    path = ROOT / "CHANGELOG.md"
    if not path.exists():
        errors.append("CHANGELOG.md ausente")
        return
    text = path.read_text(encoding="utf-8")
    sv = semver(version) if version else None
    if sv and not re.search(rf"^## {re.escape(sv)}", text, re.M):
        errors.append(f"CHANGELOG.md sem cabeçalho '## {sv}'")


def list_package_files():
    files = []
    for f in SRC.rglob("*"):
        if f.is_dir():
            continue
        suffix = "".join(f.suffixes)
        ext_ok = f.suffix in ALLOWED_EXT or suffix.endswith(".i3d.shapes")
        if not ext_ok:
            continue
        files.append(f)
    return files


def validate_allowlist(errors):
    for f in SRC.rglob("*"):
        if f.is_dir():
            continue
        suffix = f.suffix
        full_suffix = "".join(f.suffixes)
        if suffix in ALLOWED_EXT or full_suffix.endswith(".i3d.shapes"):
            continue
        errors.append(f"arquivo com extensão não permitida no pacote: {f.relative_to(SRC)}")
    for d in SRC.rglob("*"):
        if d.is_dir() and not any(d.iterdir()):
            errors.append(f"diretório vazio não permitido no pacote: {d.relative_to(SRC)}")


def build_zip(version, out_dir):
    out_dir.mkdir(parents=True, exist_ok=True)
    zip_path = out_dir / f"{MOD_NAME}-{semver(version)}.zip"
    files = sorted(list_package_files(), key=lambda p: p.relative_to(SRC).as_posix())
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for f in files:
            arcname = f.relative_to(SRC).as_posix()
            zf.write(f, arcname)
    sums_path = out_dir / "SHA256SUMS"
    with open(sums_path, "w", encoding="utf-8") as fh:
        for f in files:
            arcname = f.relative_to(SRC).as_posix()
            digest = hashlib.sha256(f.read_bytes()).hexdigest()
            fh.write(f"{digest}  {arcname}\n")
    return zip_path, sums_path, files


def reopen_and_verify(zip_path, expected_files):
    with zipfile.ZipFile(zip_path) as zf:
        names = zf.namelist()
        if len(names) != len(expected_files):
            return [f"ZIP tem {len(names)} arquivos, esperado {len(expected_files)}"]
        errors = []
        for f in expected_files:
            arcname = f.relative_to(SRC).as_posix()
            if arcname not in names:
                errors.append(f"{arcname} ausente no ZIP reaberto")
                continue
            data = zf.read(arcname)
            digest = hashlib.sha256(data).hexdigest()
            expected_digest = hashlib.sha256(f.read_bytes()).hexdigest()
            if digest != expected_digest:
                errors.append(f"{arcname}: SHA-256 divergente após reabrir o ZIP")
        return errors


def main():
    verify = "--verify" in sys.argv or "--release" in sys.argv
    release = "--release" in sys.argv

    errors = []
    warnings = []
    version = validate_moddesc(errors)
    validate_no_urls_in_lua(errors)
    validate_manifest(errors)
    validate_translations(errors, warnings)
    if version:
        validate_changelog(errors, version)
    validate_allowlist(errors)

    for w in warnings:
        print(f"AVISO: {w}")

    if errors:
        fail(errors)

    if release:
        result = subprocess.run([sys.executable, str(ROOT / "tools/check_trace.py"), "--release"])
        if result.returncode != 0:
            sys.exit(1)

    if verify:
        with tempfile.TemporaryDirectory() as tmp:
            zip_path, sums_path, files = build_zip(version, pathlib.Path(tmp))
            reopen_errors = reopen_and_verify(zip_path, files)
            if reopen_errors:
                fail(reopen_errors)
            print(f"verify OK: {len(files)} arquivos, {zip_path.name}")
    else:
        zip_path, sums_path, files = build_zip(version, DIST)
        print(f"build OK: {zip_path} ({len(files)} arquivos)")


if __name__ == "__main__":
    main()
