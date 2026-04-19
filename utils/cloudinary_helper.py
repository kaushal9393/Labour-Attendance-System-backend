import os
import base64
import logging
from typing import Optional

import cloudinary
import cloudinary.uploader
from dotenv import load_dotenv

load_dotenv()
logger = logging.getLogger(__name__)

cloudinary.config(
    cloud_name  = os.getenv("CLOUDINARY_CLOUD_NAME"),
    api_key     = os.getenv("CLOUDINARY_API_KEY"),
    api_secret  = os.getenv("CLOUDINARY_API_SECRET"),
    secure      = True,
)


def upload_base64_photo(b64_image: str, folder: str = "garage_employees") -> Optional[str]:
    """
    Upload a base64 image to Cloudinary.
    Returns the secure URL or None on failure.
    """
    try:
        if "," in b64_image:
            b64_image = b64_image.split(",", 1)[1]

        result = cloudinary.uploader.upload(
            f"data:image/jpeg;base64,{b64_image}",
            folder=folder,
            resource_type="image",
            format="jpg",
            quality="auto:good",
        )
        return result.get("secure_url")
    except Exception as exc:
        logger.error(f"[Cloudinary] Upload failed: {exc}")
        return None


def delete_photo(public_id: str) -> bool:
    """Delete a photo from Cloudinary by public_id."""
    try:
        cloudinary.uploader.destroy(public_id)
        return True
    except Exception as exc:
        logger.error(f"[Cloudinary] Delete failed: {exc}")
        return False
