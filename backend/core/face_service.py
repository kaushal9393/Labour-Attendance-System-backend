"""
face_service.py — ArcFace via InsightFace (buffalo_sc model).
Supports both 9-photo (ML Kit cropped) and legacy 25-photo registration.
"""
import os
import base64
import logging
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Optional, List

import numpy as np
import cv2

logger = logging.getLogger(__name__)

_insight_app = None
_model_lock  = threading.Lock()


def _get_insight():
    global _insight_app
    if _insight_app is None:
        with _model_lock:
            if _insight_app is None:
                try:
                    from insightface.app import FaceAnalysis
                    app = FaceAnalysis(
                        name="buffalo_sc",
                        providers=["CPUExecutionProvider"],
                    )
                    app.prepare(ctx_id=0, det_size=(320, 320))
                    _insight_app = app
                    logger.info("[Warmup] Loading InsightFace ArcFace model… done")
                except Exception as e:
                    logger.error(f"InsightFace load failed: {e}")
                    raise
    return _insight_app


_face_cascade = None

def _get_cascade():
    global _face_cascade
    if _face_cascade is None:
        logger.info("[Warmup] Loading Haar cascade…")
        _face_cascade = cv2.CascadeClassifier(
            cv2.data.haarcascades + "haarcascade_frontalface_default.xml"
        )
    return _face_cascade


def warmup_models() -> None:
    try:
        _get_insight()
        # Warm with dummy image
        dummy = np.zeros((160, 160, 3), dtype=np.uint8)
        _get_insight().get(dummy)
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


def extract_embedding(img: np.ndarray) -> Optional[List[float]]:
    """Run InsightFace ArcFace on BGR image. Returns 512-dim list or None."""
    try:
        if img is None or img.ndim != 3 or img.shape[0] < 20 or img.shape[1] < 20:
            return None
        app = _get_insight()
        faces = app.get(img)
        if not faces:
            return None
        face = max(faces, key=lambda f: (f.bbox[2]-f.bbox[0])*(f.bbox[3]-f.bbox[1]))
        emb = face.normed_embedding if hasattr(face, "normed_embedding") else face.embedding
        if emb is None or len(emb) != 512:
            return None
        emb = np.asarray(emb, dtype=np.float32)
        norm = np.linalg.norm(emb)
        if norm > 0:
            emb = emb / norm
        return [float(x) for x in emb]
    except Exception as e:
        logger.warning(f"Embedding failed: {e}")
        return None


def extract_embedding_no_detect(img: np.ndarray) -> Optional[List[float]]:
    """
    For ML Kit pre-cropped images (224x224 face crop).
    Resize to 112x112 and run ArcFace recognition directly — skip detection.
    """
    try:
        if img is None or img.ndim != 3:
            return None
        # Resize to 112x112 (ArcFace input size)
        face = cv2.resize(img, (112, 112))
        face_norm = (face.astype(np.float32) - 127.5) / 127.5
        blob = face_norm.transpose(2, 0, 1)[np.newaxis]  # NCHW

        import onnxruntime as ort
        # Reuse rec session from insightface if available
        app = _get_insight()
        # Get recognition model session directly
        rec_model = None
        for model in app.models.values():
            if hasattr(model, 'session') and '112' in str(getattr(model, 'input_size', '')):
                rec_model = model
                break
        if rec_model is None:
            # Fallback: use full insightface pipeline on resized image
            return extract_embedding(face)

        session = rec_model.session
        input_name = session.get_inputs()[0].name
        emb = session.run(None, {input_name: blob})[0][0]
        norm = np.linalg.norm(emb)
        if norm > 0:
            emb = emb / norm
        return [float(x) for x in emb]
    except Exception as e:
        logger.warning(f"extract_embedding_no_detect failed, using full pipeline: {e}")
        # Fallback to full detection pipeline
        return extract_embedding(img)


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

    _get_insight()  # ensure loaded before threads

    def process_photo(p: str) -> Optional[List[float]]:
        img = decode_base64_image(p)
        if img is None:
            return None
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
