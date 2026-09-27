"""Gera a tabela Utf8.FOLD (sequência de bytes UTF-8 -> ASCII) usada por
src/core/text/Utf8.lua, para Latin-1 Suplementar (U+00C0-U+00FF) e Latin
Extended-A (U+0100-U+017F). Usa unicodedata.normalize("NFKD") e descarta
marcas combinantes, mais os casos especiais que a decomposição não resolve
(ss, ae, o, d, l, oe, th).

Uso: python tools/gen_fold_table.py > /tmp/fold_table.lua
     (o literal gerado é colado manualmente em Utf8.lua; o arquivo final não
     depende de nada em tempo de execução — nenhum import de unicodedata no jogo)
"""
import unicodedata

SPECIAL = {
    "ß": "ss",
    "æ": "ae",
    "Æ": "AE",
    "ø": "o",
    "Ø": "O",
    "đ": "d",
    "Đ": "D",
    "ł": "l",
    "Ł": "L",
    "œ": "oe",
    "Œ": "OE",
    "þ": "th",
    "Þ": "Th",
    "ð": "d",
    "Ð": "D",
}


def fold_char(ch):
    if ch in SPECIAL:
        return SPECIAL[ch]
    decomposed = unicodedata.normalize("NFKD", ch)
    ascii_only = "".join(c for c in decomposed if not unicodedata.combining(c))
    if ascii_only and all(ord(c) < 128 for c in ascii_only):
        return ascii_only
    return None


def main():
    entries = []
    ranges = [(0xC0, 0xFF), (0x100, 0x17F)]
    for start, end in ranges:
        for cp in range(start, end + 1):
            ch = chr(cp)
            folded = fold_char(ch)
            if folded is None:
                continue
            utf8_bytes = ch.encode("utf-8")
            key = "".join("\\%d" % b for b in utf8_bytes)
            entries.append((key, folded))

    print('local NS = SmartShopSearch\nlocal Utf8 = {}\n\nUtf8.FOLD = {')
    for key, value in entries:
        escaped_value = value.replace("\\", "\\\\").replace('"', '\\"')
        print('    ["%s"] = "%s",' % (key, escaped_value))
    print("}")


if __name__ == "__main__":
    main()
