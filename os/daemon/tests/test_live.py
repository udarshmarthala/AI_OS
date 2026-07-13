"""Live tests against a running Ollama. Run: pytest -m live"""
import os

import pytest

from aios_daemon.agent import SYSTEM_PROMPT
from aios_daemon.ollama import OllamaClient
from aios_daemon.tools import AppLaunch, FileOps, SysInfo, ToolRegistry

MODEL = os.environ.get("AIOS_MODEL", "qwen2.5:7b")

pytestmark = pytest.mark.live


async def test_model_calls_app_launch():
    client = OllamaClient(base_url="http://localhost:11434", model=MODEL)
    if not await client.health():
        pytest.skip("Ollama not running or model not pulled")

    registry = ToolRegistry([AppLaunch(), FileOps(search_root="/tmp"), SysInfo()])

    async def on_token(t):
        pass

    reply = await client.chat(
        [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": "Open the Firefox browser"},
        ],
        tools=registry.specs,
        on_token=on_token,
    )
    calls = reply.get("tool_calls") or []
    assert calls, f"expected a tool call, got content: {reply['content']!r}"
    assert calls[0]["function"]["name"] == "app_launch"
