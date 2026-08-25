FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PORT=18765
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends patch ca-certificates && rm -rf /var/lib/apt/lists/*
COPY deploy/backend_v101.tar.gz /tmp/backend.tar.gz
COPY deploy/backend_v11.patch /tmp/backend_v11.patch
RUN tar -xzf /tmp/backend.tar.gz -C /app \
    && cd /app \
    && patch -p1 < /tmp/backend_v11.patch \
    && rm -f /tmp/backend.tar.gz /tmp/backend_v11.patch
RUN pip install --no-cache-dir -r requirements.txt
EXPOSE 18765
# OkeyX public multiplayer release backend. Railway health probes use /healthz.
CMD ["sh","-c","exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-18765}"]
