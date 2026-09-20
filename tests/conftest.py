"""Test configuration and fixtures."""

import sys

import pytest
from fastapi.testclient import TestClient

from .model_loader import MockModel, ModelLoader


@pytest.fixture(scope="function")
def test_model():
    mock_model_instance = MockModel()
    mock_model_instance.result = {"text": "Привет мир"}
    mock_model_instance.side_effect = None

    test_loader = ModelLoader()
    test_loader.model = mock_model_instance

    fake_module = type(sys)("model_loader")
    fake_module.ModelLoader = ModelLoader
    fake_module.model_loader = test_loader

    existing_model_loader = sys.modules.get("model_loader")
    existing_server = sys.modules.get("server")

    sys.modules["model_loader"] = fake_module

    if "server" in sys.modules:
        del sys.modules["server"]

    yield mock_model_instance

    if existing_model_loader:
        sys.modules["model_loader"] = existing_model_loader
    elif "model_loader" in sys.modules:
        del sys.modules["model_loader"]

    if existing_server:
        sys.modules["server"] = existing_server
    elif "server" in sys.modules:
        del sys.modules["server"]


@pytest.fixture
def mock_model(test_model):
    return test_model


@pytest.fixture
def client(test_model):
    from server import app
    with TestClient(app) as test_client:
        yield test_client


@pytest.fixture
def sample_audio_bytes():
    import struct

    sample_rate = 44100
    num_channels = 1
    bits_per_sample = 16
    duration = 1
    num_samples = sample_rate * duration
    data_length = num_samples * num_channels * (bits_per_sample // 8)

    header = (
        b"RIFF"
        + struct.pack("<I", 36 + data_length)
        + b"WAVE"
        + b"fmt "
        + struct.pack("<I", 16)
        + struct.pack("<H", 1)
        + struct.pack("<H", num_channels)
        + struct.pack("<I", sample_rate)
        + struct.pack("<I", sample_rate * num_channels * (bits_per_sample // 8))
        + struct.pack("<H", num_channels * (bits_per_sample // 8))
        + struct.pack("<H", bits_per_sample)
        + b"data"
        + struct.pack("<I", data_length)
    )

    return header + b"\x00" * data_length
