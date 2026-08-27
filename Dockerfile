FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=18765

WORKDIR /app

# Text-safe OkeyX backend payload. No gzip/tar.gz binary artifacts.
COPY deploy/backend_source.b64 /tmp/backend_source.b64

RUN python -c "import base64,io,pathlib,tarfile; p=pathlib.Path('/tmp/backend_source.b64'); data=base64.b64decode(p.read_text(), validate=True); tarfile.open(fileobj=io.BytesIO(data), mode='r:xz').extractall('/app'); print('OKEYX_BACKEND_SOURCE_OK')" \
    && rm -f /tmp/backend_source.b64 \
    && mkdir -p /app/data

RUN pip install --no-cache-dir -r requirements.txt

EXPOSE 18765

CMD ["sh","-c","exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-18765}"]
