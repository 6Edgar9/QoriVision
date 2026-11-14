# 🧠 Explicación Técnica y Arquitectura del Código - QoriVision

Este documento detalla los componentes, decisiones de diseño de software, manejo de visión computacional en memoria y consideraciones criptográficas implementadas en el microservicio **QoriVision**.

---

## 1. Servidor Principal: `main.py`

El archivo [main.py](main.py) alberga la API REST asíncrona implementada con **FastAPI**. Está optimizado para alto rendimiento bajo concurrencia, procesamiento en memoria sin persistencia en disco y derivación determinista de credenciales.

### 1.1 Ingesta Asíncrona y Streaming de Archivos
```python
@app.post("/api/verify")
async def verify_elector(
    dni: str = Form(...),
    file: UploadFile = File(...)
):
```
- **`dni: str = Form(...)` y `file: UploadFile = File(...)`**: Permite recibir simultáneamente datos estructurados y binarios a través del protocolo estándar `multipart/form-data`.
- **`contents = await file.read()`**: Lee de forma no bloqueante el stream binario de la imagen hacia la memoria RAM. Al ser asíncrono, no bloquea el hilo principal del *Event Loop* de Uvicorn mientras se transfieren los bytes por la red.

### 1.2 Pipeline de Visión Computacional en Memoria (Zero Disk I/O)
```python
nparr = np.frombuffer(contents, np.uint8)
image_mat = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
```
- **`np.frombuffer(contents, np.uint8)`**: Crea una vista unidimensional contigua en memoria del array de bytes entrante sin realizar copias adicionales en RAM.
- **`cv2.imdecode(nparr, cv2.IMREAD_COLOR)`**: 
  - Decodifica directamente la compresión del formato visual (JPEG, PNG, etc.) a una matriz multidimensional BGR compatible con OpenCV ($H \times W \times C$).
  - **Decisión de Diseño Crítica:** Se prescinde por completo del uso de `cv2.imread()` o archivos temporales en disco (`/tmp/`). Esto elimina la latencia de operaciones de I/O en almacenamiento y cumple con normativas estrictas de protección de datos personales (GDPR/APEP), garantizando que las caras de los votantes jamás queden grabadas en medios físicos del servidor.
- **Validación de Integridad:** Si la imagen está corrompida o contiene un payload inválido, `cv2.imdecode` retorna `None`, lo cual es interceptado inmediatamente retornando un código HTTP `400 Bad Request`.

### 1.3 Inferencia de Red Neuronal Convolucional (CNN)
```python
await asyncio.sleep(0.5)
```
- En un despliegue de producción con pesos pre-entrenados, este bloque ejecuta dos redes profundas:
  1. **Liveness CNN (Anti-Spoofing):** Modelos como *Silent-Face-Anti-Spoofing* o *MiniFASNet* que analizan patrones de reflectancia, textura de pantalla o bordes de papel impreso para detectar ataques de presentación.
  2. **Face Feature Extraction:** Redes convolucionales como *ArcFace* o *FaceNet* que proyectan la cara en un vector latente de 512 dimensiones (embedding normalizado) para validar similitud contra el padrón electoral.
- El retardo simulado de `0.5s` modela el tiempo de procesamiento típico de inferencia en CPU/GPU sin bloquear el servidor web.

### 1.4 Derivación Criptográfica: `nullifier_seed`
```python
h = hashlib.sha256()
h.update(dni.encode("utf-8"))
h.update(image_mat.tobytes()[:1024])
h.update(b"qorivision_blockchain_oracle_salt")
nullifier_seed = h.hexdigest()
```
- **Concepto Blockchain:** En protocolos de voto anónimo basados en Pruebas de Conocimiento Cero (*Zero-Knowledge Proofs* / *Semaphore*), el votante debe demostrar que pertenece a un árbol de Merkle de electores registrados sin revelar quién es. Para evitar que vote dos veces, el protocolo exige quemar un **Nullifier Hash**.
- El oráculo genera el `nullifier_seed` mezclando:
  1. Identificador cívico (`dni`).
  2. Firma biométrica derivada de la matriz de píxeles (`image_mat.tobytes()[:1024]`).
  3. Sal criptográfica privada del oráculo (`salt`).
