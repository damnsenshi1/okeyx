"""Küfür/spam filtresi (Türkçe + İngilizce). Sunucuda çalışır; istemciye güvenilmez.

- Karakter bazlı 1:1 normalleştirme (ı→i, 0→o, 1→i, @→a, $→s ...): maskeleme orijinal metinde yapılır.
- Kısa kökler yalnız TAM kelime olarak eşleşir ("sıkıntı" asla işaretlenmez).
- Uzun kökler kelime başı eşleşir (ek alırlar: "orospuluk").
- "s.i.k.t.i.r" gibi ayraçlı kaçamaklar için uzun köklerde ayraçsız tarama da yapılır.
"""
from __future__ import annotations

import re

_MAP = {
    'ı': 'i', 'İ': 'i', 'ş': 's', 'Ş': 's', 'ğ': 'g', 'Ğ': 'g', 'ü': 'u', 'Ü': 'u', 'ö': 'o', 'Ö': 'o', 'ç': 'c', 'Ç': 'c',
    '0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '7': 't', '@': 'a', '$': 's', '!': 'i',
}

EXACT = {'amk', 'aq', 'amq', 'sik', 'sikik', 'pic', 'got', 'gotun', 'amina', 'aminakoyim', 'mk', 'oc', 'yarak', 'yarrak', 'amcik', 'bok'}
PREFIX = (
    'orospu', 'oruspu', 'siktir', 'sikeyim', 'sikerim', 'sikim', 'yarrak', 'gotveren', 'ibne', 'pezevenk', 'kahpe',
    'ananisikeyim', 'aminakoy', 'amcik', 'puşt', 'pust', 'serefsiz', 'gerizekali', 'fuck', 'shit', 'bitch', 'asshol',
    'cunt', 'nigg', 'faggot', 'whore',
)
_SQUASH_MIN = 6
_TOKEN = re.compile(r'[a-z0-9@$!]+', re.I)


def _norm(text: str) -> str:
    out = []
    for ch in text:
        out.append(_MAP.get(ch, ch.lower() if len(ch.lower()) == 1 else ch))
    return ''.join(out)


def _collapse(token: str) -> str:
    return re.sub(r'(.)\1{2,}', r'\1\1', token)


def _is_bad_token(tok: str) -> bool:
    tok = _collapse(tok)
    if tok in EXACT:
        return True
    return any(tok.startswith(p) for p in PREFIX)


def find_profanity_spans(text: str) -> list[tuple[int, int]]:
    norm = _norm(text)
    spans = [m.span() for m in _TOKEN.finditer(norm) if _is_bad_token(m.group())]
    if not spans:
        # Ayraçlı kaçamaklar: yalnız uzun köklerde, harfler arasında 1-2 ayraç.
        letters = [(i, c) for i, c in enumerate(norm) if c.isalpha()]
        squashed = ''.join(c for _, c in letters)
        for root in PREFIX:
            if len(root) >= _SQUASH_MIN:
                at = squashed.find(root)
                if at >= 0 and re.search(r'[^a-z\s]', text) is not None:
                    spans.append((letters[at][0], letters[at + len(root) - 1][0] + 1))
                    break
    return spans


def mask(text: str) -> tuple[str, bool]:
    spans = find_profanity_spans(text)
    if not spans:
        return text, False
    chars = list(text)
    for a, b in spans:
        for i in range(a, b):
            chars[i] = '*'
    return ''.join(chars), True


def is_spam(text: str) -> bool:
    if re.search(r'(.)\1{8,}', text, re.I):
        return True
    if re.search(r'https?://|www\.|\b[a-z0-9-]+\.(?:com|net|org|xyz|ru|tk|me|gg)\b', text, re.I):
        return True
    letters = [c for c in text if c.isalpha()]
    if len(letters) >= 12 and sum(c.isupper() for c in letters) / len(letters) > .85:
        return True
    return False
