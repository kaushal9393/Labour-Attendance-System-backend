"""
face_service.py — ArcFace via ONNX Runtime directly (no insightface).
buffalo_sc model files in /app/models/buffalo_sc/ (downloaded at build time).
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

_MODEL_DIR = os.path.join(os.path.dirname(__file__), "..", "models", "buffalo_sc")
_DET_MODEL = os.path.join(_MODEL_DIR, "det_500m.onnx")
_REC_MODEL = os.path.join(_MODEL_DIR, "w600k_mbf.onnx")

_det_session = None
_rec_session = None
_model_lock  = threading.Lock()


def _get_sessions():
    global _det_session, _rec_session
    if _det_session is None or _rec_session is None:
        with _model_lock:
            if _det_session is None or _rec_session is None:
                import onnxruntime as ort
                opts = ort.SessionOptions()
                opts.inter_op_num_threads = 2
                opts.intra_op_num_threads = 2
                providers = ["CPUExecutionProvider"]
                _det_session = ort.InferenceSession(_DET_MODEL, opts, providers=providers)
                _rec_session = ort.InferenceSession(_REC_MODEL, opts, providers=providers)
                logger.info("[FaceService] ONNX sessions loaded OK")
    return _det_session, _rec_session


def warmup_models() -> None:
    try:
        det, rec = _get_sessions()
        # Warm det
        dummy_det = np.zeros((1, 3, 320, 320), dtype=np.float32)
        det.run(None, {det.get_inputs()[0].name: dummy_det})
        # Warm rec
        dummy_rec = np.zeros((1, 3, 112, 112), dtype=np.float32)
        rec.run(None, {rec.get_inputs()[0].name: dummy_rec})
        _get_cascade()
        logger.info("✅ Face models warmed up")
    except Exception as e:
        logger.warning(f"⚠️ Warmup failed: {e}")


_face_cascade = None

def _get_cascade():
    global _face_cascade
    if _face_cascade is None:
        _face_cascade = cv2.CascadeClassifier(
            cv2.data.haarcascades + "haarcascade_frontalface_default.xml"
        )
    return _face_cascade


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


def _detect_face_box(img: np.ndarray):
    """Run det_500m at 320x320 (faster than 640). Returns (x1,y1,x2,y2) or None."""
    det, _ = _get_sessions()
    h, w = img.shape[:2]
    size = 320  # 4x faster than 640, still accurate enough
    scale_x, scale_y = w / size, h / size
    resized = cv2.resize(img, (size, size))
    blob = resized.astype(np.float32).transpose(2, 0, 1)[np.newaxis]
    try:
        outputs = det.run(None, {det.get_inputs()[0].name: blob})
        scores, raw_boxes = outputs[0], outputs[1]
        best_box, best_score = None, 0.4
        for i, box in enumerate(raw_boxes):
            score = float(scores[i][1]) if scores.ndim == 2 else float(scores[i])
            if score > best_score:
                best_score = score
                best_box = (
                    int(box[0] * scale_x), int(box[1] * scale_y),
                    int(box[2] * scale_x), int(box[3] * scale_y),
                )
        return best_box
    except Exception:
        return None


def _embed_face_crop(img: np.ndarray, box=None) -> Optional[List[float]]:
    """Crop to box (or full image), resize 112x112, run ArcFace."""
    try:
        _, rec = _get_sessions()
        h, w = img.shape[:2]
        if box:
            x1, y1, x2, y2 = box
            pad = int(max(x2 - x1, y2 - y1) * 0.1)
            x1 = max(0, x1 - pad); y1 = max(0, y1 - pad)
            x2 = min(w, x2 + pad); y2 = min(h, y2 + pad)
            face = img[y1:y2, x1:x2]
        else:
            face = img
        if face is None or face.size == 0:
            return None
        face = cv2.resize(face, (112, 112))
        face = (face.astype(np.float32) - 127.5) / 127.5
        blob = face.transpose(2, 0, 1)[np.newaxis]
        emb = rec.run(None, {rec.get_inputs()[0].name: blob})[0][0]
        norm = np.linalg.norm(emb)
        if norm > 0:
            emb = emb / norm
        return [float(x) for x in emb]
    except Exception as e:
        logger.warning(f"Embed failed: {e}")
        return None


def extract_embedding(img: np.ndarray) -> Optional[List[float]]:
    """Detect face → embed. For scan: skip detection, use full image directly."""
    if img is None or img.ndim != 3 or img.shape[0] < 20 or img.shape[1] < 20:
        return None
    box = _detect_face_box(img)
    return _embed_face_crop(img, box)  # box=None → full image crop


def extract_embedding_no_detect(img: np.ndarray) -> Optional[List[float]]:
    """Skip face detection — treat full image as face. Use for scan (faster)."""
    if img is None or img.ndim != 3:
        return None
    return _embed_face_crop(img, None)


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
    9–25 base64 photos → averaged ArcFace embeddings per angle.
    Uses ThreadPoolExecutor for parallel processing across all photos.
    """
    n = len(photos)
    third = n // 3
    groups = {
        "front": photos[0:third],
        "left":  photos[third:third*2],
        "right": photos[third*2:n],
    }

    _get_sessions()  # ensure sessions loaded before threads start

    def process_photo(p: str) -> Optional[List[float]]:
        img = decode_base64_image(p)
        if img is None:
            return None
        # Flutter ML Kit already cropped the face to 224×224 — skip server detection
        return extract_embedding_no_detect(img)

    result = {}
    # Process all photos in parallel across all angles
    with ThreadPoolExecutor(max_workers=4) as executor:
        for angle, group in groups.items():
            futures = {executor.submit(process_photo, p): p for p in group}
            embeddings = []
            for fut in as_completed(futures):
                emb = fut.result()
                if emb is not None:
                    embeddings.append(emb)
            if len(embeddings) < 1:
                raise ValueError(
                    f"Not enough valid face photos for angle '{angle}' "
                    f"(got {len(embeddings)}/min 1)"
                )
            result[angle] = average_embeddings(embeddings)

    result["profile_b64"] = photos[0]
    return result


def check_liveness(b64_image: str):
    return True, "liveness_skipped"
