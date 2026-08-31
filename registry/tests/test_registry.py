"""Testes unitários do registry."""

import pytest

from app.security import SourceValidationError, parse_ollama_model, validate_source_uri
from app.services.routing import build_litellm_route


class TestSourceValidation:
    def test_ollama_simple_name(self):
        uri = validate_source_uri("ollama", "llama3.2")
        assert uri == "ollama://llama3.2"
        assert parse_ollama_model(uri) == "llama3.2"

    def test_ollama_uri_scheme(self):
        uri = validate_source_uri("ollama", "ollama://qwen3:8b")
        assert uri == "ollama://qwen3:8b"

    def test_hf_shorthand(self):
        uri = validate_source_uri("huggingface", "Qwen/Qwen3-8B")
        assert uri == "hf://Qwen/Qwen3-8B"

    def test_hf_url(self):
        uri = validate_source_uri("huggingface", "https://huggingface.co/meta-llama/Llama-3.2-3B")
        assert uri == "hf://meta-llama/Llama-3.2-3B"

    def test_blocks_file_scheme(self):
        with pytest.raises(SourceValidationError):
            validate_source_uri("ollama", "file:///etc/passwd")

    def test_blocks_private_ip(self):
        with pytest.raises(SourceValidationError):
            validate_source_uri("other", "http://127.0.0.1/model")


class TestRouting:
    def test_dyn_route_namespace(self):
        route = build_litellm_route("app-cutcast01", "my-llm", "ollama://llama3.2")
        assert route.startswith("dyn-")
        assert "my-llm" in route

    def test_route_without_alias(self):
        route = build_litellm_route("app-abcdef12", None, "ollama://qwen3:8b")
        assert route.startswith("dyn-abcdef12-")
