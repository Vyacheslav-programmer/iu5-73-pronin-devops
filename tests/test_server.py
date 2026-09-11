"""Тесты для server.py."""
from server import add, hello


def test_hello():
    assert isinstance(hello(), str)


def test_add():
    assert add(2, 3) == 5


def test_add_negative():
    assert add(-1, -1) == -2
