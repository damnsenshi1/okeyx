FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=10000

WORKDIR /app

COPY deploy/render_backend_*.b64 /tmp/okeyx_parts/

RUN cat /tmp/okeyx_parts/render_backend_*.b64 > /tmp/backend.b64 \
    && python -c "import base64,hashlib,io,pathlib,tarfile; raw=''.join(pathlib.Path('/tmp/backend.b64').read_text().split()); data=base64.b64decode(raw,validate=False); d=hashlib.sha256(data).hexdigest(); print('OKEYX_BACKEND_PAYLOAD_SHA256',d); tarfile.open(fileobj=io.BytesIO(data),mode='r:xz').extractall('/app'); print('OKEYX_BACKEND_SOURCE_OK')" \
    && rm -rf /tmp/okeyx_parts /tmp/backend.b64 \
    && mkdir -p /app/data

RUN pip install --no-cache-dir -r requirements.txt

EXPOSE 10000

CMD ["sh","-c","exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-10000}"]
