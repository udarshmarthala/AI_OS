const feed = document.getElementById("feed");
const input = document.getElementById("input");
const banner = document.getElementById("banner");
const spinner = document.getElementById("spinner");
let ws = null;
let currentBubble = null;

function addMsg(cls, text) {
  const div = document.createElement("div");
  div.className = `msg ${cls}`;
  div.textContent = text;
  feed.appendChild(div);
  feed.scrollTop = feed.scrollHeight;
  return div;
}

function setBusy(busy) {
  input.disabled = busy;
  spinner.classList.toggle("hidden", !busy);
  if (!busy) input.focus();
}

function connect() {
  ws = new WebSocket(`ws://${location.host}/ws`);
  ws.onopen = () => banner.classList.add("hidden");
  ws.onclose = () => banner.classList.remove("hidden");
  ws.onmessage = (raw) => {
    const e = JSON.parse(raw.data);
    if (e.event === "token") {
      if (!currentBubble) currentBubble = addMsg("assistant", "");
      currentBubble.textContent += e.text;
      feed.scrollTop = feed.scrollHeight;
    } else if (e.event === "tool") {
      addMsg("status", `▸ ${e.name}`);
    } else if (e.event === "done") {
      if (currentBubble) currentBubble.textContent = e.text;
      else if (e.text) addMsg("assistant", e.text);
      currentBubble = null;
      setBusy(false);
    } else if (e.event === "error") {
      addMsg("error", e.text);
      banner.classList.remove("hidden");
      currentBubble = null;
      setBusy(false);
    }
  };
}

input.addEventListener("keydown", (ev) => {
  if (ev.key !== "Enter") return;
  const text = input.value.trim();
  if (!text || !ws || ws.readyState !== WebSocket.OPEN) return;
  input.value = "";
  addMsg("user", text);
  setBusy(true);
  ws.send(JSON.stringify({ text }));
});

document.getElementById("retry").addEventListener("click", () => {
  fetch("/health").then((r) => { if (r.ok) { banner.classList.add("hidden"); connect(); } });
});

connect();
