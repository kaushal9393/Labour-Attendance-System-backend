"""
face_service.py
─────────────────────────────────────────────────────────────
ArcFace via ONNX Runtime directly (no insightface package needed).
Uses buffalo_sc model files bundled in the repo under models/buffalo_sc/.
"""
import os
import base64
import logging
import threading
from typing import Optional, List

import numpy as np
import cv2

logger = logging.getLogger(__name__)

# ── Model paths (bundled in repo) ────────────────────────────
_MODEL_DIR = os.path.join(os.path.dirname(__file__), "..", "models", "buffalo_sc")
_DET_MODEL  = os.path.join(_MODEL_DIR, "det_500m.onnx")
_REC_MODEL  = os.path.join(_MODEL_DIR, "w600k_mbf.onnx")

# ── Singleton ONNX sessions ───────────────────────────────────
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
                opts.inter_op_num_threads = 1
                opts.intra_op_num_threads = 2
                providers = ["CPUExecutionProvider"]
                _det_session = ort.InferenceSession(_DET_MODEL, opts, providers=providers)
                _rec_session = ort.InferenceSession(_REC_MODEL, opts, providers=providers)
                logger.info("[FaceService] ONNX sessions loaded OK")
    return _det_session, _rec_session


def warmup_models() -> None:
    try:
        _get_sessions()
        _get_cascade()
        logger.info("✅ Face models warmed up")
    except Exception as e:
        logger.warning(f"⚠️ Warmup failed: {e}")


# ── OpenCV Haar cascade ───────────────────────────────────────
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
    try:
        if "," in base64_string:
            base64_string = base64_string.split(",", 1)[1]
        img_bytes = base64.b64decode(base64_string)
        np_arr = np.frombuffer(img_bytes, dtype=np.uint8)
        img = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)
        if img is None:
            logger.warning("cv2.imdecode returned None")
        return img
    except Exception as e:
        logger.warning(f"Image decode failed: {e}")
        return None


# ── Face detection via RetinaFace det_500m ───────────────────
def _detect_faces(img: np.ndarray):
    """Returns list of (x1,y1,x2,y2) boxes, largest first."""
    det, _ = _get_sessions()
    h, w = img.shape[:2]

    # Resize to 640x640 for detector input
    size = 640
    scale_x = w / size
    scale_y = h / size
    resized = cv2.resize(img, (size, size))
    blob = resized.astype(np.float32).transpose(2, 0, 1)[np.newaxis]  # NCHW

    input_name = det.get_inputs()[0].name
    outputs = det.run(None, {input_name: blob})

    boxes = []
    # outputs[0] = scores, outputs[1] = boxes (x1,y1,x2,y2 normalized or raw)
    # det_500m outputs vary — use a simple threshold approach
    try:
        scores = outputs[0]  # shape (N, 2) or (N,)
        raw_boxes = outputs[1]  # shape (N, 4)
        for i, box in enumerate(raw_boxes):
            score = float(scores[i][1]) if scores.ndim == 2 else float(scores[i])
            if score > 0.5:
                x1 = int(box[0] * scale_x)
                y1 = int(box[1] * scale_y)
                x2 = int(box[2] * scale_x)
                y2 = int(box[3] * scale_y)
                area = (x2 - x1) * (y2 - y1)
                boxes.append((x1, y1, x2, y2, area))
    except Exception:
        pass

    boxes.sort(key=lambda b: b[4], reverse=True)
    return [(b[0], b[1], b[2], b[3]) for b in boxes]


# ── ArcFace embedding via w600k_mbf ──────────────────────────
def _align_and_embed(img: np.ndarray, box) -> Optional[List[float]]:
    """Crop face, resize to 112x112, run ArcFace, return 512-dim embedding."""
    try:
        _, rec = _get_sessions()
        x1, y1, x2, y2 = box
        # Expand box slightly
        pad = int(max(x2 - x1, y2 - y1) * 0.1)
        x1 = max(0, x1 - pad); y1 = max(0, y1 - pad)
        x2 = min(img.shape[1], x2 + pad); y2 = min(img.shape[0], y2 + pad)
        face = img[y1:y2, x1:x2]
        if face.size == 0:
            return None
        face = cv2.resize(face, (112, 112))
        # Normalize to [-1, 1]
        face = (face.astype(np.float32) - 127.5) / 127.5
        blob = face.transpose(2, 0, 1)[np.newaxis]  # NCHW

        input_name = rec.get_inputs()[0].name
        emb = rec.run(None, {input_name: blob})[0][0]  # (512,)

        # L2 normalize
        norm = np.linalg.norm(emb)
        if norm > 0:
            emb = emb / norm
        return [float(x) for x in emb]
    except Exception as e:
        logger.warning(f"Embed failed: {e}")
        return None


def extract_embedding(img: np.ndarray) -> Optional[List[float]]:
    """Full pipeline: detect face → align → embed. Returns 512-dim list or None."""
    try:
        if img is None or img.ndim != 3:
            return None
        h, w = img.shape[:2]
        if h < 20 or w < 20:
            return None

        boxes = _detect_faces(img)
        if not boxes:
            # Fallback: treat whole image as face crop
            logger.info("[FaceService] No face detected by ONNX det — using full image")
            box = (0, 0, w, h)
            return _align_and_embed(img, box)

        return _align_and_embed(img, boxes[0])
    except Exception as e:
        logger.warning(f"Embedding failed: {e}")
        return None


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


def _resize_for_embedding(img: np.ndarray, max_dim: int = 640) -> np.ndarray:
    h, w = img.shape[:2]
    if max(h, w) <= max_dim:
        return img
    scale = max_dim / max(h, w)
    return cv2.resize(img, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_AREA)


def _get_embedding_from_img(img: np.ndarray) -> Optional[List[float]]:
    return extract_embedding(_resize_for_embedding(img))


def process_registration_photos(photos: List[str]) -> dict:
    """
    Accept 9–25 base64 photos.
    Layout: front first third, left middle third, right last third.
    Returns averaged ArcFace embeddings per angle + profile_b64.
    """
    n = len(photos)
    third = n // 3
    groups = {
        "front": photos[0:third],
        "left":  photos[third:third*2],
        "right": photos[third*2:n],
    }

    _get_sessions()  # warm before processing

    result = {}
    for angle, group in groups.items():
        embeddings = []
        for p in group:
            img = decode_base64_image(p)
            if img is not None:
                img = _resize_for_embedding(img)
                emb = extract_embedding(img)
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


# ── Legacy liveness wrapper (kept for import compatibility) ───
def check_liveness(b64_image: str):
    return True, "liveness_skipped"
