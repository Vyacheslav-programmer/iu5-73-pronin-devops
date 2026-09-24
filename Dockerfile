FROM python:3.11-slim

LABEL maintainer="Пронин В.К." \
      description="VoiceGen API — FastAPI + GigaAM + Silero TTS" \
      version="1.0.0"

ARG APP_VERSION=1.0.0
ENV APP_VERSION=${APP_VERSION}

WORKDIR /app

# Системные зависимости
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libsndfile1 \
    ffmpeg \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Слой зависимостей — кэшируется
COPY requirements-docker.txt requirements-dev.txt ./
RUN pip install --no-cache-dir -r requirements-docker.txt -r requirements-dev.txt

# Слой кода — пересобирается при изменении
COPY server.py model_loader.py voicegen.py ./
COPY tests/ ./tests/
COPY pyproject.toml .

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -fsS http://localhost:8000/health || exit 1

CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8000"]
