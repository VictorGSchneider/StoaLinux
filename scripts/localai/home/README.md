# scripts/localai/home

Symlinks (relative to this checkout at `~/StoaLinux`) to the real LocalAI folders in
`$HOME`. They only record where the originals live; the data itself stays in the home
directory and is never copied into the repository.

| Link | Original | What it holds |
|---|---|---|
| `data` | `~/data` | chats, add-on state (LocalAI refuses to start if this is a symlink) |
| `configuration` | `~/configuration` | LocalAI runtime config |
| `backends` | `~/backends` | downloaded backends (~6 GB: cuda12 llama.cpp + stable-diffusion) |
| `models` | `~/Models` | the GGUFs (`llm/`) and the SDXL checkpoints |

`stoa-localai` runs from `$HOME`, so LocalAI finds `data`, `configuration` and
`backends` there. `~/.local/share/localai/{data,configuration,backends}` are links back to them.
