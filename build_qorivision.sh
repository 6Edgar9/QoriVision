#!/usr/bin/env bash
# ==============================================================================
# QoriVision - Biometric Oracle Service Builder
# Microservicio de oráculo biométrico (Liveness y Face Matching) para Blockchain
# ==============================================================================
set -e

echo "=== [1/5] Generando requirements.txt ==="
cat << 'EOF' > requirements.txt
fastapi>=0.100.0
uvicorn[standard]>=0.22.0
python-multipart>=0.0.6
opencv-python-headless>=4.8.0
numpy>=1.24.0
EOF

echo "=== [2/5] Generando main.py (FastAPI Biometric Oracle) ==="
cat << 'EOF' > main.py
import asyncio
import hashlib
import time
import cv2
import numpy as np
from fastapi import FastAPI, File, Form, HTTPException, UploadFile, status

app = FastAPI(
    title="QoriVision - Biometric Oracle",
    description="Microservicio de oráculo biométrico (Liveness y Face Matching) para votación en Blockchain",
    version="1.0.0"
)

@app.post("/api/verify")
async def verify_elector(
    dni: str = Form(...),
    file: UploadFile = File(...)
):
    start_time = time.perf_counter()

    # 1. Lectura asíncrona de los bytes binarios de la imagen
    contents = await file.read()
    if not contents:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El archivo proporcionado está vacío."
        )

    # 2. Conversión del buffer a matriz NumPy y decodificación con OpenCV en memoria
    nparr = np.frombuffer(contents, np.uint8)
    image_mat = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

    if image_mat is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Decodificación fallida: el archivo no es una imagen válida o compatible."
        )

    # 3. Inferencia simulada: Red Neuronal Convolucional (CNN) para Liveness Detection y Face Matching
    # (e.g., Silent-Face-Anti-Spoofing + ArcFace / FaceNet)
    await asyncio.sleep(0.5)

    # 4. Generación criptográfica del Nullifier Seed
    # En esquemas de votación anónima (ZKP / Semaphore), el nullifier previene la doble emisión de votos
    # sin revelar la identidad real del elector en el ledger.
    h = hashlib.sha256()
    h.update(dni.encode("utf-8"))
    h.update(image_mat.tobytes()[:1024])  # Huella de características faciales
    h.update(b"qorivision_blockchain_oracle_salt")
    nullifier_seed = h.hexdigest()

    execution_time_ms = round((time.perf_counter() - start_time) * 1000, 2)

    # 5. Respuesta JSON con la estructura exacta requerida
    return {
        "status": "verified",
        "confidence": 99.8,
        "nullifier_seed": nullifier_seed,
        "execution_time_ms": execution_time_ms
    }

@app.get("/health")
def health_check():
    return {"status": "ok", "service": "QoriVision"}
EOF

echo "=== [3/5] Generando Dockerfile ==="
cat << 'EOF' > Dockerfile
FROM python:3.10-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .

EXPOSE 8081

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8081"]
EOF

echo "=== [4/5] Construyendo imagen Docker (qorivision-image) y levantando contenedor ==="
docker build -t qorivision-image .

echo "Deteniendo contenedores previos si existen..."
docker rm -f qorivision-app 2>/dev/null || true

echo "Levantando qorivision-app en segundo plano en puerto 8081..."
docker run -d --name qorivision-app -p 8081:8081 qorivision-image

echo "Esperando 4 segundos para que Uvicorn inicie..."
sleep 4

echo "=== [5/5] Generando imagen de prueba y ejecutando verificación biométrica ==="
# Generación dinámica de la imagen sintética de prueba directamente con el contenedor activo (OpenCV + NumPy)
docker exec qorivision-app python -c "import cv2, numpy as np; img = np.full((150, 150, 3), (120, 150, 180), dtype=np.uint8); cv2.circle(img, (75, 75), 40, (200, 220, 240), -1); cv2.imwrite('/tmp/test_face.jpg', img)"
docker cp qorivision-app:/tmp/test_face.jpg ./test_face.jpg

echo "Enviando solicitud POST multipart/form-data a http://localhost:8081/api/verify..."
RESPONSE=$(curl -s -X POST "http://localhost:8081/api/verify" \
  -F "dni=76543210" \
  -F "file=@test_face.jpg")

echo ""
echo "=== RESPUESTA DEL ORÁCULO BIOMÉTRICO (QoriVision) ==="
echo "$RESPONSE"
echo ""
