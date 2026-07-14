from fastapi.testclient import TestClient

from aios_daemon.server import create_app


class MockLLM:
    def __init__(self, replies, healthy=True):
        self.replies = list(replies)
        self.healthy = healthy

    async def chat(self, messages, tools, on_token):
        reply = self.replies.pop(0)
        if reply.get("content"):
            await on_token(reply["content"])
        return reply

    async def health(self):
        return self.healthy


def test_health_ok():
    app = create_app(llm=MockLLM([], healthy=True))
    client = TestClient(app)
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"ok": True}


def test_health_brain_down():
    app = create_app(llm=MockLLM([], healthy=False))
    client = TestClient(app)
    response = client.get("/health")
    assert response.status_code == 503
    assert response.json() == {"ok": False}


def test_ws_chat_roundtrip():
    llm = MockLLM([{"role": "assistant", "content": "Paris"}])
    app = create_app(llm=llm)
    client = TestClient(app)
    with client.websocket_connect("/ws") as ws:
        ws.send_json({"text": "capital of France?"})
        events = []
        while True:
            event = ws.receive_json()
            events.append(event)
            if event["event"] in ("done", "error"):
                break
    assert events[-1] == {"event": "done", "text": "Paris"}
    assert {"event": "token", "text": "Paris"} in events


def test_ws_rejects_oversized_message():
    llm = MockLLM([{"role": "assistant", "content": "ok"}])
    app = create_app(llm=llm)
    client = TestClient(app)
    with client.websocket_connect("/ws") as ws:
        ws.send_json({"text": "x" * 20001})
        event = ws.receive_json()
        assert event["event"] == "error"
        assert "too long" in event["text"].lower()


def test_ws_survives_non_string_text():
    llm = MockLLM([{"role": "assistant", "content": "Paris"}])
    app = create_app(llm=llm)
    client = TestClient(app)
    with client.websocket_connect("/ws") as ws:
        ws.send_json({"text": 123})
        ws.send_json({"text": "capital of France?"})
        while True:
            event = ws.receive_json()
            if event["event"] in ("done", "error"):
                break
    assert event == {"event": "done", "text": "Paris"}


def test_ws_confirm_gate_deny():
    call = {"function": {"name": "file_ops", "arguments": {"action": "trash", "path": "/etc/passwd"}}}
    llm = MockLLM([
        {"role": "assistant", "content": "", "tool_calls": [call]},
        {"role": "assistant", "content": "Okay, cancelled."},
    ])
    app = create_app(llm=llm)
    client = TestClient(app)
    with client.websocket_connect("/ws") as ws:
        ws.send_json({"text": "trash passwd"})
        events = []
        while True:
            event = ws.receive_json()
            events.append(event)
            if event["event"] == "confirm":
                ws.send_json({"approved": False})
            if event["event"] in ("done", "error"):
                break
    kinds = [e["event"] for e in events]
    assert "confirm" in kinds
    assert events[-1]["event"] == "done"


def test_serves_index():
    app = create_app(llm=MockLLM([]))
    client = TestClient(app)
    response = client.get("/")
    assert response.status_code == 200
    assert "text/html" in response.headers["content-type"]
