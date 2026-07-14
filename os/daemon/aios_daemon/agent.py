MAX_HOPS = 5

SYSTEM_PROMPT = (
    "You are AIOS, an AI operating system. You control this computer through tools: "
    "app_launch (launch or list installed applications), file_ops (search/open/move/trash files), "
    "and sys_info (time, disk, memory, uptime). Use a tool whenever the user asks to act on "
    "apps, files, or the system. For general questions, answer directly and concisely. "
    "Never claim you performed an action unless a tool result confirms it."
)


class AgentLoop:
    def __init__(self, llm, registry, system_prompt=SYSTEM_PROMPT):
        self.llm = llm
        self.registry = registry
        self.history = [{"role": "system", "content": system_prompt}]

    async def run_turn(self, text, emit, confirm=None):
        self.history.append({"role": "user", "content": text})

        async def on_token(token):
            await emit({"event": "token", "text": token})

        for _ in range(MAX_HOPS):
            try:
                reply = await self.llm.chat(self.history, tools=self.registry.specs, on_token=on_token)
            except Exception as e:
                await emit({"event": "error", "text": f"Brain offline: {e}"})
                return

            self.history.append(reply)
            calls = reply.get("tool_calls")
            if not calls:
                await emit({"event": "done", "text": reply.get("content", "")})
                return

            for call in calls:
                name = call["function"]["name"]
                args = call["function"].get("arguments") or {}
                await emit({"event": "tool", "name": name})
                prompt = self.registry.confirm_prompt(name, args)
                if prompt and confirm is not None and not await confirm(prompt):
                    result = "User declined the action. Do not retry it."
                else:
                    result = await self.registry.execute(name, args)
                self.history.append({"role": "tool", "content": result})

        await emit({"event": "done", "text": "I got stuck in a tool loop and stopped. Try rephrasing."})
