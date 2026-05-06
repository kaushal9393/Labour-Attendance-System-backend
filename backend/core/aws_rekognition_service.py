"""
aws_rekognition_service.py — AWS Rekognition Face Collections.
Drop-in replacement for the Azure FaceList + FindSimilar flow.

Per company we maintain one Rekognition Collection (id: garage-<company_id>).
- detect_face        : verifies a face exists in the image (no FaceId stored).
- add_face_to_list   : IndexFaces — stores a permanent FaceId in the collection.
- find_similar       : SearchFacesByImage — returns best match + confidence.
- delete_faces       : DeleteFaces.
"""
import os
import base64
import logging
from typing import Optional, List, Tuple

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger(__name__)

AWS_REGION         = os.getenv("AWS_REGION", "ap-south-1")
AWS_ACCESS_KEY_ID  = os.getenv("AWS_ACCESS_KEY_ID") or os.getenv("AWS_ACCESS_KEY")
AWS_SECRET_KEY     = os.getenv("AWS_SECRET_ACCESS_KEY") or os.getenv("AWS_SECRET_KEY")

COLLECTION_PREFIX = "garage"

# Rekognition similarity is 0-100. Azure's 0.6 threshold ≈ 80% on Rekognition.
SIMILARITY_THRESHOLD = float(os.getenv("AWS_FACE_SIMILARITY_THRESHOLD", "80"))

_client = None


def _get_client():
    global _client
    if _client is None:
        kwargs = {"region_name": AWS_REGION}
        if AWS_ACCESS_KEY_ID and AWS_SECRET_KEY:
            kwargs["aws_access_key_id"]     = AWS_ACCESS_KEY_ID
            kwargs["aws_secret_access_key"] = AWS_SECRET_KEY
        _client = boto3.client("rekognition", **kwargs)
    return _client


def _collection_id(company_id: int) -> str:
    return f"{COLLECTION_PREFIX}-{company_id}"


def _b64_to_bytes(image_b64: str) -> Optional[bytes]:
    if "," in image_b64:
        image_b64 = image_b64.split(",", 1)[1]
    try:
        return base64.b64decode(image_b64)
    except Exception as e:
        logger.warning(f"[AWS] Base64 decode failed: {e}")
        return None


def ensure_face_list(company_id: int) -> None:
    """Create Rekognition collection for company if it doesn't exist."""
    cid = _collection_id(company_id)
    client = _get_client()
    try:
        client.create_collection(CollectionId=cid)
        logger.info(f"[AWS] Collection created: {cid}")
    except ClientError as e:
        if e.response["Error"]["Code"] == "ResourceAlreadyExistsException":
            return
        raise


def detect_face_from_bytes(img_bytes: bytes) -> Optional[bool]:
    """Return True if at least one face is detected. Returns None on API error."""
    try:
        resp = _get_client().detect_faces(
            Image={"Bytes": img_bytes},
            Attributes=["DEFAULT"],
        )
        faces = resp.get("FaceDetails", [])
        return True if faces else False
    except ClientError as e:
        logger.warning(f"[AWS] DetectFaces failed: {e}")
        return None


def detect_face(image_b64: str) -> Optional[bool]:
    """Detect face from base64 image. Returns True/False, or None on decode error."""
    img_bytes = _b64_to_bytes(image_b64)
    if img_bytes is None:
        return None
    return detect_face_from_bytes(img_bytes)


def add_face_to_list(company_id: int, image_b64: str, user_data: str) -> Optional[str]:
    """
    Index a face into the company collection.
    user_data goes into ExternalImageId (employee identifier — alphanumeric/_/-/. only).
    Returns the permanent FaceId or None.
    """
    ensure_face_list(company_id)
    img_bytes = _b64_to_bytes(image_b64)
    if img_bytes is None:
        return None

    safe_external_id = "".join(c if c.isalnum() or c in "_-." else "_" for c in str(user_data))[:255]

    try:
        resp = _get_client().index_faces(
            CollectionId=_collection_id(company_id),
            Image={"Bytes": img_bytes},
            ExternalImageId=safe_external_id,
            DetectionAttributes=[],
            MaxFaces=1,
            QualityFilter="AUTO",
        )
    except ClientError as e:
        logger.error(f"[AWS] IndexFaces failed: {e}")
        raise RuntimeError(f"IndexFaces failed: {e}")

    records = resp.get("FaceRecords", [])
    if not records:
        return None
    return records[0]["Face"]["FaceId"]


def find_similar(company_id: int, image_b64_or_bytes) -> Optional[Tuple[str, float]]:
    """
    Search collection for the best matching face.
    Accepts either base64 string or raw bytes (kept compatible with attendance flow).
    Returns (face_id, similarity_0_to_1) or None.
    """
    if isinstance(image_b64_or_bytes, (bytes, bytearray)):
        img_bytes = bytes(image_b64_or_bytes)
    else:
        img_bytes = _b64_to_bytes(image_b64_or_bytes)
    if img_bytes is None:
        return None

    try:
        resp = _get_client().search_faces_by_image(
            CollectionId=_collection_id(company_id),
            Image={"Bytes": img_bytes},
            MaxFaces=1,
            FaceMatchThreshold=SIMILARITY_THRESHOLD,
        )
    except ClientError as e:
        code = e.response["Error"]["Code"]
        # InvalidParameterException is returned when no face is found in the input image
        if code in ("InvalidParameterException", "ResourceNotFoundException"):
            logger.info(f"[AWS] SearchFacesByImage no-match ({code})")
            return None
        logger.warning(f"[AWS] SearchFacesByImage failed: {e}")
        return None

    matches = resp.get("FaceMatches", [])
    if not matches:
        return None
    best = matches[0]
    face_id = best["Face"]["FaceId"]
    similarity = float(best["Similarity"]) / 100.0  # normalize to 0-1 for callers
    return face_id, similarity


def delete_faces_from_list(company_id: int, face_ids: List[str]) -> None:
    """Delete faces (by FaceId) from the collection."""
    if not face_ids:
        return
    try:
        _get_client().delete_faces(
            CollectionId=_collection_id(company_id),
            FaceIds=face_ids,
        )
    except ClientError as e:
        logger.warning(f"[AWS] DeleteFaces failed: {e}")


def register_employee_faces(company_id: int, employee_id_placeholder: str, photos: list) -> list:
    """
    Index all photos into the company collection.
    Returns list of permanent FaceIds.
    """
    ensure_face_list(company_id)
    face_ids: List[str] = []
    for photo_b64 in photos:
        try:
            fid = add_face_to_list(company_id, photo_b64, user_data=employee_id_placeholder)
        except RuntimeError as e:
            logger.warning(f"[AWS] Skipping photo: {e}")
            continue
        if fid:
            face_ids.append(fid)

    if not face_ids:
        raise ValueError(
            "No valid face detected in any photo. "
            "Please retake photos with face clearly visible and good lighting."
        )
    logger.info(f"[AWS] {len(face_ids)}/{len(photos)} faces registered")
    return face_ids


def update_face_userdata(company_id: int, face_id: str, employee_id: int) -> None:
    """
    Rekognition does not support mutating ExternalImageId after indexing.
    We re-associate by deleting + re-indexing only if needed elsewhere; for the
    current flow the DB already maps face_ids -> employee_id, so this is a no-op
    kept for API compatibility with the old Azure module.
    """
    return None
