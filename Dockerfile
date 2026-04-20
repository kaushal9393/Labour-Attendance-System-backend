FROM python:3.11-slim

# System deps for OpenCV + InsightFace
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    g++ \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# ── Layer 1: Heavy ML packages (cached — only reinstall if this line changes) ──
# InsightFace + onnxruntime replaces tensorflow-cpu/deepface entirely.
# RAM: ~250MB vs 800MB+ for TF — fits Railway free tier (512MB).
RUN pip install --no-cache-dir \
    "insightface==0.7.3" \
    "onnxruntime==1.17.1" \
    "numpy==1.26.4" \
    "opencv-python-headless>=4.10.0" \
    "pillow>=10.4.0"

# ── Layer 2: Pre-download ArcFace model weights ─────────────────
# Bake model into image so cold-start doesn't hit network timeout.
RUN python - <<'EOF'
from insightface.app import FaceAnalysis
import numpy as np
app = FaceAnalysis(name="buffalo_sc", providers=["CPUExecutionProvider"])
app.prepare(ctx_id=0, det_size=(320, 320))
dummy = np.zeros((160, 160, 3), dtype="uint8")
faces = app.get(dummy)
print(f"[Docker] InsightFace model pre-loaded OK (faces on dummy: {len(faces)})")
EOF

# ── Layer 3: Light app dependencies ─────────────────────────────
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# ── Layer 4: Application code ────────────────────────────────────
COPY . .

EXPOSE 8000

CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT:-8000} --workers 1"]
