"""
Recovery codes — the path that runs when someone loses their phone.

This is where MFA usually hurts real users rather than attackers. An admin who
changes handset with no way back is locked out of a whole school's records, and
whoever fixes that will do it by disabling MFA in the database, which is worse
than never having enabled it. So the fallback has to work, and has to be
single-use.

sha256 rather than bcrypt is deliberate: these are 160-bit random values, so
there is no low-entropy guess space for a slow hash to defend, and bcrypt over
ten codes on every fallback attempt would cost real time for nothing.
"""

import pytest

from app.core.mfa import (
    RECOVERY_CODE_COUNT,
    consume_recovery_code,
    generate_recovery_codes,
    hash_recovery_code,
)


class TestGeneration:
    def test_returns_the_expected_number_of_codes(self):
        plain, hashed = generate_recovery_codes()
        assert len(plain) == RECOVERY_CODE_COUNT
        assert len(hashed) == RECOVERY_CODE_COUNT

    def test_codes_are_unique(self):
        plain, _ = generate_recovery_codes()
        assert len(set(plain)) == RECOVERY_CODE_COUNT

    def test_plaintext_is_never_what_gets_stored(self):
        # The whole point: a database leak must not hand over usable codes.
        plain, hashed = generate_recovery_codes()
        for p in plain:
            assert p not in hashed

    def test_codes_are_readable_enough_to_write_down(self):
        # People print these and type them under stress. Grouped, and without
        # characters that get confused on paper.
        plain, _ = generate_recovery_codes()
        for code in plain:
            assert "-" in code, f"{code} should be grouped for legibility"
            assert not set(code) & set("01OIl"), f"{code} contains a confusable"


class TestConsumption:
    def test_a_valid_code_is_accepted(self):
        plain, hashed = generate_recovery_codes()
        ok, remaining = consume_recovery_code(plain[0], hashed)
        assert ok is True
        assert len(remaining) == RECOVERY_CODE_COUNT - 1

    def test_a_consumed_code_cannot_be_reused(self):
        # Single use is the property. A recovery code that still works after a
        # successful login is a permanent second password.
        plain, hashed = generate_recovery_codes()
        ok, remaining = consume_recovery_code(plain[0], hashed)
        assert ok is True
        ok_again, _ = consume_recovery_code(plain[0], remaining)
        assert ok_again is False

    def test_other_codes_survive_one_being_used(self):
        plain, hashed = generate_recovery_codes()
        _, remaining = consume_recovery_code(plain[0], hashed)
        ok, _ = consume_recovery_code(plain[1], remaining)
        assert ok is True

    def test_an_unknown_code_is_rejected(self):
        _, hashed = generate_recovery_codes()
        ok, remaining = consume_recovery_code("AAAA-BBBB-CCCC", hashed)
        assert ok is False
        assert len(remaining) == RECOVERY_CODE_COUNT, "a failed attempt burned a code"

    def test_input_is_normalised(self):
        # Typed off paper, so case and stray spaces are expected.
        plain, hashed = generate_recovery_codes()
        ok, _ = consume_recovery_code(f"  {plain[0].lower()}  ", hashed)
        assert ok is True

    @pytest.mark.parametrize("junk", ["", None, 12345, "not-a-code"])
    def test_malformed_input_is_rejected_not_raised(self, junk):
        _, hashed = generate_recovery_codes()
        ok, remaining = consume_recovery_code(junk, hashed)
        assert ok is False
        assert len(remaining) == RECOVERY_CODE_COUNT

    def test_empty_store_rejects_everything(self):
        # An account that has burned all ten must not fall open.
        ok, remaining = consume_recovery_code("AAAA-BBBB-CCCC", [])
        assert ok is False
        assert remaining == []

    def test_none_store_is_treated_as_empty(self):
        # The column is nullable, so this is reachable for a row that never
        # enrolled.
        ok, remaining = consume_recovery_code("AAAA-BBBB-CCCC", None)
        assert ok is False
        assert remaining == []


class TestHashing:
    def test_hash_is_stable(self):
        assert hash_recovery_code("ABCD-EFGH-JKMN") == hash_recovery_code("ABCD-EFGH-JKMN")

    def test_hash_normalises_the_same_way_consumption_does(self):
        assert hash_recovery_code(" abcd-efgh-jkmn ") == hash_recovery_code("ABCD-EFGH-JKMN")
