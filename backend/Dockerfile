FROM python:3.10-slim

# System deps for OpenCV + InsightFace ONNX
RUN apt-get update && apt-get install -y \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    gcc \
    g++ \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .

# Install all deps including insightface
# Python 3.10 has pre-built wheels for insightface 0.7.3 (no source compile needed)
RUN pip install --no-cache-dir \
    fastapi==0.111.0 \
    "uvicorn[standard]==0.29.0" \
    asyncpg==0.29.0 \
    "sqlalchemy[asyncio]==2.0.30" \
    "python-jose[cryptography]==3.3.0" \
    bcrypt==4.1.3 \
    python-multipart==0.0.9 \
    python-dotenv==1.0.1 \
    "numpy==1.26.4" \
    opencv-python-headless==4.9.0.80 \
    cloudinary==1.40.0 \
    "httpx==0.27.0" \
    "pillow==10.4.0" \
    pgvector==0.2.5 \
    onnxruntime==1.17.3 \
    tqdm \
    requests \
    easydict \
    Cython \
    insightface==0.7.3

# Strip heavy optional packages insightface pulled (keep onnx — insightface needs it)
RUN pip uninstall -y scipy scikit-learn scikit-image matplotlib albumentations \
    imageio tifffile lazy_loader || true

COPY . .

# Pre-download buffalo_sc model into the image — avoids runtime download on Railway
RUN python -c "\
from insightface.app import FaceAnalysis; \
import numpy as np; \
app = FaceAnalysis(name='buffalo_sc', providers=['CPUExecutionProvider']); \
app.prepare(ctx_id=0, det_size=(160,160)); \
print('buffalo_sc model downloaded OK') \
"

EXPOSE 8080
CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT:-8080}"]
