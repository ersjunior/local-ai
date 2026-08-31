"""Validação de source_uri — proteção SSRF e allowlist."""

import ipaddress
import re
from urllib.parse import urlparse

ALLOWED_HOSTS = {
    "huggingface.co",
    "www.huggingface.co",
    "hf.co",
    "ollama.com",
    "registry.ollama.ai",
}

PRIVATE_NETS = [
    ipaddress.ip_network("10.0.0.0/8"),
    ipaddress.ip_network("172.16.0.0/12"),
    ipaddress.ip_network("192.168.0.0/16"),
    ipaddress.ip_network("127.0.0.0/8"),
    ipaddress.ip_network("169.254.0.0/16"),
    ipaddress.ip_network("::1/128"),
    ipaddress.ip_network("fc00::/7"),
]

OLLAMA_URI_RE = re.compile(r"^ollama://(?P<model>[a-zA-Z0-9._:/-]+)$")
HF_URI_RE = re.compile(r"^hf://(?P<repo>[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+)(?::(?P<tag>.+))?$")
HF_URL_RE = re.compile(
    r"^https?://(?:www\.)?huggingface\.co/(?P<repo>[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+)"
)


class SourceValidationError(ValueError):
    pass


def _is_private_ip(host: str) -> bool:
    try:
        ip = ipaddress.ip_address(host)
    except ValueError:
        return False
    return any(ip in net for net in PRIVATE_NETS)


def validate_source_uri(source_type: str, source_uri: str) -> str:
    """Valida e normaliza source_uri. Retorna URI normalizada."""
    uri = source_uri.strip()

    if uri.lower().startswith("file://"):
        raise SourceValidationError("file:// não é permitido")

    if source_type == "ollama":
        if OLLAMA_URI_RE.match(uri):
            return uri
        # Nome simples: llama3.2, library/model:tag
        if re.match(r"^[a-zA-Z0-9][a-zA-Z0-9._:/-]*$", uri) and "://" not in uri:
            return f"ollama://{uri}"
        raise SourceValidationError("URI Ollama inválida; use ollama://modelo ou nome simples")

    if source_type == "huggingface":
        m = HF_URI_RE.match(uri)
        if m:
            return f"hf://{m.group('repo')}"
        m = HF_URL_RE.match(uri)
        if m:
            return f"hf://{m.group('repo')}"
        if urlparse(uri).scheme in ("http", "https"):
            parsed = urlparse(uri)
            if parsed.hostname not in ALLOWED_HOSTS:
                raise SourceValidationError(f"domínio não permitido: {parsed.hostname}")
            if parsed.hostname and _is_private_ip(parsed.hostname):
                raise SourceValidationError("IP privado não permitido")
            return uri
        if re.match(r"^[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+$", uri):
            return f"hf://{uri}"
        raise SourceValidationError("URI HuggingFace inválida")

    if source_type == "other":
        parsed = urlparse(uri)
        if parsed.scheme in ("http", "https"):
            if parsed.hostname in ALLOWED_HOSTS:
                return uri
            if parsed.hostname and _is_private_ip(parsed.hostname):
                raise SourceValidationError("IP privado não permitido")
            raise SourceValidationError("domínio não está na allowlist")
        raise SourceValidationError("source_type=other requer http(s) com domínio allowlisted")

    raise SourceValidationError(f"source_type desconhecido: {source_type}")


def parse_ollama_model(normalized_uri: str) -> str:
    if normalized_uri.startswith("ollama://"):
        return normalized_uri[len("ollama://") :]
    return normalized_uri


def parse_hf_repo(normalized_uri: str) -> str:
    if normalized_uri.startswith("hf://"):
        return normalized_uri[len("hf://") :]
    m = HF_URL_RE.match(normalized_uri)
    if m:
        return m.group("repo")
    return normalized_uri
