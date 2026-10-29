# macos-dotfiles

The macOS config for the work MacBook.
A `Brewfile` installs the software, and GNU stow links the config files into `~`.
It replaces the nix-darwin and Home Manager setup in [fveracoechea/dotfiles](https://github.com/fveracoechea/dotfiles).
The migration plan and the cutover steps are in [fveracoechea/dotfiles#47](https://github.com/fveracoechea/dotfiles/issues/47).

## Layout

The repo root mirrors `$HOME`, so `stow .` links everything in one command.
`.stowrc` sets `--target=~` and `--no-folding`.
With `--no-folding`, stow links files, not directories, so apps that write state into their config directory do not write into the repo.
`.stow-local-ignore` keeps the repo-only files out of `~`: `Brewfile`, `justfile`, `macos/`, `wallpapers/`, and the lint configs.
It also ignores `.claude/`, because a Claude Code session in this repo writes local settings there.

## Agent instructions

[fveracoechea/operator](https://github.com/fveracoechea/operator) owns the global agent instructions and the opinions.
Edit them in Operator, not here.

- `just agents` writes `agents/AGENTS.md` from Operator to `~/.config/opencode/AGENTS.md`. It uses the commit in `operator_rev` at the top of the `justfile`.
- `just skills` installs the `my-opinions` skill from Operator. It replaces `~/OPINIONS.md`.
- `just check-agents` fails if the repo has a copy of either file, or if the pinned `AGENTS.md` loads a skill that `just skills` does not install.

To take a new Operator version, change `operator_rev`, run `just check-agents`, and run `just agents`.

## OpenCode

Homebrew installs OpenCode v2.
`opencode.json` holds the server settings in the native v2 shape, and `cli.json` holds the terminal client settings.
`just check-opencode` validates both files against the schemas at their `$schema` URLs.
It then loads the stowed config with the installed OpenCode and Herdr in an empty home.
The check fails if OpenCode logs a warning, drops an expected setting, or if Herdr changes `cli.json`.

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
| `just restow` | Links new files and removes stale links. |
| `just unstow` | Removes every link. |
| `just bun-globals` | Installs the npm-only tools at pinned versions. |
| `just spotify` | Applies the spicetify theme. Run it again after each Spotify update. |
| `just wallpaper <file>` | Sets the desktop picture to a file in `wallpapers/`. |
| `just check` | Runs the repo checks. CI runs this same recipe. |

`brew bundle cleanup` runs by hand, not on every install.

## Update

```sh
git pull
brew update
brew bundle --file=Brewfile
brew upgrade
just restow
just setup
```

After an OpenCode upgrade, quit every OpenCode process and start OpenCode in a new terminal.
A process that is still running keeps the old config.

### Remove Claude Code from an existing install

Do these steps one time, before you pull the commit that removes Claude Code.
They remove only the Claude Code package and the links that this repo made.
Claude Code credentials, history, and the shared skills stay in place.

```sh
herdr integration uninstall claude
git checkout -- .claude/settings.json   # herdr wrote its hook into the tracked file
just unstow                             # while the old tree still lists the ~/.claude links
git pull
just stow
brew uninstall --cask claude-code
nvim --headless '+lua vim.pack.del({ "opencode.nvim" })' +qa
```

Then do the steps in [Update](#update).
`stow` leaves the empty `~/.claude/skills/lsp` directories. Remove them with `find ~/.claude/skills/lsp -type d -empty -delete`.

## Manual steps

- Turn on the caps lock rule in Karabiner-Elements > Complex Modifications.
- Set the pointer size to 1.5 in System Settings > Accessibility > Pointer Control. `com.apple.universalaccess` is SIP-protected, so a script cannot write it.
- Keep secrets in `~/.config/zsh/secrets.zsh`. It is not in git.
