"""
Firebase Cloud Messaging notification service.

Initialises the Firebase Admin SDK once on first use (lazy init) using the
service-account credentials stored in the FIREBASE_CREDENTIALS_JSON env var.

If the env var is empty the service silently skips all sends — this keeps
local dev and CI working without Firebase credentials.
"""

import json
import logging
from typing import Optional

logger = logging.getLogger(__name__)

_app = None          # firebase_admin.App instance
_messaging = None    # firebase_admin.messaging module reference
_init_attempted = False


def _init() -> bool:
    """Initialise Firebase Admin SDK. Returns True if ready to send."""
    global _app, _messaging, _init_attempted
    if _init_attempted:
        return _app is not None
    _init_attempted = True

    from app.core.config import settings
    raw = settings.FIREBASE_CREDENTIALS_JSON.strip()
    if not raw:
        logger.info("FIREBASE_CREDENTIALS_JSON not set — push notifications disabled.")
        return False

    try:
        import firebase_admin
        from firebase_admin import credentials, messaging as fb_messaging

        cred_dict = json.loads(raw)
        cred = credentials.Certificate(cred_dict)
        _app = firebase_admin.initialize_app(cred)
        _messaging = fb_messaging
        logger.info("Firebase Admin SDK initialised successfully.")
        return True
    except Exception as exc:
        logger.error("Failed to initialise Firebase Admin SDK: %s", exc)
        _app = None
        return False


async def send_to_token(
    token: str,
    title: str,
    body: str,
    data: Optional[dict] = None,
) -> bool:
    """
    Send a push notification to a single FCM token.
    Returns True on success, False on any failure.
    """
    if not _init():
        return False
    try:
        message = _messaging.Message(
            notification=_messaging.Notification(title=title, body=body),
            data={k: str(v) for k, v in (data or {}).items()},
            token=token,
            android=_messaging.AndroidConfig(
                notification=_messaging.AndroidNotification(
                    channel_id="mindforge_alerts",
                    priority="high",
                ),
                priority="high",
            ),
            apns=_messaging.APNSConfig(
                payload=_messaging.APNSPayload(
                    aps=_messaging.Aps(sound="default"),
                ),
            ),
        )
        _messaging.send(message)
        return True
    except Exception as exc:
        logger.warning("FCM send_to_token failed: %s", exc)
        return False


async def send_to_tokens(
    tokens: list[str],
    title: str,
    body: str,
    data: Optional[dict] = None,
) -> int:
    """
    Send a push notification to multiple FCM tokens (up to 500 per call).
    Returns the number of successful sends.
    """
    if not tokens or not _init():
        return 0

    # FCM multicast supports max 500 tokens per call — chunk if needed.
    success_count = 0
    chunk_size = 500
    for i in range(0, len(tokens), chunk_size):
        chunk = tokens[i : i + chunk_size]
        try:
            message = _messaging.MulticastMessage(
                notification=_messaging.Notification(title=title, body=body),
                data={k: str(v) for k, v in (data or {}).items()},
                tokens=chunk,
                android=_messaging.AndroidConfig(
                    notification=_messaging.AndroidNotification(
                        channel_id="mindforge_alerts",
                        priority="high",
                    ),
                    priority="high",
                ),
                apns=_messaging.APNSConfig(
                    payload=_messaging.APNSPayload(
                        aps=_messaging.Aps(sound="default"),
                    ),
                ),
            )
            response = _messaging.send_each_for_multicast(message)
            success_count += response.success_count
            if response.failure_count:
                logger.warning(
                    "FCM multicast: %d succeeded, %d failed",
                    response.success_count,
                    response.failure_count,
                )
        except Exception as exc:
            logger.warning("FCM send_to_tokens chunk failed: %s", exc)

    return success_count
