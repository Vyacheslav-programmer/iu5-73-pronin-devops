"""Простой HTTP-сервер для проекта."""


def hello() -> str:
    """Возвращает приветствие."""
    return "Hello from АРЭПО!"


def add(a: int, b: int) -> int:
    """Складывает два числа."""
    return a + b


if __name__ == "__main__":
    print(hello())
    print(f"2 + 3 = {add(2, 3)}")
