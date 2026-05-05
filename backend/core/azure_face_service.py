"""
azure_face_service.py — Azure Face API using FaceList + FindSimilar.
No Limited Access approval needed (unlike PersonGroup/Identify).
"""
import os
import base64
import logging
import requests
from typing import Optional

logger = logging.getLogger(__name__)

AZURE_ENDPOINT = os.getenv("AZURE_FACE_ENDPOINT", "").rstrip("/")
AZURE_KEY      = os.getenv("AZURE_FACE_KEY", "")
FACELIST_PREFIX = "garage"

HEADERS = {
    "Ocp-Apim-Subscription-Key": AZURE_KEY,
    "Content-Type": "application/json",
}
HEADERS_OCTET = {
    "Ocp-Apim-Subscription-Key": AZURE_KEY,
    "Content-Type": "application/octet-stream",
}

CONFIDENCE_THRESHOLD = 0.6


def _list_id(company_id: int) -> str:
    return f"{FACELIST_PREFIX}-{company_id}"


def ensure_face_list(company_id: int) -> None:
    """Create FaceList for company if it doesn't exist."""
    lid = _list_id(company_id)
    url = f"{AZURE_ENDPOINT}/face/v1.0/facelists/{lid}"
    r = requests.get(url, headers=HEADERS)
    if r.status_code == 404:
        r2 = requests.put(url, headers=HEADERS, json={
            "name": f"Company {company_id}",
            "recognitionModel": "recognition_04",
        })
        if r2.status_code not in (200, 202):
            raise RuntimeError(f"Failed to create FaceList: {r2.text}")
        logger.info(f"[Azure] FaceList created: {lid}")
    elif r.status_code != 200:
        raise RuntimeError(f"FaceList check failed: {r.text}")


def detect_face_from_bytes(img_bytes: bytes) -> Optional[str]:
    """Detect largest face, return faceId (temporary, 24h expiry)."""
    url = (
        f"{AZURE_ENDPOINT}/face/v1.0/detect"
        "?returnFaceId=true"
        "&detectionModel=detection_03"
        "&recognitionModel=recognition_04"
    )
    r = requests.post(url, headers=HEADERS_OCTET, data=img_bytes)
    if r.status_code != 200:
        logger.warning(f"[Azure] Detect failed ({r.status_code}): {r.text}")
        return None
    faces = r.json()
    if not faces:
        return None
    largest = max(faces, key=lambda f: f["faceRectangle"]["width"] * f["faceRectangle"]["height"])
    return largest["faceId"]


def _b64_to_bytes(image_b64: str) -> Optional[bytes]:
    if "," in image_b64:
        image_b64 = image_b64.split(",", 1)[1]
    try:
        return base64.b64decode(image_b64)
    except Exception as e:
        logger.warning(f"[Azure] Base64 decode failed: {e}")
        return None


def detect_face(image_b64: str) -> Optional[str]:
    """Detect face from base64 image. Returns temporary faceId or None."""
    img_bytes = _b64_to_bytes(image_b64)
    if img_bytes is None:
        return None
    return detect_face_from_bytes(img_bytes)


def add_face_to_list(company_id: int, image_b64: str, user_data: str) -> Optional[str]:
    """
    Add a face to FaceList. user_data stores employee info for lookup.
    Returns persistedFaceId (permanent) or None.
    """
    ensure_face_list(company_id)
    lid = _list_id(company_id)
    url = (
        f"{AZURE_ENDPOINT}/face/v1.0/facelists/{lid}/persistedFaces"
        f"?userData={user_data}"
        "&detectionModel=detection_03"
    )
    img_bytes = _b64_to_bytes(image_b64)
    if img_bytes is None:
        return None

    r = requests.post(url, headers=HEADERS_OCTET, data=img_bytes)
    if r.status_code == 200:
        return r.json().get("persistedFaceId")
    else:
        logger.error(f"[Azure] AddFace failed ({r.status_code}): {r.text}")
        raise RuntimeError(f"AddFace failed ({r.status_code}): {r.text}")


def find_similar(company_id: int, face_id: str) -> Optional[tuple]:
    """
    Find most similar face in FaceList.
    Returns (persisted_face_id, confidence) or None.
    """
    lid = _list_id(company_id)
    url = f"{AZURE_ENDPOINT}/face/v1.0/findsimilars"
    payload = {
        "faceId": face_id,
        "faceListId": lid,
        "maxNumOfCandidatesReturned": 1,
        "mode": "matchPerson",
    }
    r = requests.post(url, headers=HEADERS, json=payload)
    if r.status_code != 200:
        logger.warning(f"[Azure] FindSimilar failed ({r.status_code}): {r.text}")
        return None
    results = r.json()
    if not results:
        return None
    best = results[0]
    confidence = float(best.get("confidence", 0))
    if confidence < CONFIDENCE_THRESHOLD:
        return None
    return best["persistedFaceId"], confidence


def delete_faces_from_list(company_id: int, persisted_face_ids: list) -> None:
    """Delete all faces of an employee from the FaceList."""
    lid = _list_id(company_id)
    for fid in persisted_face_ids:
        url = f"{AZURE_ENDPOINT}/face/v1.0/facelists/{lid}/persistedFaces/{fid}"
        r = requests.delete(url, headers=HEADERS)
        if r.status_code not in (200, 204):
            logger.warning(f"[Azure] Delete face failed ({r.status_code}): {r.text}")


def register_employee_faces(company_id: int, employee_id_placeholder: str, photos: list) -> list:
    """
    Add all photos to FaceList.
    user_data = employee_id_placeholder (will be updated after DB insert).
    Returns list of persistedFaceIds.
    """
    ensure_face_list(company_id)
    persisted_ids = []
    for photo_b64 in photos:
        pid = add_face_to_list(company_id, photo_b64, user_data=employee_id_placeholder)
        if pid:
            persisted_ids.append(pid)

    if not persisted_ids:
        raise ValueError(
            "No valid face detected in any photo. "
            "Please retake photos with face clearly visible and good lighting."
        )
    logger.info(f"[Azure] {len(persisted_ids)}/{len(photos)} faces registered")
    return persisted_ids


def update_face_userdata(company_id: int, persisted_face_id: str, employee_id: int) -> None:
    """Update userData on a persisted face to store the real employee ID."""
    lid = _list_id(company_id)
    url = f"{AZURE_ENDPOINT}/face/v1.0/facelists/{lid}/persistedFaces/{persisted_face_id}"
    r = requests.patch(url, headers=HEADERS, json={"userData": str(employee_id)})
    if r.status_code not in (200, 204):
        logger.warning(f"[Azure] UpdateUserData failed ({r.status_code}): {r.text}")
