import asyncio
import os
import shutil
import subprocess
from datetime import datetime
from pathlib import Path

SEARCH_CAP = 20


class ToolRegistry:
    def __init__(self, tools):
        self._tools = {t.spec["name"]: t for t in tools}

    @property
    def specs(self):
        return [{"type": "function", "function": t.spec} for t in self._tools.values()]

    async def execute(self, name, args):
        tool = self._tools.get(name)
        if tool is None:
            return f"Error: unknown tool '{name}'"
        try:
            return await tool.execute(args)
        except Exception as e:  # tool errors feed back to the model as strings
            return f"Error: {e}"

    def confirm_prompt(self, name, args):
        tool = self._tools.get(name)
        if tool is None or not hasattr(tool, "confirm_prompt"):
            return None
        return tool.confirm_prompt(args)


class SysInfo:
    spec = {
        "name": "sys_info",
        "description": "Report system status: current time, free disk space, total memory, uptime.",
        "parameters": {"type": "object", "properties": {}},
    }

    async def execute(self, args):
        disk = shutil.disk_usage("/")
        mem_bytes = os.sysconf("SC_PAGE_SIZE") * os.sysconf("SC_PHYS_PAGES")
        try:
            uptime = f"{float(Path('/proc/uptime').read_text().split()[0]) / 3600:.1f}h"
        except OSError:
            uptime = "n/a"
        return (
            f"time: {datetime.now().isoformat(timespec='seconds')}, "
            f"disk_free: {disk.free // 2**30}GiB of {disk.total // 2**30}GiB, "
            f"memory_total: {mem_bytes // 2**30}GiB, "
            f"uptime: {uptime}"
        )


class FileOps:
    spec = {
        "name": "file_ops",
        "description": (
            "File operations: search files by name substring, open a file, move a file, "
            "or put a file in the Trash. Never permanently deletes."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "action": {"type": "string", "enum": ["search", "open", "move", "trash"]},
                "query": {"type": "string", "description": "Filename substring for search"},
                "path": {"type": "string", "description": "Absolute path for open/move/trash"},
                "destination": {"type": "string", "description": "Absolute destination for move"},
            },
            "required": ["action"],
        },
    }

    def __init__(self, search_root):
        self.search_root = search_root

    def confirm_prompt(self, args):
        action = args.get("action")
        if action == "trash":
            return f"Put {args.get('path')} in the Trash?"
        if action == "move":
            return f"Move {args.get('path')} to {args.get('destination')}?"
        return None

    def _resolve_inside(self, raw):
        # resolve() follows symlinks, so links escaping the root are caught too
        resolved = Path(raw).resolve()
        if not resolved.is_relative_to(Path(self.search_root).resolve()):
            return None
        return resolved

    async def execute(self, args):
        action = args.get("action")
        if not action:
            return "Error: missing 'action'"
        if action == "search":
            query = args.get("query")
            if not query:
                return "Error: search requires 'query'"
            return await asyncio.to_thread(self._search, query)
        if action == "open":
            path = args.get("path")
            if not path:
                return "Error: missing 'path'"
            subprocess.Popen(["xdg-open", path])
            return f"Opened {path}"
        if action == "move":
            path, dest = args.get("path"), args.get("destination")
            if not path or not dest:
                return "Error: move requires 'path' and 'destination'"
            shutil.move(path, dest)
            return f"Moved {path} -> {dest}"
        if action == "trash":
            path = args.get("path")
            if not path:
                return "Error: missing 'path'"
            result = subprocess.run(["gio", "trash", path], capture_output=True)
            if result.returncode != 0:
                return f"Error: {result.stderr.decode().strip() or 'trash failed'}"
            return f"Trashed {path}"
        return f"Error: unknown action '{action}'"

    def _search(self, query):
        q = query.lower()
        hits = []
        for root, dirs, files in os.walk(self.search_root):
            dirs[:] = [d for d in dirs if not d.startswith(".")]
            for f in files:
                if q in f.lower():
                    hits.append(str(Path(root) / f))
                    if len(hits) >= SEARCH_CAP:
                        return "\n".join(hits)
        return "\n".join(hits) if hits else f"No files found for '{query}'"


class AppLaunch:
    spec = {
        "name": "app_launch",
        "description": "Launch an installed application by name, or list installed applications.",
        "parameters": {
            "type": "object",
            "properties": {
                "name": {"type": "string", "description": "Application name, e.g. 'Firefox'"},
                "action": {"type": "string", "enum": ["launch", "list"], "description": "Defaults to launch"},
            },
        },
    }

    DEFAULT_DIRS = ["/usr/share/applications", os.path.expanduser("~/.local/share/applications")]

    def __init__(self, apps_dirs=None):
        self.apps_dirs = apps_dirs or self.DEFAULT_DIRS

    def _installed(self):
        apps = {}  # display name -> desktop id
        for d in self.apps_dirs:
            for entry in sorted(Path(d).glob("*.desktop")) if Path(d).is_dir() else []:
                name = None
                for line in entry.read_text(errors="ignore").splitlines():
                    if line.startswith("Name=") and name is None:
                        name = line[5:].strip()
                if name:
                    apps[name] = entry.stem
        return apps

    async def execute(self, args):
        apps = await asyncio.to_thread(self._installed)
        if args.get("action") == "list":
            return ", ".join(sorted(apps)) or "No applications found"
        name = args.get("name")
        if not name:
            return "Error: missing 'name'"
        wanted = name.lower()
        for display, desktop_id in apps.items():
            if wanted in display.lower():
                subprocess.Popen(["gtk-launch", desktop_id])
                return f"Launched {display}"
        return f"Error: no installed app matches '{name}'"
