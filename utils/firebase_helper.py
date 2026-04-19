import os
import logging
from typing import Optional, List

from dotenv import load_dotenv

load_dotenv()
logger = logging.getLogger(__name__)

_firebase_app = None


def _get_firebase():
    global _firebase_app
    if _firebase_app is None:
        import firebase_admin
        from firebase_admin import credentials
        service_account_path = os.getenv("FIREBASE_SERVICE_ACCOUNT", "serviceAccount.json")
        if os.path.exists(service_account_path):
            cred = credentials.Certificate(service_account_path)
            _firebase_app = firebase_admin.initialize_app(cred)
        else:
            logger.warning("[Firebase] serviceAccount.json not found — notifications disabled")
    return _firebase_app


def send_notification(
    token: str,
    title: str,
    body: str,
    data: Optional[dict] = None,
) -> bool:
    """Send a push notification to a single device FCM token."""
    try:
        from firebase_admin import messaging
        _get_firebase()
        message = messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            data=data or {},
            token=token,
        )
        messaging.send(message)
        return True
    except Exception as exc:
        logger.error(f"[Firebase] Send failed: {exc}")
        return False


def send_multicast(
    tokens: List[str],
    title: str,
    body: str,
    data: Optional[dict] = None,
) -> int:
    """Send to multiple tokens. Returns success count."""
    try:
        from firebase_admin import messaging
        _get_firebase()
        message = messaging.MulticastMessage(
            notification=messaging.Notification(title=title, body=body),
            data=data or {},
            tokens=tokens,
        )
        response = messaging.send_each_for_multicast(message)
        return response.success_count
    except Exception as exc:
        logger.error(f"[Firebase] Multicast failed: {exc}")
        return 0
