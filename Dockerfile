FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PORT=10000
WORKDIR /app
COPY backend/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt
COPY backend/app ./app
RUN mkdir -p /app/data
EXPOSE 10000
CMD ["sh","-c","exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-10000}"]
