"""
azure_face_service.py — Azure Face API integration.
Replaces ArcFace ONNX with Azure Cognitive Services Face API.
Uses PersonGroup for 1:N identification.
"""
import os
import base64
import logging
import time
import requests
from typing import Optional

logger = logging.getLogger(__name__)

AZURE_ENDPOINT = os.getenv("AZURE_FACE_ENDPOINT", "").rstrip("/")
AZURE_KEY      = os.getenv("AZURE_FACE_KEY", "")
PERSON_GROUP_PREFIX = "garage"

HEADERS = {
    "Ocp-Apim-Subscription-Key": AZURE_KEY,
    "Content-Type": "application/json",
}
HEADERS_OCTET = {
    "Ocp-Apim-Subscription-Key": AZURE_KEY,
    "Content-Type": "application/octet-stream",
}


def _group_id(company_id: int) -> str:
    return f"{PERSON_GROUP_PREFIX}-{company_id}"


def ensure_person_group(company_id: int) -> None:
    """Create PersonGroup for company if it doesn't exist."""
    gid = _group_id(company_id)
    url = f"{AZURE_ENDPOINT}/face/v1.0/persongroups/{gid}"
    r = requests.get(url, headers=HEADERS)
    if r.status_code == 404:
        r2 = requests.put(url, headers=HEADERS, json={
            "name": f"Garage Company {company_id}",
            "recognitionModel": "recognition_04",
        })
        if r2.status_code not in (200, 202):
            raise RuntimeError(f"Failed to create PersonGroup: {r2.text}")
        logger.info(f"[Azure] PersonGroup created: {gid}")
    elif r.status_code != 200:
        raise RuntimeError(f"PersonGroup check failed: {r.text}")


def create_person(company_id: int, employee_name: str) -> str:
    """Create a Person in the PersonGroup. Returns azure_person_id."""
    ensure_person_group(company_id)
    gid = _group_id(company_id)
    url = f"{AZURE_ENDPOINT}/face/v1.0/persongroups/{gid}/persons"
    r = requests.post(url, headers=HEADERS, json={"name": employee_name})
    if r.status_code != 200:
        raise RuntimeError(f"Failed to create Person: {r.text}")
    person_id = r.json()["personId"]
    logger.info(f"[Azure] Person created: {employee_name} → {person_id}")
    return person_id


def add_face_to_person(company_id: int, person_id: str, image_b64: str) -> Optional[str]:
    """Add a face image to a Person. Returns persistedFaceId or None."""
    gid = _group_id(company_id)
    url = f"{AZURE_ENDPOINT}/face/v1.0/persongroups/{gid}/persons/{person_id}/persistedFaces"

    # Strip data URL prefix if present
    if "," in image_b64:
        image_b64 = image_b64.split(",", 1)[1]

    try:
        img_bytes = base64.b64decode(image_b64)
    except Exception as e:
        logger.warning(f"[Azure] Base64 decode failed: {e}")
        return None

    r = requests.post(url, headers=HEADERS_OCTET, data=img_bytes)
    if r.status_code == 200:
        return r.json().get("persistedFaceId")
    else:
        logger.warning(f"[Azure] AddFace failed ({r.status_code}): {r.text}")
        return None


def train_person_group(company_id: int) -> None:
    """Train the PersonGroup. Must be called after adding faces."""
    gid = _group_id(company_id)
    url = f"{AZURE_ENDPOINT}/face/v1.0/persongroups/{gid}/train"
    r = requests.post(url, headers=HEADERS)
    if r.status_code not in (200, 202):
        raise RuntimeError(f"Training failed: {r.text}")

    # Poll until training complete (max 30s)
    status_url = f"{AZURE_ENDPOINT}/face/v1.0/persongroups/{gid}/training"
    for _ in range(30):
        time.sleep(1)
        rs = requests.get(status_url, headers=HEADERS)
        if rs.status_code == 200:
            status = rs.json().get("status")
            if status == "succeeded":
                logger.info(f"[Azure] Training complete for group {gid}")
                return
            elif status == "failed":
                raise RuntimeError(f"Training failed: {rs.json()}")
    logger.warning(f"[Azure] Training timeout for group {gid}")


def delete_person(company_id: int, person_id: str) -> None:
    """Delete a Person from the PersonGroup."""
    gid = _group_id(company_id)
    url = f"{AZURE_ENDPOINT}/face/v1.0/persongroups/{gid}/persons/{person_id}"
    r = requests.delete(url, headers=HEADERS)
    if r.status_code not in (200, 204):
        logger.warning(f"[Azure] Delete person failed ({r.status_code}): {r.text}")
    else:
        logger.info(f"[Azure] Person deleted: {person_id}")
    # Retrain after deletion
    try:
        train_person_group(company_id)
    except Exception as e:
        logger.warning(f"[Azure] Retrain after delete failed: {e}")


def detect_face(image_b64: str) -> Optional[str]:
    """
    Detect a face in image. Returns faceId string or None if no face found.
    faceId expires in 24 hours — use only for immediate identify call.
    """
    if "," in image_b64:
        image_b64 = image_b64.split(",", 1)[1]

    try:
        img_bytes = base64.b64decode(image_b64)
    except Exception as e:
        logger.warning(f"[Azure] Detect base64 decode failed: {e}")
        return None

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
        logger.info("[Azure] No face detected in image")
        return None

    # Return largest face's faceId
    largest = max(faces, key=lambda f: f["faceRectangle"]["width"] * f["faceRectangle"]["height"])
    return largest["faceId"]


def identify_face(company_id: int, face_id: str) -> Optional[tuple]:
    """
    Identify face against PersonGroup.
    Returns (person_id, confidence) or None if no match.
    """
    gid = _group_id(company_id)
    url = f"{AZURE_ENDPOINT}/face/v1.0/identify"
    payload = {
        "faceIds": [face_id],
        "personGroupId": gid,
        "maxNumOfCandidatesReturned": 1,
        "confidenceThreshold": 0.6,
    }
    r = requests.post(url, headers=HEADERS, json=payload)
    if r.status_code != 200:
        logger.warning(f"[Azure] Identify failed ({r.status_code}): {r.text}")
        return None

    results = r.json()
    if not results or not results[0].get("candidates"):
        logger.info("[Azure] No match found")
        return None

    best = results[0]["candidates"][0]
    return best["personId"], float(best["confidence"])


def register_employee_faces(company_id: int, employee_name: str, photos: list) -> str:
    """
    Full registration flow:
    1. Create Person
    2. Add all photos as faces
    3. Train PersonGroup
    Returns azure_person_id.
    """
    ensure_person_group(company_id)
    person_id = create_person(company_id, employee_name)

    added = 0
    for photo_b64 in photos:
        face_id = add_face_to_person(company_id, person_id, photo_b64)
        if face_id:
            added += 1

    if added == 0:
        # Clean up person since no faces added
        delete_person(company_id, person_id)
        raise ValueError(
            "No valid face detected in any photo. "
            "Please retake photos with face clearly visible."
        )

    logger.info(f"[Azure] {added}/{len(photos)} faces added for {employee_name}")
    train_person_group(company_id)
    return person_id
