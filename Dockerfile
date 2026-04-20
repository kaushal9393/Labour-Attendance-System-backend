FROM python:3.11-slim

# System deps for OpenCV + MediaPipe
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# ── Layer 1: Heavy ML packages (cached until this RUN changes) ──
# Install these first so they are NOT reinstalled on every code/deps push.
RUN pip install --no-cache-dir \
    "tensorflow-cpu==2.16.1" \
    "tf-keras==2.16.0" \
    "deepface==0.0.93" \
    "mediapipe==0.10.9" \
    "numpy==1.26.4" \
    "opencv-python-headless>=4.10.0" \
    "pillow>=10.4.0"

# ── Layer 2: Pre-download ArcFace model weights ─────────────────
# Bake the model into the image so cold-start doesn't time out.
RUN python - <<'EOF'
import os
os.environ["TF_USE_LEGACY_KERAS"] = "1"
os.environ["TF_CPP_MIN_LOG_LEVEL"] = "3"
from deepface import DeepFace
try:
    import numpy as np
    dummy = np.zeros((112, 112, 3), dtype="uint8")
    DeepFace.represent(img_path=dummy, model_name="ArcFace",
                       detector_backend="opencv", enforce_detection=False)
    print("[Docker] ArcFace model pre-loaded OK")
except Exception as e:
    print(f"[Docker] Model pre-load warning (non-fatal): {e}")
EOF

# ── Layer 3: Remaining app dependencies (changes often) ─────────
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# ── Layer 4: Application code ────────────────────────────────────
COPY . .

EXPOSE 8000

CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT:-8000}"]
