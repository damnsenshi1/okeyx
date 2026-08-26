FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=18765

WORKDIR /app

# Railway runtime reconstructs the exact OkeyX V11.0.23 backend bundle from
# BUNDLE_* environment variables in the service start command. Do not unpack
# repository tarballs here: truncated binary artifacts caused Railway builds
# to fail with `gzip: unexpected end of file` before the app could start.
# Keeping the image stage intentionally minimal makes GitHub-triggered builds
# deterministic; dependencies are installed after the runtime bundle is restored.

EXPOSE 18765

CMD ["python", "-c", "print('OkeyX runtime image ready')"]
