"""Confusable-aware username identity for the uniqueness check.

Usernames were compared by exact code points, so ``IYER_MATHS`` could register
next to ``iyer_maths`` (case) and ``аarav8`` with a Cyrillic ``а`` next to
``aarav8`` (homoglyph) — two accounts with a human-identical handle, i.e.
impersonation (findings J-03 / K-21). ``confusable_skeleton`` reduces a username
to a canonical form so those collide and the second registration is refused.

Scope: this folds the *common* Latin-look-alike letters from Cyrillic and Greek
plus case and Unicode compatibility (NFKC) — enough to stop the realistic
impersonation vectors. It deliberately does NOT romanise whole scripts: a
Devanagari or Gujarati username keeps its own letters and does not collide with
a Latin one, so legitimate non-Latin handles still register. It is used only to
compare usernames for uniqueness, never to change what is stored or how login
looks a user up, so existing accounts are unaffected.
"""

import unicodedata

# Lower-case Latin look-alikes from other scripts. Keyed by the confusable
# code point, valued by the ASCII letter it imitates. Curated for low
# false-collision risk — only well-known, unambiguous look-alikes are mapped.
_CONFUSABLES = {
    # ── Cyrillic → Latin ──
    "а": "a",  # а
    "в": "b",  # в
    "е": "e",  # е
    "ё": "e",  # ё
    "к": "k",  # к
    "м": "m",  # м
    "н": "h",  # н
    "о": "o",  # о
    "р": "p",  # р
    "с": "c",  # с
    "у": "y",  # у
    "х": "x",  # х
    "і": "i",  # і
    "ј": "j",  # ј
    "ѕ": "s",  # ѕ
    "ԁ": "d",  # ԁ
    "һ": "h",  # һ
    "ӏ": "l",  # ӏ
    # ── Greek → Latin ──
    "α": "a",  # α
    "ε": "e",  # ε
    "ι": "i",  # ι
    "κ": "k",  # κ
    "ν": "v",  # ν
    "ο": "o",  # ο
    "ρ": "p",  # ρ
    "τ": "t",  # τ
    "χ": "x",  # χ
    "υ": "u",  # υ
    # ── other common look-alikes ──
    "ı": "i",  # ı dotless i
    "−": "-",  # − minus sign vs hyphen
}


def confusable_skeleton(username: str) -> str:
    """Canonical form of a username for uniqueness comparison.

    NFKC (folds full-width, compatibility and composed forms) → case-fold →
    map the common cross-script Latin look-alikes to ASCII → strip surrounding
    whitespace. Two usernames with the same skeleton are treated as the same
    handle for registration.
    """
    s = unicodedata.normalize("NFKC", username).strip().casefold()
    # Case-fold again after NFKC in case normalisation introduced upper-case.
    s = unicodedata.normalize("NFKC", s).casefold()
    return "".join(_CONFUSABLES.get(ch, ch) for ch in s)
