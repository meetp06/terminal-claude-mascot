from __future__ import annotations


class ProviderError(Exception):
    """Raised when a provider is unreachable or returns an error. Callers are
    expected to catch this and degrade gracefully (deterministic output)."""
