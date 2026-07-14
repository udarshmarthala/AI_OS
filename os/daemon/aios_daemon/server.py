from pathlib import Path

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

from .agent import AgentLoop
from .config import Config
from .ollama import OllamaClient
from .tools import AppLaunch, FileOps, SysInfo, ToolRegistry

WEB_DIR = Path(__file__).parent.parent / "web"
MAX_INPUT_CHARS = 20000


def create_app(llm=None, config=None):
    config = config or Config()
    llm = llm or OllamaClient(base_url=config.ollama_url, model=config.model)
    registry = ToolRegistry([AppLaunch(), FileOps(search_root=config.search_root), SysInfo()])

    app = FastAPI()

    @app.get("/health")
    async def health():
        ok = await llm.health()
        return JSONResponse({"ok": ok}, status_code=200 if ok else 503)

    @app.websocket("/ws")
    async def ws_chat(ws: WebSocket):
        await ws.accept()
        loop = AgentLoop(llm=llm, registry=registry)

        async def emit(event):
            await ws.send_json(event)

        async def confirm(prompt):
            await ws.send_json({"event": "confirm", "text": prompt})
            data = await ws.receive_json()
            return data.get("approved") is True

        try:
            while True:
                data = await ws.receive_json()
                text = data.get("text")
                if not isinstance(text, str):
                    continue
                text = text.strip()
                if len(text) > MAX_INPUT_CHARS:
                    await emit({"event": "error", "text": "Message too long."})
                    continue
                if text:
                    await loop.run_turn(text, emit, confirm=confirm)
        except WebSocketDisconnect:
            pass

    app.mount("/", StaticFiles(directory=WEB_DIR, html=True), name="web")
    return app
