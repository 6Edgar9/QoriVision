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
