# macos-dotfiles

The macOS config for the work MacBook.
A `Brewfile` installs the software, and GNU stow links the config files into `~`.
It replaces the nix-darwin and Home Manager setup in [fveracoechea/dotfiles](https://github.com/fveracoechea/dotfiles).
The migration plan and the cutover steps are in [fveracoechea/dotfiles#47](https://github.com/fveracoechea/dotfiles/issues/47).

## Layout

The repo root mirrors `$HOME`, so `stow .` links everything in one command.
`.stowrc` sets `--target=~` and `--no-folding`.
With `--no-folding`, stow links files, not directories, so apps that write state into their config directory do not write into the repo.
`.stow-local-ignore` keeps the repo-only files out of `~`: `AGENTS.md`, `Brewfile`, `justfile`, `macos/`, and `wallpapers/`.
It also ignores `.claude/settings.local.json`, because a Claude Code session in this repo writes local settings there.

## Neovim

[fveracoechea/neovim](https://github.com/fveracoechea/neovim) owns the shared Linux/macOS Lua configuration, plugin lockfile, and editor checks.
`neovim_revision` in `justfile` pins one commit.
`just neovim` maintains its checkout under `$XDG_DATA_HOME/neovim-config` and links individual configuration files into `$XDG_CONFIG_HOME/nvim`.
Both variables default to their standard paths under `~`.
Stow no longer owns Neovim files.
The Brewfile and `just bun-globals` supply the external tools; Nix is not needed.

The installer refuses unrelated configuration files and local changes to its managed checkout or plugin lockfile.
Update plugins in a separate shared-repository development checkout, commit its lockfile, then advance `neovim_revision` here.
Sessions and undo files live under Neovim's state directory, not in this repo.
`just check-neovim` exercises the pinned installation recipe twice in an isolated home, then runs shared checks and editor startup assertions.

### Migrating the old Stow installation

Before pulling the migration, run `just unstow` from the old checkout.
This removes the old Neovim links while Stow still knows their source files.
Preserve any plugin lockfile edits and sessions before updating.
Then pull the migration and run `just install`.
The new installer fails safely if old links remain; it does not replace them automatically.

## Operator

[fveracoechea/operator](https://github.com/fveracoechea/operator) owns the global agent instructions, the opinions, and the Operator CLI.
Edit the global instructions and skills in Operator, not here.
The root `AGENTS.md` contains repository-specific quality checks and requires changes to be committed and pushed to `main`.
`operator_version` at the top of the `justfile` pins one Operator release for all of them.

- `just operator` installs the release from JSR and writes the `operator` command to `~/.bun/bin`.
  It installs the Operator skills, `my-opinions` included, for OpenCode in `~/.config/opencode/skills` and for Claude Code in `~/.claude/skills`.
  It also installs Matt Pocock's skills, which `operator ready` requires, and Anthropic's `frontend-design` skill in `~/.agents/skills`.
  Then it links the Operator Herdr plugin and sets OpenCode as the SuperAgent host.
- Every Operator command needs a registered project, so `just operator` registers this checkout.
- `just agents` writes `agents/AGENTS.md` from the commit of the pinned release to `~/.config/opencode/AGENTS.md` and `~/.claude/CLAUDE.md`.
  It also installs Operator's shared `super` and `worker` Markdown modes in `~/.config/opencode/agents/`.
  `operator_agents_revision` pins the modes separately, so a prompt update does not upgrade the CLI or device state.
- `just check-agents` allows the root `AGENTS.md` but rejects other tracked agent-instruction files or copies of Operator's opinions.
  It also fails if the pinned global instructions load a skill that no recipe installs.

`.config/.bunfig.toml` maps the `@jsr` scope to the JSR registry.
Bun reads this file, not `~/.bunfig.toml`, because `.zshenv` sets `XDG_CONFIG_HOME`.
`.zshenv` also sets `BUN_INSTALL` to `~/.bun`. Without it, Bun puts global packages under `XDG_CACHE_HOME`, which is not on `PATH`.

After `gh auth login`, run `operator ready --json` to check the install.
To take a new Operator release, change `operator_version`, run `just check-agents`, and run `just operator agents`.

## OpenCode

Homebrew installs OpenCode v2.
`opencode.json` holds the server settings in the native v2 shape, and `cli.json` holds the terminal client settings.
`just check-opencode` validates both files against the schemas at their `$schema` URLs.
It then loads the stowed config with the installed OpenCode and Herdr in an empty home.
The check fails if OpenCode logs a warning, drops an expected setting, or if Herdr changes `cli.json`.
It also installs the pinned modes twice and checks their loaded prompts, model overrides, and permissions.

Select `super` to supervise Operator work, or `worker` with an absolute Operator brief in the initial prompt.
Both are primary agents because Operator dispatches workers into separate panes.
Each mode loads its matching installed skill before other tool calls.
`opencode.json` keeps only their machine-specific model overrides.
Edit the shared prompts and permissions in Operator's `agents/opencode/`, then advance `operator_agents_revision` here.
Run `just opencode-agents` to update only the modes.

`cli.json` registers `./herdr-opencode`, so `herdr integration install opencode` only writes its own plugin files.
Herdr also writes its v1 plugin files, because `herdr integration status` reads them.
OpenCode v2 does not load `tui.jsonc`, and the v1 server plugin does nothing in v2.

When you change a setting in the OpenCode TUI, OpenCode replaces the `cli.json` link with a file.
Copy the change into the repo, delete `~/.config/opencode/cli.json`, and run `just restow`.

OpenCode v2 keeps the `lsp` settings, but it does not start language servers or expose an LSP tool.
The return of LSP is tracked in [anomalyco/opencode#38528](https://github.com/anomalyco/opencode/issues/38528).
The `lsp` list keeps only `nixd` and `typescript`, the same list as [fveracoechea/dotfiles](https://github.com/fveracoechea/dotfiles).
This Mac has no `nixd`, so that entry stays inactive.
For diagnostics, agents run the project lint and typecheck commands.

### SuperAgent

`opencode.json` defines a `super` primary agent for the Operator SuperAgent role.
Pick it in the TUI. `build` stays the default agent.
Its `system` prompt tells it to load the `super-agent` skill first.
V2 has no other per-agent instruction field, and this one replaces OpenCode's short base prompt for that agent only.

Its permissions keep it to reading, research and supervision:

- `edit` covers `write` and `patch` and is denied, except under `/tmp/operator-plans/`, where it writes the files that Operator commands take with `--file`.
- `question` is denied, so it asks the person in plain text instead of blocking its turn.
- `subagent` allows only `explore`. `general` edits files.
- The shell stays allowed for Operator, Herdr and `gh`, but denies `sleep`, `bun test`, `bun run`, `bun dev`, `bun install`, `npm install`, `npm run`, `pkill`, `gh run rerun`, and `git commit` and `git push` with or without `git -C <path>`.
- Slack tools that change canvases, lists, reactions, uploads, conversations or scheduled messages are denied. `slack_send_message` and `slack_send_message_draft` stay allowed for PR shares.
- PostHog has one `exec` tool for reads and writes, so it stays allowed for research. The Datadog server already refuses writes for this org.

`glow` renders long Markdown answers in a Herdr pane.

## Claude Code

Homebrew installs the `claude-code` cask.
Stow links `settings.json`, `statusline.sh`, and the `lsp` plugin into `~/.claude`.
`settings.json` is a link to the repo file, so a setting that Claude Code writes shows in `git diff`.
`settings.json` already has the herdr `SessionStart` hook, so `herdr integration install claude` only writes its hook script.
The hook command holds the absolute path of `~/.claude/hooks`, so change it if your home directory is different.
The `cc` alias starts Claude Code with `--dangerously-skip-permissions`.

Claude Code loads `~/.claude/skills/lsp` as a plugin, and `.lsp.json` lists its language servers.
For TypeScript it runs `tsc --lsp --stdio`, the server built into TypeScript 7.
`typescript-language-server` needs `tsserver.js`, and TypeScript 7 does not ship it.

## MCP servers

OpenCode connects globally to Slack, Datadog, and PostHog through `.config/opencode/opencode.json`, with Code Mode enabled by default.
`just claude-mcp`, also run by `just setup`, adds missing user-wide Datadog and PostHog servers to Claude Code.
It preserves existing entries and keeps `~/.claude.json`, which also contains machine-local state, out of Git.
Claude Code's Slack connection comes from its enabled Slack plugin.

Both clients use Datadog US1 with `toolsets=all` and the PostHog endpoint `https://mcp.posthog.com/mcp`.
Authenticate separately in each client: `/mcps` in OpenCode, and `/mcp` in a new Claude Code session.
OAuth credentials stay outside the repository.

## Install

```sh
brew bundle --file=Brewfile
stow -n -v .   # preview the links
just install
just macos
```

`just install` runs `brew bundle`, `stow .`, the pinned Bun globals, and the one-time setup.
Each setup step is safe to run again.

## Recipes

| Recipe | What it does |
| --- | --- |
| `just upgrade` | Upgrades the Brewfile packages, then installs the latest hunk, herdr, and gh-stack skills. |
| `just restow` | Links new files and removes stale links. |
| `just unstow` | Removes every link. |
| `just bun-globals` | Installs the npm-only tools at pinned versions. |
| `just operator` | Installs the pinned Operator release, its skills, and its Herdr plugin. |
| `just agents` | Writes the global agent instructions from the pinned Operator release. |
| `just neovim` | Installs the pinned shared Neovim configuration without Nix. |
| `just check-neovim` | Checks the real Neovim installation in an isolated home. |
| `just claude-mcp` | Adds missing user-wide Datadog and PostHog MCP servers to Claude Code. |
| `just spotify` | Applies the spicetify theme. Run it again after each Spotify update. |
| `just wallpaper <file>` | Sets the desktop picture to a file in `wallpapers/`. |
| `just check` | Runs the repo checks. CI runs this same recipe. |

`brew bundle cleanup` runs by hand, not on every install.

## Update

```sh
git pull
just upgrade
just restow
just setup
```

After an OpenCode upgrade, quit every OpenCode process and start OpenCode in a new terminal.
A process that is still running keeps the old config.

## Manual steps

- Turn on the caps lock rule in Karabiner-Elements > Complex Modifications.
- Set the pointer size to 1.5 in System Settings > Accessibility > Pointer Control. `com.apple.universalaccess` is SIP-protected, so a script cannot write it.
- Keep secrets in `~/.config/zsh/secrets.zsh`. It is not in git.
