"""
face_service.py
─────────────────────────────────────────────────────────────
ArcFace via InsightFace + ONNX Runtime (no TensorFlow).
Replaces DeepFace/TF which OOM-killed Railway free tier (512MB limit).
InsightFace buffalo_sc: ~170MB on disk, ~250MB RAM — fits comfortably.
"""
import base64
import logging
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Optional, Tuple, List

import numpy as np
import cv2

logger = logging.getLogger(__name__)

# ── Thread-safe InsightFace singleton ─────────────────────────
_insight_app = None
_insight_lock = threading.Lock()

def _get_insight():
    global _insight_app
    if _insight_app is None:
        with _insight_lock:
            if _insight_app is None:  # double-checked locking
                from insightface.app import FaceAnalysis
                _insight_app = FaceAnalysis(
                    name="buffalo_sc",
                    providers=["CPUExecutionProvider"],
                )
                _insight_app.prepare(ctx_id=0, det_size=(320, 320))
                logger.info("[InsightFace] Model loaded OK")
    return _insight_app


# ── Thread-safe OpenCV Haar cascade ──────────────────────────
_face_cascade = None
_cascade_lock = threading.Lock()

def _get_cascade():
    global _face_cascade
    if _face_cascade is None:
        with _cascade_lock:
            if _face_cascade is None:
                _face_cascade = cv2.CascadeClassifier(
                    cv2.data.haarcascades + "haarcascade_frontalface_default.xml"
                )
    return _face_cascade


# ── Startup warmup ────────────────────────────────────────────
def warmup_models() -> bool:
    """Pre-load all models into memory. Call at app startup."""
    try:
        logger.info("[Warmup] Loading InsightFace ArcFace model…")
        _get_insight()
        logger.info("[Warmup] Loading Haar cascade…")
        _get_cascade()
        logger.info("[Warmup] All models ready ✅")
        return True
    except Exception as exc:
        logger.warning(f"[Warmup] Failed: {exc}")
        return False


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


# ── Liveness: OpenCV Haar cascade ────────────────────────────
def check_liveness(b64_image: str) -> Tuple[bool, str]:
    """
    Lightweight face-presence check — no GPU, no protobuf.
    Falls back to True on any error so face matching still runs.
    """
    try:
        img = decode_base64_image(b64_image)
        if img is None:
            return False, "image_decode_failed"

        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        faces = _get_cascade().detectMultiScale(
            gray, scaleFactor=1.1, minNeighbors=4, minSize=(60, 60)
        )
        if len(faces) == 0:
            return False, "no_face_detected"
        return True, "live"

    except Exception as exc:
        logger.warning(f"[Liveness] Error (skipping): {exc}")
        return True, "liveness_skipped"


# ── ArcFace embedding via InsightFace ────────────────────────
def extract_embedding(img: np.ndarray) -> Optional[List[float]]:
    """Run InsightFace ArcFace on BGR uint8 ndarray. Returns 512-dim list or None."""
    try:
        if img is None or not isinstance(img, np.ndarray):
            logger.warning("Invalid image — not a numpy array")
            return None
        if img.dtype != np.uint8:
            img = img.astype(np.uint8)
        if len(img.shape) != 3 or img.shape[2] != 3:
            logger.warning(f"Bad image shape: {img.shape}")
            return None
        if img.shape[0] < 20 or img.shape[1] < 20:
            logger.warning("Image too small")
            return None

        app = _get_insight()
        faces = app.get(img)

        if not faces:
            logger.warning("InsightFace found no face")
            return None

        # Pick the largest face (most prominent subject)
        face = max(faces, key=lambda f: (f.bbox[2] - f.bbox[0]) * (f.bbox[3] - f.bbox[1]))

        # Always use L2-normalised embedding for consistent cosine distance
        embedding = face.normed_embedding if hasattr(face, "normed_embedding") else face.embedding
        if embedding is None or len(embedding) != 512:
            logger.warning(f"Unexpected embedding size: {len(embedding) if embedding is not None else 'None'}")
            return None

        # Ensure L2 norm = 1 (safety net)
        emb = np.asarray(embedding, dtype=np.float32)
        norm = np.linalg.norm(emb)
        if norm > 0:
            emb = emb / norm

        return [float(x) for x in emb]

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
def _process_angle(angle_and_photos: tuple) -> tuple:
    """Worker: compute averaged embedding for one angle group."""
    angle, group_photos = angle_and_photos
    embeddings = [e for e in (get_embedding(p) for p in group_photos) if e is not None]
    if len(embeddings) < 1:
        raise ValueError(
            f"Not enough valid face photos for angle '{angle}' "
            f"(got {len(embeddings)}/min 1)"
        )
    return angle, average_embeddings(embeddings)


def process_registration_photos(photos: List[str]) -> dict:
    """
    Accept 25 base64 photos (front:0-8, left:9-16, right:17-24).
    Processes all 3 angle groups in parallel with ThreadPoolExecutor.
    Returns averaged ArcFace embeddings per angle + profile_b64.
    """
    groups = [
        ("front", photos[0:9]),
        ("left",  photos[9:17]),
        ("right", photos[17:25]),
    ]
    result = {}
    with ThreadPoolExecutor(max_workers=4) as executor:
        futures = {executor.submit(_process_angle, item): item[0] for item in groups}
        for future in as_completed(futures):
            angle, embedding = future.result()  # raises ValueError on failure
            result[angle] = embedding

    result["profile_b64"] = photos[0]
    return result
