"""
face_service.py
─────────────────────────────────────────────────────────────
ArcFace embedding generation (DeepFace) + MediaPipe liveness
detection for the Garage Attendance System.
"""
import os
os.environ.setdefault("TF_USE_LEGACY_KERAS", "1")
os.environ.setdefault("TF_ENABLE_ONEDNN_OPTS", "0")
os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")

import base64
import io
import logging
from typing import Optional, Tuple, List

import numpy as np
import cv2
from PIL import Image

logger = logging.getLogger(__name__)

# ── Lazy imports so startup is fast even if GPU is slow ──────
_deepface = None
_mp_face_mesh = None
_face_mesh_instance = None


def _get_deepface():
    global _deepface
    if _deepface is None:
        from deepface import DeepFace
        _deepface = DeepFace
    return _deepface


_MEDIAPIPE_UNAVAILABLE = False  # set True if import fails

def _get_face_mesh():
    global _mp_face_mesh, _face_mesh_instance, _MEDIAPIPE_UNAVAILABLE
    if _MEDIAPIPE_UNAVAILABLE:
        return None
    if _face_mesh_instance is None:
        try:
            import mediapipe as mp
            _mp_face_mesh = mp.solutions.face_mesh
            _face_mesh_instance = _mp_face_mesh.FaceMesh(
                static_image_mode=True,
                max_num_faces=1,
                refine_landmarks=True,
                min_detection_confidence=0.5,
            )
        except Exception as exc:
            logger.warning(f"[MediaPipe] Unavailable, liveness check disabled: {exc}")
            _MEDIAPIPE_UNAVAILABLE = True
            return None
    return _face_mesh_instance


# ── Helpers ──────────────────────────────────────────────────
def decode_base64_image(base64_string: str) -> Optional[np.ndarray]:
    """Decode base64 (with or without data: prefix) to BGR uint8 ndarray, or None on failure."""
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
        logger.warning(f"Image decode failed: {str(e)}")
        return None


def _base64_to_bgr(b64: str) -> np.ndarray:
    """Legacy PIL-based decoder kept for liveness path."""
    if "," in b64:
        b64 = b64.split(",", 1)[1]
    img_bytes = base64.b64decode(b64)
    pil_img   = Image.open(io.BytesIO(img_bytes)).convert("RGB")
    return cv2.cvtColor(np.array(pil_img), cv2.COLOR_RGB2BGR)


def _bgr_to_rgb(img: np.ndarray) -> np.ndarray:
    return cv2.cvtColor(img, cv2.COLOR_BGR2RGB)


# ── Liveness detection ────────────────────────────────────────
EAR_THRESHOLD = 0.20  # Eye Aspect Ratio minimum

def _eye_aspect_ratio(landmarks, eye_indices: List[int], w: int, h: int) -> float:
    """
    Simplified EAR using MediaPipe landmark pixel coords.
    eye_indices: [top, bottom, left, right] (4 points)
    """
    pts = [(int(landmarks[i].x * w), int(landmarks[i].y * h)) for i in eye_indices]
    # vertical distance
    v = abs(pts[0][1] - pts[1][1])
    # horizontal distance
    ho = abs(pts[2][0] - pts[3][0])
    return v / (ho + 1e-6)

# MediaPipe 468-landmark indices for eye corners + lids
LEFT_EYE_INDICES  = [159, 145, 33, 133]   # top, bottom, left, right
RIGHT_EYE_INDICES = [386, 374, 362, 263]
NOSE_TIP_INDEX    = 1


def check_liveness(b64_image: str) -> Tuple[bool, str]:
    """
    Returns (is_live: bool, reason: str).
    If MediaPipe is unavailable, skips liveness and returns True so face
    matching can still proceed.
    """
    try:
        face_mesh = _get_face_mesh()
        if face_mesh is None:
            # MediaPipe not available — skip liveness, rely on face matching
            return True, "liveness_skipped"

        img_bgr = _base64_to_bgr(b64_image)
        img_rgb = _bgr_to_rgb(img_bgr)
        h, w    = img_rgb.shape[:2]

        results = face_mesh.process(img_rgb)

        if not results.multi_face_landmarks:
            return False, "no_face_detected"

        lm = results.multi_face_landmarks[0].landmark

        left_ear  = _eye_aspect_ratio(lm, LEFT_EYE_INDICES,  w, h)
        right_ear = _eye_aspect_ratio(lm, RIGHT_EYE_INDICES, w, h)
        ear       = (left_ear + right_ear) / 2.0

        if ear < EAR_THRESHOLD:
            return False, "eyes_closed"

        # Nose tip visibility (z-depth proxy — should be close to 0)
        nose_z = lm[NOSE_TIP_INDEX].z
        if nose_z > 0.1:
            return False, "face_not_frontal"

        return True, "live"

    except Exception as exc:
        logger.warning(f"[Liveness] Error (skipping, relying on face match): {exc}")
        return True, "liveness_skipped"


# ── ArcFace embedding ─────────────────────────────────────────
def extract_embedding(img: np.ndarray) -> Optional[List[float]]:
    """Run DeepFace ArcFace on a BGR uint8 ndarray. Returns 512-dim list or None."""
    try:
        if img is None or not isinstance(img, np.ndarray):
            logger.warning("Invalid image input — not a numpy array")
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

        if not result or len(result) == 0:
            logger.warning("DeepFace returned empty result")
            return None

        embedding = result[0]["embedding"]
        if len(embedding) != 512:
            logger.warning(f"Unexpected embedding size: {len(embedding)}")
            return None

        return [float(x) for x in embedding]

    except Exception as e:
        logger.warning(f"Embedding failed: {str(e)}")
        return None


def get_embedding(b64_image: str) -> Optional[List[float]]:
    """Base64 wrapper around extract_embedding."""
    img = decode_base64_image(b64_image)
    if img is None:
        return None
    return extract_embedding(img)


def average_embeddings(embeddings: List[List[float]]) -> List[float]:
    """Average a list of 512-dim embeddings into one representative vector."""
    arr = np.array([e for e in embeddings if e is not None])
    if len(arr) == 0:
        raise ValueError("No valid embeddings to average")
    avg = np.mean(arr, axis=0)
    # L2-normalise so cosine similarity == dot product
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

    Returns:
      {
        "front": [512-dim list],
        "left":  [512-dim list],
        "right": [512-dim list],
        "profile_b64": str   # first photo for Cloudinary upload
      }
    """
    groups = {
        "front": photos[0:9],
        "left":  photos[9:17],
        "right": photos[17:25],
    }
    result = {}
    for angle, group_photos in groups.items():
        embeddings = []
        for p in group_photos:
            emb = get_embedding(p)
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
