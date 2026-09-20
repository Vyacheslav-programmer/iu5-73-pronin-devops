# АРЭПО Модуль 1 — Пронин В.К.

Лабораторная работа по курсу «Автоматизация развёртывания и эксплуатации ПО».

**Студент:** Пронин Вячеслав Константинович  
**Группа:** ИУ5Ц-93Б  
**Вариант:** 15  
**Преподаватель:** Балашов А.М.

Remote Сферы: https://gateway-bmstu.saas.sferaplatform.ru/app/sourcecode/api/stud.iu5/IU5-73_Pronin.git

Текст для страницы знаний: [docs/knowledge.md](docs/knowledge.md)

## Задачи семинара 1 и семинара 2

### Семинар 1. Работа с репозиторием Git

Повторены операции из семинара (clone/add/commit/push, структура проекта, ветка `main`/`master`).

Проект: `server.py`, тесты `tests/`, зависимости `requirements.txt` / `requirements-dev.txt`.

### Семинар 2. Hooks и CI (Jenkins)

Git hooks в `.githooks/`:

```bash
git config core.hooksPath .githooks
```

- `pre-commit` — compileall + ruff
- `pre-push` — pytest

Jenkins: корневой `Jenkinsfile`, те же стадии, что и GitHub Actions.

Подключение в Jenkins: New Item → Pipeline → Pipeline from SCM → Git (URL репозитория Сферы) → Script Path = `Jenkinsfile`.

## Задание по варианту

**Вариант 15.** GitHub Actions workflow `.github/workflows/ci.yml`

- триггеры: `push` и `pull_request` в `main`;
- шаги совпадают с Jenkins: Checkout → Setup Python 3.11 → Install dependencies → Compilation Check → Linting → Tests.

## Дополнительное задание

Не выполнялось.

## Структура

| Файл | Назначение |
| --- | --- |
| `server.py` | учебное Python-приложение |
| `tests/test_server.py` | pytest |
| `Jenkinsfile` | CI в Jenkins (семинар) |
| `.github/workflows/ci.yml` | CI в GitHub Actions (вариант 15) |
| `.githooks/` | pre-commit / pre-push |
| `docs/knowledge.md` | текст для Сферы → Знания |
