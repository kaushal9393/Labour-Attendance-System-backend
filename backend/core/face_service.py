"""
face_service.py
─────────────────────────────────────────────────────────────
ArcFace embedding (DeepFace) + lightweight OpenCV liveness check.
MediaPipe removed: it caused protobuf conflicts and OOM kills on Railway.
"""
import os
os.environ.setdefault("TF_USE_LEGACY_KERAS", "1")
os.environ.setdefault("TF_ENABLE_ONEDNN_OPTS", "0")
os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")

import base64
import logging
from typing import Optional, Tuple, List

import numpy as np
import cv2

logger = logging.getLogger(__name__)

# ── Lazy DeepFace import so startup stays fast ────────────────
_deepface = None

def _get_deepface():
    global _deepface
    if _deepface is None:
        from deepface import DeepFace
        _deepface = DeepFace
    return _deepface


# ── OpenCV Haar cascade (loaded once, reused) ─────────────────
_face_cascade = None

def _get_cascade():
    global _face_cascade
    if _face_cascade is None:
        _face_cascade = cv2.CascadeClassifier(
            cv2.data.haarcascades + "haarcascade_frontalface_default.xml"
        )
    return _face_cascade


# ── Image helpers ─────────────────────────────────────────────
def decode_base64_image(base64_string: str) -> Optional[np.ndarray]:
    """Decode base64 (with or without data: prefix) → BGR uint8 ndarray."""
    try:
        if "," in base64_string:
            base64_string = base64_string.split(",", 1)[1]
        img_bytes = base64.b64decode(base64_string)
        np_arr = np.frombuffer(img_bytes, dtype=np.uint8)
        img = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)
        if img is None:
            logger.warning("cv2.imdecode returned None")
            return None
        return img
    except Exception as e:
        logger.warning(f"Image decode failed: {e}")
        return None


# ── Liveness: OpenCV Haar face detection ──────────────────────
def check_liveness(b64_image: str) -> Tuple[bool, str]:
    """
    Lightweight face-presence check using OpenCV Haar cascade.
    No GPU, no protobuf, no mediapipe — runs anywhere.
    Returns (is_live, reason).
    """
    try:
        img = decode_base64_image(b64_image)
        if img is None:
            return False, "image_decode_failed"

        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        cascade = _get_cascade()
        faces = cascade.detectMultiScale(
            gray, scaleFactor=1.1, minNeighbors=4, minSize=(60, 60)
        )
        if len(faces) == 0:
            return False, "no_face_detected"
        return True, "live"

    except Exception as exc:
        logger.warning(f"[Liveness] Error (skipping): {exc}")
        return True, "liveness_skipped"


# ── ArcFace embedding ─────────────────────────────────────────
def extract_embedding(img: np.ndarray) -> Optional[List[float]]:
    """Run DeepFace ArcFace on a BGR uint8 ndarray. Returns 512-dim list or None."""
    try:
        if img is None or not isinstance(img, np.ndarray):
            logger.warning("Invalid image — not a numpy array")
            return None
        if img.dtype != np.uint8:
            img = img.astype(np.uint8)
        if len(img.shape) != 3 or img.shape[2] != 3:
            logger.warning(f"Bad image shape: {img.shape}")
            return None
        if img.shape[0] < 10 or img.shape[1] < 10:
            logger.warning("Image too small")
            return None

        DeepFace = _get_deepface()
        result = DeepFace.represent(
            img_path=img,
            model_name="ArcFace",
            detector_backend="opencv",
            enforce_detection=False,
            align=True,
        )

        if not result:
            logger.warning("DeepFace returned empty result")
            return None

        embedding = result[0]["embedding"]
        if len(embedding) != 512:
            logger.warning(f"Unexpected embedding size: {len(embedding)}")
            return None

        return [float(x) for x in embedding]

    except Exception as e:
        logger.warning(f"Embedding failed: {e}")
        return None


def get_embedding(b64_image: str) -> Optional[List[float]]:
    """Base64 wrapper around extract_embedding."""
    img = decode_base64_image(b64_image)
    if img is None:
        return None
    return extract_embedding(img)


def average_embeddings(embeddings: List[List[float]]) -> List[float]:
    """Average a list of 512-dim embeddings into one L2-normalised vector."""
    arr = np.array([e for e in embeddings if e is not None])
    if len(arr) == 0:
        raise ValueError("No valid embeddings to average")
    avg = np.mean(arr, axis=0)
    norm = np.linalg.norm(avg)
    if norm > 0:
        avg = avg / norm
    return avg.tolist()


# ── Registration helper ───────────────────────────────────────
def process_registration_photos(photos: List[str]) -> dict:
    """
    Accept 25 base64 photos split by angle:
      front: indices  0-8   (9 photos)
      left:  indices  9-16  (8 photos)
      right: indices 17-24  (8 photos)
    Returns averaged embeddings per angle + profile_b64.
    """
    groups = {
        "front": photos[0:9],
        "left":  photos[9:17],
        "right": photos[17:25],
    }
    result = {}
    for angle, group_photos in groups.items():
        embeddings = [e for e in (get_embedding(p) for p in group_photos) if e is not None]
        if len(embeddings) < 1:
            raise ValueError(
                f"Not enough valid face photos for angle '{angle}' "
                f"(got {len(embeddings)}/min 1)"
            )
        result[angle] = average_embeddings(embeddings)

    result["profile_b64"] = photos[0]
    return result
