# АРЭ ПО Модуль 1 — Пронин В.К.

Лабораторная работа по курсу «Автоматизация развёртывания и эксплуатации ПО».

- **Студент:** Пронин Вячеслав Константинович
- **Группа:** ИУ5Ц-93Б
- **Вариант:** 15 (обязательное) + 5 (дополнительное)
- **Преподаватель:** Балашов А.М.

## Удалённый репозиторий

- **Сфера Код:** https://bmstu.saas.sferaplatform.ru/sourcecode/projects/stud.iu5/repos/IU5-73_Pronin
- **GitHub:** https://github.com/Vyacheslav-programmer/iu5-73-pronin-devops

## Задачи семинара 1 и семинара 2

### Семинар 1. Работа с репозиторием Git

Повторены операции из семинара (clone/add/commit/push, структура проекта, ветки).

Проект: `server.py`, `voicegen.py`, `model_loader.py`, тесты `tests/`, зависимости `requirements.txt` / `requirements-dev.txt`.

### Семинар 2. Hooks и CI (Jenkins)

Git hooks в `.githooks/`:

- `pre-commit` — проверка TODO в staged Python-файлах
- `pre-push` — запуск pytest перед push
- `commit-msg` — проверка формата сообщения коммита (feat/fix/docs/ci/chore/test/refactor)

Активация хуков:

git config core.hooksPath .githooks

Jenkins: корневой `Jenkinsfile`, стадии Checkout → Setup Python → Install dependencies → Compilation Check → Linting → TODO Check → Unit Tests → Integration Tests → Security Scan → Load Test → Aggregate Report.

## Задание по варианту (Вариант 15)

Рабочий процесс GitHub Actions — `.github/workflows/ci.yml`.

- Триггеры: `push` и `pull_request` в ветки `main` и `master`.
- Шаги совпадают с Jenkins: Checkout → Setup Python → Setup Environment → Compilation Check → Linting → TODO Check → Tests.

## Дополнительное задание (Вариант 5)

Интеграция Git Hooks с Jenkins Pipeline:

- `commit-msg` — контроль формата сообщений.
- `aggregate-report.sh` — сборка единого отчёта `report.md`.
- `tests/test_loadtest.py` — заглушка нагрузочного теста.
- Security Scan (bandit + safety).
- Агрегация результатов через `archiveArtifacts` в Jenkins.

Jenkins сборка #7 — SUCCESS, все 10 стадий выполнены, артефакты сохранены.

## Структура проекта

| Файл | Назначение |
|------|------------|
| `server.py` | FastAPI-приложение (транскрипция аудио) |
| `voicegen.py` | Скрипт синтеза речи (Silero TTS) |
| `model_loader.py` | Загрузка модели GigaAM |
| `tests/test_server.py` | pytest-тесты API |
| `tests/test_loadtest.py` | Заглушка нагрузочного теста |
| `tests/conftest.py` | Фикстуры pytest |
| `tests/model_loader.py` | Mock модели для тестов |
| `Jenkinsfile` | CI в Jenkins (10 стадий) |
| `.github/workflows/ci.yml` | CI в GitHub Actions (7 шагов) |
| `.githooks/pre-commit` | Хук: проверка TODO |
| `.githooks/pre-push` | Хук: запуск pytest |
| `.githooks/commit-msg` | Хук: проверка формата коммита |
| `ci-check.sh` | Скрипт проверки TODO в проекте |
| `aggregate-report.sh` | Скрипт сборки единого отчёта |
| `pyproject.toml` | Конфиг ruff + pytest |
| `requirements.txt` | Основные зависимости |
| `requirements-dev.txt` | Зависимости для разработки |

## Ссылки

- **Страница в Сфере Знания:** https://bmstu.saas.sferaplatform.ru/knowledge/pages?id=487
- **Merge Request:** https://bmstu.saas.sferaplatform.ru/sourcecode/projects/stud.iu5/repos/IU5-73_Pronin/pulls/2
- **GitHub Actions:** https://github.com/Vyacheslav-programmer/iu5-73-pronin-devops/actions
