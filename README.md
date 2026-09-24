# АРЭ ПО Модуль 2 — Пронин В.К.

Лабораторная работа по курсу «Автоматизация развёртывания и эксплуатации ПО».

- **Студент:** Пронин Вячеслав Константинович
- **Группа:** ИУ5Ц-93Б
- **Вариант:** 15 (обязательное) + 5 (дополнительное)
- **Преподаватель:** Балашов А.М.

### Задание по варианту (Вариант 15) — контейнер на runc

Запущен OCI-контейнер через рантайм `runc`:

- **OCI bundle**: `config.json` + `rootfs` (overlayfs)
- **Namespaces**: pid, mount, uts, ipc, network
- **Cgroups v2**: 256 МБ памяти, 50% ядра CPU
- **Сеть**: veth-пара + network namespace + iptables NAT/DNAT
- **Внутри контейнера**: Alpine Linux + Python 3 + FastAPI + uvicorn

Скрипт `container-runc.sh` поднимает контейнер, FastAPI доступен на `http://localhost:8000/health` → `{"status":"ok"}`.

### Дополнительное задание (Вариант 5) — Dockerfile для ML-сервиса

Создан многослойный `Dockerfile` для FastAPI-приложения:

- **Базовый образ**: `python:3.11-slim`
- **LABEL, ARG, ENV** — метаданные и версия
- **Слои**: системные зависимости → pip-зависимости → код
- **HEALTHCHECK** — проверка `/health`
- **EXPOSE 8000**, **CMD uvicorn**
- **Упрощённый `requirements-docker.txt`** — без `torch`/`transformers` (обосновано в отчёте)

Собраны образы в **Docker** и **Podman** из одного `Dockerfile` / `Containerfile`:

- Docker: `voicegen-api:latest` — 1.03 ГБ
- Podman: `voicegen-api-podman:latest` — 1.05 ГБ
- **Тесты `pytest tests/ -v` внутри обоих контейнеров — 7 passed**

Артефакты:

- `Dockerfile`, `Containerfile` — инструкции сборки
- `requirements-docker.txt` — минимальный набор зависимостей для образа
- `container-runc.sh` — скрипт для задания 15