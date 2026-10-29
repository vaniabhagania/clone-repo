# Run Dossier on your computer

Three steps. You need [Docker](https://docs.docker.com/desktop/) and about 2 GB of free memory; nothing else.

**1. Install and start Docker.**
Docker Desktop on macOS or Windows, or Docker Engine with the Compose plugin on Linux. On Windows, do the rest in a WSL terminal (for example Ubuntu), and clone the repo inside WSL.

**2. Get the code.**

```bash
git clone https://github.com/vaniabhagania/clone-repo
cd clone-repo
```

**3. Run it.**

```bash
./run.sh
```

The first time, it asks you to choose a sign-in password, downloads Dossier (about 1.7 GB), sets up the database and starts it. When it says it's running, open **http://localhost:3000** and sign in with that password.

Then pick an AI model in **Settings → AI provider** to use the writing features.

## Everyday use

| Command | What it does |
| --- | --- |
| `./run.sh` | Start Dossier (also the way to restart it) |
| `./run.sh stop` | Stop it. Your data is kept. |
| `./run.sh logs` | Follow the app's log, for when something looks wrong |
| `./run.sh password` | Choose a new sign-in password |

Dossier is only reachable from your own computer. Your data lives in Docker volumes, so it survives stopping and restarting.

## Notes

- A file called `.env` is created next to `run.sh` with the secrets Dossier needs. Keep it private; it is never committed to git. Only a hash of your password is stored, not the password.
- On an Apple Silicon Mac the image runs under emulation, so it is slower to start.
- To delete everything, including your data: `docker compose -f compose.production.yml down -v`.
- This repo contains [Dossier](https://github.com/AienTech/dossier), licensed under AGPL-3.0. The full project README is in [README.md](README.md).
