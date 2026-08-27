FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=10000

WORKDIR /app

COPY deploy/render_backend_*.b64 /tmp/okeyx_parts/

RUN cat /tmp/okeyx_parts/render_backend_*.b64 > /tmp/backend.b64 \
    && python -c "import base64,hashlib,io,pathlib,tarfile; raw=pathlib.Path('/tmp/backend.b64').read_text(); data=base64.b64decode(raw,validate=True); d=hashlib.sha256(data).hexdigest(); expected='569ee854dc4b130e3698b85afac79bbd66a19d7ebf31e1288a283ff5e6b356ca'; assert d==expected,(d,expected); tarfile.open(fileobj=io.BytesIO(data),mode='r:xz').extractall('/app'); print('OKEYX_BACKEND_SOURCE_OK',d)" \
    && rm -rf /tmp/okeyx_parts /tmp/backend.b64 \
    && mkdir -p /app/data

RUN pip install --no-cache-dir -r requirements.txt

EXPOSE 10000

CMD ["sh","-c","exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-10000}"]
