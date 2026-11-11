// Board's landing page: sound after a click, typing along, the typing test and soundscapes.
// Stores nothing and sends nothing. The only requests are this site's own audio files, made after "Turn sound on".

// Words per minute from the correctly typed characters (five characters per word); accuracy from every character
// typed, mistakes that were later fixed included.
export function score(target, typed, inserts, errors, ms) {
  let correct = 0;
  for (let i = 0; i < Math.min(target.length, typed.length); i++) if (typed[i] === target[i]) correct++;
  const minutes = ms / 60000;
  return {
    wpm: minutes > 0 ? Math.round(correct / 5 / minutes) : 0,
    accuracy: inserts > 0 ? Math.round((100 * Math.max(0, inserts - errors)) / inserts) : 100,
  };
}

export const PASSAGES = [
  "Every key you press makes a small sound. Board picks the sound, and your fingers pick the rhythm.",
  "The quick brown fox jumps over the lazy dog, then sits down to write a letter on an old typewriter.",
  "Type a little faster and the keys start to sing. Slow down and you can hear each one land.",
  "Good typing is steady, not rushed. Keep your eyes on the words and let your hands find the keys.",
];

const $ = (selector) => document.querySelector(selector);
const chosen = (name) => document.querySelector(`input[name="${name}"]:checked`);
const filesOf = (input) => (input?.dataset.files ?? "").split(/\s+/).filter(Boolean);

let ctx = null;
let out = null;
let soundOn = false;
let place = null;
let repeating = false;
const buffers = new Map();

function load(url) {
  if (!buffers.has(url)) {
    const pending = fetch(url)
      .then((response) => { if (!response.ok) throw new Error(`${url}: ${response.status}`); return response.arrayBuffer(); })
      .then((bytes) => ctx.decodeAudioData(bytes));
    pending.catch(() => buffers.delete(url));   // a failed file is fetched again next time
    buffers.set(url, pending);
  }
  return buffers.get(url);
}

// One key's sound, slightly varied in pitch and level as Board does.
async function strike() {
  if (!soundOn) return;
  const files = filesOf(chosen("sound"));
  if (!files.length) return;
  let buffer;
  try { buffer = await load(files[Math.floor(Math.random() * files.length)]); }
  catch { $("#sound-status").textContent = "The sound didn't load. Check your connection, then turn sound off and on."; return; }
  const source = ctx.createBufferSource();
  source.buffer = buffer;
  source.playbackRate.value = 0.96 + Math.random() * 0.08;
  const gain = ctx.createGain();
  gain.gain.value = 0.75 + Math.random() * 0.2;
  source.connect(gain).connect(out);
  source.start();
}

function stopPlace() { place?.stop(); place = null; }

async function startPlace() {
  stopPlace();
  const input = chosen("place");
  const status = $("#place-status");
  if (!input) return;
  const url = input.dataset.loop;
  if (!url) { status.textContent = `${input.value}: the recording isn't ready yet. Soundscapes are still being made.`; return; }
  if (!soundOn) { status.textContent = `${input.value} is ready. Turn sound on to hear it.`; return; }
  try {
    const buffer = await load(url);
    if (chosen("place") !== input || !soundOn) return;
    const source = ctx.createBufferSource();
    source.buffer = buffer;
    source.loop = true;
    const gain = ctx.createGain();
    gain.gain.value = 0.35;
    source.connect(gain).connect(out);
    source.start();
    place = source;
    status.textContent = `Playing ${input.value}. Type above to hear your keys over it.`;
  } catch { status.textContent = `${input.value} didn't load. Check your connection and pick it again.`; }
}

function wireSound() {
  const toggle = $("#sound-toggle");
  const status = $("#sound-status");
  // A track plays here when it has data-files; one without would be marked as in the app only.
  document.querySelectorAll('input[name="sound"]').forEach((input) => {
    const ready = filesOf(input).length > 0;
    input.disabled = !ready;
    input.closest(".track").classList.toggle("ready", ready);
    input.closest(".track").querySelector(".state").textContent = ready ? "Plays here" : "In app";
  });
  toggle.addEventListener("click", async () => {
    soundOn = !soundOn;
    toggle.querySelector("span").textContent = soundOn ? "Turn sound off" : "Turn sound on";
    toggle.querySelector("use").setAttribute("href", soundOn ? "#i-sound" : "#i-mute");
    if (!soundOn) { stopPlace(); ctx?.suspend(); status.textContent = "Sound is off."; return; }
    ctx ??= new (window.AudioContext || window.webkitAudioContext)();
    if (!out) { out = ctx.createGain(); out.gain.value = 0.9; out.connect(ctx.destination); }
    await ctx.resume();
    filesOf(chosen("sound")).forEach((url) => load(url).catch(() => {}));
    status.textContent = `Sound is on: ${chosen("sound").value}. Type in the box, or take the typing test below.`;
    startPlace();
  });
  document.querySelectorAll('input[name="sound"]').forEach((input) => input.addEventListener("change", () => {
    if (soundOn) { filesOf(input).forEach((url) => load(url).catch(() => {})); status.textContent = `Sound is on: ${input.value}.`; }
  }));
  document.querySelectorAll('input[name="place"]').forEach((input) => input.addEventListener("change", startPlace));
}

