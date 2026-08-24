FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PORT=18765
WORKDIR /app
COPY deploy/backend_v101.tar.gz /tmp/backend.tar.gz
RUN tar -xzf /tmp/backend.tar.gz -C /app && rm -f /tmp/backend.tar.gz
RUN pip install --no-cache-dir -r requirements.txt
EXPOSE 18765
CMD ["sh","-c","uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-18765}"]
