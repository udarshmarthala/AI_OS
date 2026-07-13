import os
from dataclasses import dataclass, field


@dataclass
class Config:
    ollama_url: str = field(default_factory=lambda: os.environ.get("AIOS_OLLAMA_URL", "http://localhost:11434"))
    model: str = field(default_factory=lambda: os.environ.get("AIOS_MODEL", "qwen2.5:7b"))
    port: int = field(default_factory=lambda: int(os.environ.get("AIOS_PORT", "8800")))
    search_root: str = field(default_factory=lambda: os.environ.get("AIOS_SEARCH_ROOT", os.path.expanduser("~")))
