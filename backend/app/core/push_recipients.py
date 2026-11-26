"""
Who may receive a push notification.

Recipient lists are built from active students and then widened with each
student's linked parent, but the parent was never checked. A parent an admin
had deactivated (a custody change, say) kept getting "Your child was marked
absent", new-test and broadcast pushes on their phone. Every token lookup goes
through this condition, so a deactivated or deleted account gets nothing no
matter how it ended up in the id set.
"""

from sqlalchemy import and_

from app.models.user import User


def can_receive_push():
    """SQL condition: the user has a device token and an active account."""
    return and_(
        User.fcm_token.isnot(None),
        User.is_active == True,  # noqa: E712
        User.deleted_at.is_(None),
    )
