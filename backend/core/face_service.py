"""
face_service.py — ArcFace via ONNX Runtime (buffalo_sc model, no insightface).
Accepts 3-25 base64 photos for registration (3 per angle).
"""
import os
import base64
import logging
import threading
from concurrent.futures import ThreadPoolExecutor
from typing import Optional, List

import numpy as np
import cv2

logger = logging.getLogger(__name__)

_rec_session = None
_det_session = None
_model_lock  = threading.Lock()

MODEL_DIR = os.environ.get("MODEL_DIR", "/app/models/buffalo_sc")


def _get_rec_session():
    """Load ArcFace recognition ONNX session (w600k_r50.onnx or 1k3d68.onnx)."""
    global _rec_session
    if _rec_session is None:
        with _model_lock:
            if _rec_session is None:
                import onnxruntime as ort
                # buffalo_sc ships w600k_r50.onnx for recognition
                candidates = ["w600k_r50.onnx", "w600k_mbf.onnx", "glintr100.onnx"]
                loaded = False
                for name in candidates:
                    path = os.path.join(MODEL_DIR, name)
                    if os.path.exists(path):
                        logger.info(f"[ArcFace] Loading recognition model: {path}")
                        _rec_session = ort.InferenceSession(
                            path, providers=["CPUExecutionProvider"]
                        )
                        loaded = True
                        break
                if not loaded:
                    # List what's available
                    files = os.listdir(MODEL_DIR) if os.path.exists(MODEL_DIR) else []
                    raise RuntimeError(
                        f"No ArcFace recognition model found in {MODEL_DIR}. "
                        f"Files present: {files}"
                    )
    return _rec_session


def _get_det_session():
    """Load SCRFD face detection ONNX session."""
    global _det_session
    if _det_session is None:
        with _model_lock:
            if _det_session is None:
                import onnxruntime as ort
                candidates = ["det_500m.onnx", "det_2.5g.onnx", "det_10g.onnx"]
                for name in candidates:
                    path = os.path.join(MODEL_DIR, name)
                    if os.path.exists(path):
                        logger.info(f"[SCRFD] Loading detection model: {path}")
                        _det_session = ort.InferenceSession(
                            path, providers=["CPUExecutionProvider"]
                        )
                        return _det_session
    return _det_session  # may be None — we fall back to Haar


_face_cascade = None

def _get_cascade():
    global _face_cascade
    if _face_cascade is None:
        _face_cascade = cv2.CascadeClassifier(
            cv2.data.haarcascades + "haarcascade_frontalface_default.xml"
        )
    return _face_cascade


def warmup_models() -> None:
    try:
        _get_rec_session()
        dummy = np.zeros((112, 112, 3), dtype=np.uint8)
        _arcface_embed(dummy)
        _get_cascade()
        logger.info("[Warmup] All models ready ✅")
    except Exception as e:
        logger.warning(f"⚠️ Warmup failed: {e}")


def decode_base64_image(base64_string: str) -> Optional[np.ndarray]:
    try:
        if "," in base64_string:
            base64_string = base64_string.split(",", 1)[1]
        img_bytes = base64.b64decode(base64_string)
        np_arr = np.frombuffer(img_bytes, dtype=np.uint8)
        img = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)
        return img
    except Exception as e:
        logger.warning(f"Image decode failed: {e}")
        return None


def _arcface_embed(face_bgr: np.ndarray) -> Optional[List[float]]:
    """Run ArcFace on a 112×112 BGR face crop, return normed 512-d embedding."""
    try:
        session = _get_rec_session()
        face = cv2.resize(face_bgr, (112, 112))
        # Normalize to [-1, 1]
        face_norm = (face.astype(np.float32) - 127.5) / 127.5
        blob = face_norm.transpose(2, 0, 1)[np.newaxis]  # NCHW
        input_name = session.get_inputs()[0].name
        emb = session.run(None, {input_name: blob})[0][0]
        norm = np.linalg.norm(emb)
        if norm > 0:
            emb = emb / norm
        return [float(x) for x in emb]
    except Exception as e:
        logger.warning(f"ArcFace embed failed: {e}")
        return None


