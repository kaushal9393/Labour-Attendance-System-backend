# syntax=docker/dockerfile:1
# v2 — cache busted
FROM python:3.10-slim

RUN apt-get update && apt-get install -y \
    libgl1 libglib2.0-0 libsm6 libxext6 libxrender-dev libgomp1 wget unzip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install all deps — NO insightface, direct onnxruntime only
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
    tqdm requests easydict

# Download buffalo_sc ONNX model files at build time
RUN mkdir -p /app/models/buffalo_sc && \
    wget -q "https://github.com/deepinsight/insightface/releases/download/v0.7/buffalo_sc.zip" \
         -O /tmp/buffalo_sc.zip && \
    unzip -o /tmp/buffalo_sc.zip -d /app/models/buffalo_sc && \
    rm /tmp/buffalo_sc.zip && \
    ls -lh /app/models/buffalo_sc/

COPY requirements.txt .
COPY . .

EXPOSE 8080
CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT:-8080}"]