- **Resultado:** Se emite una prueba criptográfica que autoriza la emisión de un voto único e irrepetible.

### 1.5 Métrica de Latencia
```python
start_time = time.perf_counter()
...
execution_time_ms = round((time.perf_counter() - start_time) * 1000, 2)
```
- Se utiliza `time.perf_counter()` para medir con precisión de microsegundos el tiempo total invertido desde la llegada del payload hasta la emisión de la respuesta JSON.

---

## 2. Definición del Contenedor: `Dockerfile`

El archivo [Dockerfile](Dockerfile) sigue los principios de contenedores efímeros y minimalistas:

1. **Imagen Base `python:3.10-slim`:**
   - Reduce la superficie de ataque y el peso total frente a imágenes completas basadas en Ubuntu, manteniendo compatibilidad con librerías compiladas en C de NumPy y OpenCV.
2. **Variables de Entorno de Python:**
   - `PYTHONDONTWRITEBYTECODE=1`: Evita que Python genere archivos de caché `.pyc` dentro del contenedor.
   - `PYTHONUNBUFFERED=1`: Fuerza el envío inmediato de logs estándar (stdout y stderr) a la consola de Docker sin pasar por buffers intermedios.
3. **Dependencias del Sistema:**
   - Se instala `curl` para permitir diagnósticos y comprobaciones de salud nativas del contenedor.
4. **Optimización de Capas de Caché:**
   - Se copia primero `requirements.txt` y se ejecuta `pip install` antes de copiar el código fuente. Esto asegura que si se modifica `main.py`, Docker reutilice la capa de dependencias compiladas sin reinstalarlas.
5. **Comando de Ejecución:**
   - `CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8081"]`: Enlaza el servidor en todas las interfaces de red para permitir la exposición del puerto fuera del contenedor Docker.

---

## 3. Dependencias: `requirements.txt`

El archivo [requirements.txt](requirements.txt) contiene el stack tecnológico base:
- `fastapi>=0.100.0`: Framework web de alto rendimiento basado en Starlette y Pydantic.
- `uvicorn[standard]>=0.22.0`: Servidor ASGI de ultra-baja latencia basado en `uvloop` y `httptools`.
- `python-multipart>=0.0.6`: Parser para procesar peticiones HTTP con cuerpos codificados en `multipart/form-data`.
- `opencv-python-headless>=4.8.0`: Versión de OpenCV compilada sin dependencias de interfaces gráficas de usuario (X11, Qt, GTK). Es la variante adecuada para servidores backend y contenedores Docker.
- `numpy>=1.24.0`: Soporte para álgebra lineal y manipulación rápida de matrices multidimensionales en C.

---

## 4. Orquestación y Automatización: `build_qorivision.sh`

El archivo [build_qorivision.sh](build_qorivision.sh) es un script de despliegue reproducible con cinco fases secuenciales:

1. **`set -e`**: Garantiza que si cualquier comando del pipeline falla, el script detenga su ejecución inmediatamente.
2. **Generación con Heredocs (`cat << 'EOF'`):** Escribe el código fuente desacoplado de dependencias externas.
3. **Ciclo de Vida de Docker:**
   - `docker build -t qorivision-image .`
   - `docker rm -f qorivision-app 2>/dev/null || true` (limpieza idempotente de contenedores previos).
   - `docker run -d --name qorivision-app -p 8081:8081 qorivision-image` (ejecución desacoplada en segundo plano).
4. **Período de Calentamiento:** `sleep 4` asegura que el Event Loop de FastAPI y el worker de Uvicorn completen su inicialización antes de recibir tráfico.
5. **Generación Dinámica de Imagen y Test en Caliente:**
   - Emplea el motor Python + OpenCV del propio contenedor para generar una imagen JPEG sintética válida (`test_face.jpg`) con un círculo que simula un rostro.
   - Ejecuta una petición real con `curl` enviando el DNI y la imagen adjunta.
   - Imprime el JSON de respuesta devuelto por el microservicio para verificación visual instantánea.