def _detect_and_crop_face(img: np.ndarray) -> Optional[np.ndarray]:
    """Detect largest face in image, return cropped BGR patch or None."""
    h, w = img.shape[:2]

    # Try Haar cascade (fast, no extra deps)
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    cascade = _get_cascade()
    faces = cascade.detectMultiScale(gray, 1.1, 5, minSize=(60, 60))
    if len(faces) > 0:
        # Pick largest
        x, y, fw, fh = max(faces, key=lambda r: r[2] * r[3])
        # 20% padding
        pad = int((fw + fh) / 2 * 0.20)
        x1 = max(0, x - pad)
        y1 = max(0, y - pad)
        x2 = min(w, x + fw + pad)
        y2 = min(h, y + fh + pad)
        return img[y1:y2, x1:x2]
    return None


def extract_embedding(img: np.ndarray) -> Optional[List[float]]:
    """Detect face then embed. Falls back to center crop if no face found."""
    if img is None or img.ndim != 3:
        return None
    crop = _detect_and_crop_face(img)
    if crop is None:
        # Fallback: use center square crop
        h, w = img.shape[:2]
        size = min(h, w)
        x1 = (w - size) // 2
        y1 = (h - size) // 2
        crop = img[y1:y1+size, x1:x1+size]
    return _arcface_embed(crop)


def extract_embedding_no_detect(img: np.ndarray) -> Optional[List[float]]:
    """
    For ML Kit pre-cropped images (already face-cropped on device).
    Skip detection, run ArcFace directly.
    """
    if img is None or img.ndim != 3:
        return None
    return _arcface_embed(img)


def get_embedding(b64_image: str) -> Optional[List[float]]:
    img = decode_base64_image(b64_image)
    if img is None:
        return None
    return extract_embedding(img)


def average_embeddings(embeddings: List[List[float]]) -> List[float]:
    arr = np.array([e for e in embeddings if e is not None])
    if len(arr) == 0:
        raise ValueError("No valid embeddings to average")
    avg = np.mean(arr, axis=0)
    norm = np.linalg.norm(avg)
    if norm > 0:
        avg = avg / norm
    return avg.tolist()


def _resize_for_embedding(img: np.ndarray, max_dim: int = 480) -> np.ndarray:
    h, w = img.shape[:2]
    if max(h, w) <= max_dim:
        return img
    scale = max_dim / max(h, w)
    return cv2.resize(img, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_AREA)


def process_registration_photos(photos: List[str]) -> dict:
    """
    Accept 3–25 base64 photos.
    Layout: front first third, left middle third, right last third.
    Returns averaged ArcFace embeddings per angle + profile_b64.
    """
    n = len(photos)
    if n < 3:
        raise ValueError(f"At least 3 photos required, got {n}")

    third = n // 3
    groups = {
        "front": photos[0:third],
        "left":  photos[third:third*2],
        "right": photos[third*2:n],
    }

    _get_rec_session()  # ensure loaded before threads

    def process_photo(p: str) -> Optional[List[float]]:
        img = decode_base64_image(p)
        if img is None:
            return None
        # ML Kit already cropped to face — use no-detect path if small (224x224)
        h, w = img.shape[:2]
        if max(h, w) <= 256:
            return extract_embedding_no_detect(img)
        img = _resize_for_embedding(img, 480)
        return extract_embedding(img)

    result = {}
    with ThreadPoolExecutor(max_workers=3) as executor:
        for angle, group in groups.items():
            futures = [executor.submit(process_photo, p) for p in group]
            embeddings = [f.result() for f in futures]
            embeddings = [e for e in embeddings if e is not None]
            if len(embeddings) < 1:
                raise ValueError(
                    f"No valid face detected for angle '{angle}'. "
                    f"Please ensure face is clearly visible."
                )
            result[angle] = average_embeddings(embeddings)

    result["profile_b64"] = photos[0]
    return result


def check_liveness(b64_image: str):
    return True, "liveness_skipped"
