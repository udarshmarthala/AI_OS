import json

import httpx

from aios_daemon.ollama import OllamaClient


def make_client(ndjson_body, captured):
    def handler(request):
        captured.append(json.loads(request.content))
        return httpx.Response(200, content=ndjson_body.encode())

    transport = httpx.MockTransport(handler)
    http = httpx.AsyncClient(transport=transport, base_url="http://test")
    return OllamaClient(base_url="http://test", model="qwen2.5:7b", http=http)


async def test_streams_tokens_and_content():
    body = (
        '{"message":{"role":"assistant","content":"Hel"},"done":false}\n'
        '{"message":{"role":"assistant","content":"lo"},"done":false}\n'
        '{"message":{"role":"assistant","content":""},"done":true}\n'
    )
    captured, tokens = [], []

    async def on_token(t):
        tokens.append(t)

    client = make_client(body, captured)
    reply = await client.chat([{"role": "user", "content": "hi"}], tools=[], on_token=on_token)
    assert reply["content"] == "Hello"
    assert tokens == ["Hel", "lo"]
    assert reply.get("tool_calls") in (None, [])


async def test_parses_tool_calls():
    body = (
        '{"message":{"role":"assistant","content":"","tool_calls":'
        '[{"function":{"name":"app_launch","arguments":{"name":"Firefox"}}}]},"done":true}\n'
    )
    captured = []

    async def on_token(t):
        pass

    client = make_client(body, captured)
    reply = await client.chat([{"role": "user", "content": "open firefox"}], tools=[], on_token=on_token)
    assert reply["tool_calls"][0]["function"]["name"] == "app_launch"
    assert reply["tool_calls"][0]["function"]["arguments"] == {"name": "Firefox"}


async def test_sends_model_messages_and_tools():
    body = '{"message":{"role":"assistant","content":"ok"},"done":true}\n'
    captured = []

    async def on_token(t):
        pass

    client = make_client(body, captured)
    spec = [{"type": "function", "function": {"name": "echo", "description": "d", "parameters": {}}}]
    await client.chat([{"role": "user", "content": "x"}], tools=spec, on_token=on_token)
    sent = captured[0]
    assert sent["model"] == "qwen2.5:7b"
    assert sent["stream"] is True
    assert sent["tools"] == spec
    assert sent["messages"][-1]["content"] == "x"


async def test_health_true_when_model_present():
    def handler(request):
        return httpx.Response(200, json={"models": [{"name": "qwen2.5:7b"}]})

    http = httpx.AsyncClient(transport=httpx.MockTransport(handler), base_url="http://test")
    client = OllamaClient(base_url="http://test", model="qwen2.5:7b", http=http)
    assert await client.health() is True


async def test_health_false_when_down():
    def handler(request):
        raise httpx.ConnectError("refused")

    http = httpx.AsyncClient(transport=httpx.MockTransport(handler), base_url="http://test")
    client = OllamaClient(base_url="http://test", model="qwen2.5:7b", http=http)
    assert await client.health() is False
