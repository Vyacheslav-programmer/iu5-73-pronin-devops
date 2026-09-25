# АРЭ ПО Модуль 2 — Пронин В.К.

Лабораторная работа по курсу «Автоматизация развёртывания и эксплуатации ПО».

- **Студент:** Пронин Вячеслав Константинович
- **Группа:** ИУ5Ц-93Б
- **Вариант:** 15 (обязательное) + 5 (дополнительное)
- **Преподаватель:** Балашов А.М.

## Задачи семинаров по Модулю 2

### Семинар 1. Виртуализация и контейнеризация

Изучены материалы: https://devops.science.iu5.bmstu.ru/containers/virt

Основные темы:

- Разница между виртуализацией и контейнеризацией
- Типы гипервизоров (тип 1 — bare-metal, тип 2 — hosted)
- Модели виртуализации (VM, application container, system container)
- Ключевые понятия: namespaces, cgroups, chroot, overlayfs, veth

### Семинар 2. Bash-эмулятор контейнера (emulate)

Запущен скрипт `container-emulator.sh`:
https://devops.science.iu5.bmstu.ru/containers/seminars/insidecont/emulate

Что демонстрирует скрипт:

- **Overlayfs**: lowerdir (Alpine) + upperdir (изменения) + merged (точка монтирования)
- **Cgroups v2**: memory.max=268435456 (256 МБ), cpu.max=50000 100000 (50% CPU)
- **Network namespace**: `container-net` с veth-парой
- **veth-пара**: veth0 (хост) ↔ veth1 (контейнер, IP 10.0.0.2)
- **iptables NAT/DNAT/SNAT**: проброс порта 8000 + MASQUERADE
- **unshare + chroot**: ручная изоляция (без OCI-спецификации, в отличие от runc)
- **Alpine Linux + Python 3 + FastAPI**: внутри эмулятора

Результат: `curl http://localhost:8000/health` → `{"status":"ok"}`

### Семинар 3. Работа с Docker и Podman

Изучены материалы: https://devops.science.iu5.bmstu.ru/containers/seminars/containers/docker_and_podman

Выполнено:

- Установлены Docker 29.2.1 и Podman 5.8.5 в ALT Linux
- Запущен `hello-world` через оба рантайма
- Собраны кастомные образы из одного Dockerfile
- Тесты запущены внутри обоих контейнеров

---

## Задание по варианту (Вариант 15) — контейнер на runc

Запущен OCI-контейнер через рантайм `runc`:

- **OCI bundle**: `config.json` + `rootfs` (overlayfs)
- **Namespaces**: pid, mount, uts, ipc, network
- **Cgroups v2**: 256 МБ памяти, 50% ядра CPU
- **Сеть**: veth-пара + network namespace + iptables NAT/DNAT
- **Внутри контейнера**: Alpine Linux + Python 3 + FastAPI + uvicorn

Скрипт `container-runc.sh` поднимает контейнер, FastAPI доступен на `http://localhost:8000/health` → `{"status":"ok"}`.

---

## Дополнительное задание (Вариант 5) — Dockerfile для ML-сервиса

Создан многослойный `Dockerfile` для FastAPI-приложения:

- **Базовый образ**: `python:3.11-slim`
- **LABEL, ARG, ENV** — метаданные и версия
- **Слои**: системные зависимости → pip-зависимости → код
- **HEALTHCHECK** — проверка `/health`
- **EXPOSE 8000**, **CMD uvicorn**
- **Упрощённый `requirements-docker.txt`** — без `torch`/`transformers` (обосновано: torch без +cpu тянет 4 ГБ CUDA-библиотек, а тесты используют mock `model_loader`)

Собраны образы в **Docker** и **Podman** из одного `Dockerfile` / `Containerfile`:

- Docker: `voicegen-api:latest` — 1.03 ГБ
- Podman: `voicegen-api-podman:latest` — 1.05 ГБ
- **Тесты `pytest tests/ -v` внутри обоих контейнеров — 7 passed**

---

## Артефакты

- `container-emulator.sh` — bash-эмулятор контейнера (семинар)
- `container-runc.sh` — контейнер на runc (задание 15)
- `Dockerfile`, `Containerfile` — инструкции сборки образа (задание 20)
- `requirements-docker.txt` — минимальный набор зависимостей для образа