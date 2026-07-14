from aios_daemon.agent import AgentLoop
from aios_daemon.tools import ToolRegistry


class EchoTool:
    spec = {
        "name": "echo",
        "description": "Echoes input",
        "parameters": {"type": "object", "properties": {"text": {"type": "string"}}, "required": ["text"]},
    }

    async def execute(self, args):
        return f"echo: {args.get('text', '')}"


class MockLLM:
    def __init__(self, replies):
        self.replies = list(replies)
        self.received = []

    async def chat(self, messages, tools, on_token):
        self.received.append(list(messages))
        reply = self.replies.pop(0)
        if reply.get("content"):
            await on_token(reply["content"])
        return reply


class Collector:
    def __init__(self):
        self.events = []

    async def __call__(self, event):
        self.events.append(event)


async def test_plain_answer():
    llm = MockLLM([{"role": "assistant", "content": "Paris"}])
    loop = AgentLoop(llm=llm, registry=ToolRegistry([]))
    emit = Collector()
    await loop.run_turn("capital of France?", emit)
    kinds = [e["event"] for e in emit.events]
    assert "token" in kinds
    assert emit.events[-1] == {"event": "done", "text": "Paris"}


async def test_tool_loop_executes_and_feeds_back():
    call = {"function": {"name": "echo", "arguments": {"text": "hi"}}}
    llm = MockLLM([
        {"role": "assistant", "content": "", "tool_calls": [call]},
        {"role": "assistant", "content": "Done: echo: hi"},
    ])
    loop = AgentLoop(llm=llm, registry=ToolRegistry([EchoTool()]))
    emit = Collector()
    await loop.run_turn("say hi", emit)
    assert {"event": "tool", "name": "echo"} in emit.events
    assert emit.events[-1] == {"event": "done", "text": "Done: echo: hi"}
    # second LLM call saw the tool result
    assert any(m["role"] == "tool" and m["content"] == "echo: hi" for m in llm.received[1])


async def test_hop_limit():
    call = {"function": {"name": "echo", "arguments": {"text": "x"}}}
    looping = {"role": "assistant", "content": "", "tool_calls": [call]}
    llm = MockLLM([dict(looping) for _ in range(10)])
    loop = AgentLoop(llm=llm, registry=ToolRegistry([EchoTool()]))
    emit = Collector()
    await loop.run_turn("loop", emit)
    assert len(llm.received) <= 5
    assert emit.events[-1]["event"] == "done"


async def test_llm_error_emits_error_event():
    class FailingLLM:
        async def chat(self, messages, tools, on_token):
            raise ConnectionError("connection refused")

    loop = AgentLoop(llm=FailingLLM(), registry=ToolRegistry([]))
    emit = Collector()
    await loop.run_turn("hello", emit)
    assert emit.events[-1]["event"] == "error"
    assert "connection refused" in emit.events[-1]["text"]


class TrashTool:
    spec = {
        "name": "trash",
        "description": "Trashes a file",
        "parameters": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]},
    }

    def __init__(self):
        self.executed = []

    def confirm_prompt(self, args):
        return f"Trash {args.get('path')}?"

    async def execute(self, args):
        self.executed.append(args)
        return "Trashed"


async def test_destructive_call_declined_skips_execution():
    call = {"function": {"name": "trash", "arguments": {"path": "/home/x/notes.txt"}}}
    llm = MockLLM([
        {"role": "assistant", "content": "", "tool_calls": [call]},
        {"role": "assistant", "content": "Okay, not trashing it."},
    ])
    tool = TrashTool()
    loop = AgentLoop(llm=llm, registry=ToolRegistry([tool]))
    emit = Collector()
    prompts = []

    async def confirm(prompt):
        prompts.append(prompt)
        return False

    await loop.run_turn("trash my notes", emit, confirm=confirm)
    assert prompts == ["Trash /home/x/notes.txt?"]
    assert tool.executed == []
    assert any(m["role"] == "tool" and "declined" in m["content"] for m in llm.received[1])


async def test_destructive_call_approved_executes():
    call = {"function": {"name": "trash", "arguments": {"path": "/home/x/notes.txt"}}}
    llm = MockLLM([
        {"role": "assistant", "content": "", "tool_calls": [call]},
        {"role": "assistant", "content": "Done."},
    ])
    tool = TrashTool()
    loop = AgentLoop(llm=llm, registry=ToolRegistry([tool]))
    emit = Collector()

    async def confirm(prompt):
        return True

    await loop.run_turn("trash my notes", emit, confirm=confirm)
    assert tool.executed == [{"path": "/home/x/notes.txt"}]


async def test_history_persists_across_turns():
    llm = MockLLM([
        {"role": "assistant", "content": "A"},
        {"role": "assistant", "content": "B"},
    ])
    loop = AgentLoop(llm=llm, registry=ToolRegistry([]))
    emit = Collector()
    await loop.run_turn("first", emit)
    await loop.run_turn("second", emit)
    # second call includes: system, first user, first assistant, second user
    assert [m["role"] for m in llm.received[1]] == ["system", "user", "assistant", "user"]
