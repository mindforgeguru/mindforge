"""Regression for J-03 / K-21: usernames differing only by case or a cross-script
look-alike must collide for the uniqueness check, so an impersonating handle
can't be registered. Pure-logic tests on app.core.username_identity.
"""

from app.core.username_identity import confusable_skeleton as sk


# ── collisions that must be caught (same skeleton) ───────────────────────────

def test_case_variants_collide():
    assert sk("IYER_MATHS") == sk("iyer_maths")
    assert sk("AARAV8") == sk("aarav8")
    assert sk("Aarav8") == sk("aarav8")


def test_cyrillic_homoglyph_collides():
    # Leading char is Cyrillic а (U+0430), rest ASCII.
    assert sk("аarav8") == sk("aarav8")
    # Cyrillic е inside an otherwise-ASCII handle.
    assert sk("tеacher_das") == sk("teacher_das")


def test_greek_homoglyph_collides():
    # Greek omicron ο (U+03BF) imitating ASCII o.
    assert sk("dοn") == sk("don")


def test_fullwidth_and_whitespace_normalised():
    assert sk("ａａｒａｖ8") == sk("aarav8")   # full-width Latin → ASCII via NFKC
    assert sk("  Aarav8  ") == sk("aarav8")   # surrounding whitespace stripped


# ── distinct handles must NOT collide (no over-folding) ──────────────────────

def test_genuinely_different_handles_stay_distinct():
    assert sk("aarav8") != sk("aarav9")
    assert sk("meera8") != sk("aarav8")


def test_non_latin_scripts_do_not_collide_with_latin():
    # A Devanagari / Gujarati handle keeps its own letters — a legitimate
    # non-Latin username must still be registerable, not folded onto a Latin one.
    assert sk("आरव") != sk("aarav")
    assert sk("આરવ") != sk("aarav")
    assert sk("आरव") == sk("आरव")
