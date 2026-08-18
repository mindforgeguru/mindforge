"""
Where the MFA fields live.

Added after getting this wrong. The fields were patched in against the anchor
`school_id: Optional[int] = None`, which is not unique in schemas/user.py, so
they landed on `UserRegisterRequest` instead of `UserLoginRequest`. Two
consequences, and the second is the reason this file exists:

  * login blew up with AttributeError — a 500 on the auth endpoint, caught
    immediately by an end-to-end probe;
  * `mfa_code` and `recovery_code` became accepted input on **registration**,
    which is public and unauthenticated. Harmless as written, since nothing
    reads them there, but a second-factor field on a self-service signup route
    is the kind of thing that later grows a meaning.

Nothing in the unit suite would have noticed either. These assertions are cheap
and pin both directions.
"""

from app.schemas.user import (
    MfaCodeRequest,
    MfaDisableRequest,
    UserLoginRequest,
    UserRegisterRequest,
)


class TestLoginCarriesTheMfaFields:
    def test_login_accepts_a_totp_code(self):
        assert "mfa_code" in UserLoginRequest.model_fields

    def test_login_accepts_a_recovery_code(self):
        assert "recovery_code" in UserLoginRequest.model_fields

    def test_both_are_optional(self):
        # The first call is made without them — the server replies mfa_required
        # so the client knows to prompt. Making either required would break
        # every non-enrolled account.
        for f in ("mfa_code", "recovery_code"):
            assert UserLoginRequest.model_fields[f].default is None


class TestRegistrationDoesNot:
    def test_registration_has_no_mfa_fields(self):
        leaked = {"mfa_code", "recovery_code"} & set(UserRegisterRequest.model_fields)
        assert not leaked, (
            f"{leaked} are accepted on the public registration endpoint; MFA "
            "belongs on login and the authenticated enrolment routes only"
        )


class TestEnrolmentSchemas:
    def test_confirm_takes_only_a_code(self):
        assert set(MfaCodeRequest.model_fields) == {"code"}

    def test_disable_requires_the_mpin_and_one_factor(self):
        fields = MfaDisableRequest.model_fields
        assert set(fields) == {"mpin", "code", "recovery_code"}
        # Re-authenticating is the point: without the MPIN, anyone at an
        # unlocked signed-in session could strip the second factor off.
        assert fields["mpin"].is_required()
        assert fields["code"].default is None
        assert fields["recovery_code"].default is None
