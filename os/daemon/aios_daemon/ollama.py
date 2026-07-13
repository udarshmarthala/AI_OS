import json

import httpx


class OllamaClient:
    def __init__(self, base_url, model, http=None):
        self.model = model
        # Cold model load can take minutes; generous read timeout.
        self.http = http or httpx.AsyncClient(base_url=base_url, timeout=httpx.Timeout(10, read=300))

    async def chat(self, messages, tools, on_token):
        payload = {"model": self.model, "stream": True, "messages": messages}
        if tools:
            payload["tools"] = tools
        content, tool_calls = "", []
        async with self.http.stream("POST", "/api/chat", json=payload) as response:
            if response.status_code != 200:
                await response.aread()
                raise httpx.HTTPStatusError(
                    f"HTTP {response.status_code}",
                    request=response.request,
                    response=response,
                )
            async for line in response.aiter_lines():
                if not line.strip():
                    continue
                chunk = json.loads(line)
                message = chunk.get("message") or {}
                token = message.get("content", "")
                if token:
                    content += token
                    await on_token(token)
                tool_calls.extend(message.get("tool_calls") or [])
                if chunk.get("done"):
                    break
        reply = {"role": "assistant", "content": content}
        if tool_calls:
            reply["tool_calls"] = tool_calls
        return reply

    async def health(self):
        try:
            response = await self.http.get("/api/tags", timeout=2)
        except httpx.HTTPError:
            return False
        if response.status_code != 200:
            return False
        names = [m.get("name", "") for m in response.json().get("models", [])]
        base = self.model.split(":")[0]
        return any(n.startswith(base) for n in names)
