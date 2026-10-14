# macos-dotfiles

The macOS config for the work MacBook.
A `Brewfile` installs the software, and GNU stow links the config files into `~`.
It replaces the nix-darwin and Home Manager setup in [fveracoechea/dotfiles](https://github.com/fveracoechea/dotfiles).
The migration plan and the cutover steps are in [fveracoechea/dotfiles#47](https://github.com/fveracoechea/dotfiles/issues/47).

## Layout

The repo root mirrors `$HOME`, so `stow .` links everything in one command.
`.stowrc` sets `--target=~` and `--no-folding`.
With `--no-folding`, stow links files, not directories, so apps that write state into their config directory do not write into the repo.
`.stow-local-ignore` keeps the repo-only files out of `~`: `Brewfile`, `justfile`, `agents/`, `macos/`, `wallpapers/`, and the lint configs.

`agents/AGENTS.md` is the one real copy of the global agent instructions.
`.claude/CLAUDE.md` and `.config/opencode/AGENTS.md` are relative symlinks to it.

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

## Manual steps

- Turn on the caps lock rule in Karabiner-Elements > Complex Modifications.
- Set the pointer size to 1.5 in System Settings > Accessibility > Pointer Control. `com.apple.universalaccess` is SIP-protected, so a script cannot write it.
- Keep secrets in `~/.config/zsh/secrets.zsh`. It is not in git.