// The drawn keyboard presses the key that was typed: by its code on a hardware keyboard, by its character on a phone.
function wireKeyboard() {
  const press = (key) => {
    if (!key) return;
    key.classList.add("down");
    clearTimeout(key.upTimer);
    key.upTimer = setTimeout(() => key.classList.remove("down"), 130);
  };
  const keyFor = (attribute, value) => document.querySelector(`.kb .key[${attribute}="${CSS.escape(value)}"]`);
  document.querySelectorAll("[data-type-along]").forEach((field) => {
    field.addEventListener("keydown", (event) => { repeating = event.repeat; if (!event.repeat) press(keyFor("data-code", event.code)); });
    field.addEventListener("keyup", () => { repeating = false; });
    field.addEventListener("beforeinput", (event) => {
      if (event.inputType.startsWith("delete")) press(keyFor("data-code", "Backspace"));
      else if (event.data) press(keyFor("data-char", event.data.slice(-1).toLowerCase()));
      if (!repeating) strike();   // a held key plays once, as in Board
    });
  });
}

function wireTest() {
  const passage = $("#passage");
  const input = $("#test-input");
  let index = 0;
  let target = "";
  let started = 0;
  let inserts = 0;
  let errors = 0;

  const draw = () => {
    const typed = input.value;
    passage.replaceChildren(...[...target].map((character, i) => {
      const span = document.createElement("span");
      span.textContent = character;
      if (i < typed.length) span.className = typed[i] === character ? "ok" : "bad";
      else if (i === typed.length) span.className = "at";
      return span;
    }));
    const ms = started ? performance.now() - started : 0;
    const result = score(target, typed, inserts, errors, ms);
    $("#wpm").textContent = result.wpm;
    $("#acc").textContent = `${result.accuracy}%`;
    $("#secs").textContent = `${Math.round(ms / 1000)} s`;
    return result;
  };
  const reset = (next) => {
    if (next) index = (index + 1) % PASSAGES.length;
    target = PASSAGES[index];
    $("#passage-text").textContent = target;
    $("#test-result").textContent = "";
    input.value = "";
    input.readOnly = false;
    started = inserts = errors = 0;
    draw();
  };

  input.addEventListener("keydown", (event) => { if (event.key === "Enter") event.preventDefault(); });
  input.addEventListener("beforeinput", (event) => {
    if (!event.inputType.startsWith("insert")) return;
    const text = event.data ?? event.dataTransfer?.getData("text/plain") ?? "";
    const at = input.selectionStart;
    for (let i = 0; i < text.length; i++) { inserts++; if (text[i] !== target[at + i]) errors++; }
  });
  input.addEventListener("input", () => {
    if (!started && input.value) started = performance.now();
    if (input.value.length > target.length) input.value = input.value.slice(0, target.length);
    const { wpm, accuracy } = draw();
    if (input.value.length === target.length) {
      input.readOnly = true;
      $("#test-result").textContent = `Done: ${wpm} words per minute, ${accuracy}% accuracy. Choose New passage to go again.`;
    }
  });
  passage.addEventListener("click", () => input.focus());
  $("#test-new").addEventListener("click", () => { reset(true); input.focus(); });
  reset(false);
}

// The download link and version come from the one config block in the page's <head>. With no link there yet,
// the buttons keep their placeholder note and their in-page target.
// The link a release config gives, or "" when it has none worth using: it must be a string holding a full
// https address once the spaces around it are trimmed. Anything else (blank, a javascript: or http: address, a
// relative path) leaves the page in its placeholder state. This checks the form only, not that the file exists.
export function releaseLink(release) {
  const text = typeof release?.url === "string" ? release.url.trim() : "";
  if (!text) return "";
  let address;
  try { address = new URL(text); } catch { return ""; }
  return address.protocol === "https:" && address.hostname ? address.href : "";
}

// Reads the config block; a missing or broken one counts as no release.
export function readRelease(root = document) {
  try { return JSON.parse(root.getElementById("release")?.textContent ?? "{}") ?? {}; } catch { return {}; }
}

// Sets every Download button from the config, either way: a usable link switches them on, anything else puts
// the placeholder state back. Returns true when the buttons download.
export function wireRelease(root = document) {
  const release = readRelease(root);
  const link = releaseLink(release);
  const version = link && typeof release.version === "string" ? release.version.trim() : "";
  root.querySelectorAll("[data-download]").forEach((button) => { button.setAttribute("href", link || "#get"); });
  root.querySelectorAll("[data-placeholder]").forEach((note) => { note.hidden = Boolean(link); });
  root.querySelectorAll("[data-version]").forEach((slot) => { slot.textContent = version ? `Version ${version}. ` : ""; slot.hidden = !version; });
  return Boolean(link);
}

wireRelease();
if (document.getElementById("sound-toggle")) {
  wireSound();
  wireKeyboard();
  wireTest();
}
