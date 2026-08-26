FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=18765

WORKDIR /app

# OkeyX V11.0.23 production backend
COPY deploy/backend_v11_0_23_fixed.tar.gz /tmp/backend.tar.gz

RUN gzip -t /tmp/backend.tar.gz \
    && tar -xzf /tmp/backend.tar.gz -C /app \
    && rm -f /tmp/backend.tar.gz \
    && mkdir -p /app/data

RUN pip install --no-cache-dir -r requirements.txt

EXPOSE 18765

CMD ["sh","-c","exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-18765}"]
