set shell := ["bash", "-euo", "pipefail", "-c"]

# List the recipes.
default:
    @just --list

# Install the software, link the config into ~, and run the one-time setup.
install: brew stow bun-globals setup

brew:
    brew bundle --file=Brewfile

stow:
    stow .

restow:
    stow -R .

unstow:
    stow -D .

# npm-only tools. Pin exact versions and upgrade them on a schedule.
bun-globals:
    bun add -g graphql-language-service-cli@3.5.0 @stylelint/language-server@1.1.1 oxlint@1.88.0

# Setup that reads the stowed config. Each step is safe to run again.
setup: hunk-gh skills
    # The Ghostty syntax ships inside Ghostty.app. Stow refuses absolute links.
    ln -sf /Applications/Ghostty.app/Contents/Resources/bat/syntaxes/ghostty.sublime-syntax ~/.config/bat/syntaxes/
    bat cache --build
    herdr integration install claude
    herdr integration install opencode
    ya pkg install
    "$(brew --prefix)/opt/tpm/share/tpm/bin/install_plugins"
    # Without a UI, the config waits until every plugin and parser is installed.
    nvim --headless +qa
    brew services start borders
    open -a AeroSpace

# Hunk's own extension for `hunk gh`, at a pinned commit.
hunk-gh:
    #!/usr/bin/env bash
    set -euo pipefail
    dir="$HOME/.local/share/hunk-gh"
    [[ -d $dir/.git ]] || git clone --quiet https://github.com/modem-dev/hunk-gh "$dir"
    git -C "$dir" fetch --quiet origin
    git -C "$dir" checkout --quiet --detach bdf6f9613f575b286d3af6edafc733249e933ddf

# Agent skills for Claude Code and OpenCode. herdr installs its own skill.
skills:
    bunx skills add -g anthropics/skills --skill frontend-design -a claude-code -a opencode -y
    bunx skills add -g fveracoechea/operator --skill no-slop --skill pr-review -a claude-code -a opencode -y
    bunx skills add -g modem-dev/hunk --skill hunk-review -a claude-code -a opencode -y

# Theme Spotify. Run it again after each Spotify update.
spotify:
    spicetify config current_theme catppuccin color_scheme mocha inject_css 1 inject_theme_js 1 replace_colors 1 overwrite_assets 1
    spicetify backup apply

# Apply the macOS defaults.
macos:
    macos/defaults.sh

# Set the desktop picture to a file in wallpapers/.
wallpaper file:
    osascript -e 'tell application "System Events" to tell every desktop to set picture to POSIX file "{{ justfile_directory() }}/wallpapers/{{ file }}"'

# Run every repo check. CI runs this same recipe.
check: check-stow check-ssh check-agents check-shell check-lua

# Stow into an empty home. This catches conflicts, and repo-only files
# that .stow-local-ignore misses.
check-stow:
    #!/usr/bin/env bash
    set -euo pipefail
    home="$(mktemp -d)"
    trap 'rm -rf "$home"' EXIT
    stow --target="$home" .
    allowed=" .claude .config .ssh .zshenv OPINIONS.md bin "
    status=0
    for entry in $(ls -A "$home"); do
      if [[ $allowed != *" $entry "* ]]; then
        echo "error: stow linked ~/$entry. Add it to .stow-local-ignore." >&2
        status=1
      fi
    done
    folded="$(find "$home" -type l -exec test -d {} \; -print)"
    if [[ -n $folded ]]; then
      echo "error: stow linked whole directories. Keep --no-folding in .stowrc:" >&2
      echo "$folded" >&2
      status=1
    fi
    exit "$status"

# Only the ssh config is in git. A key must never be committed.
check-ssh:
    #!/usr/bin/env bash
    set -euo pipefail
    extra="$(git ls-files .ssh | grep -vx '.ssh/config' || true)"
    if [[ -n $extra ]]; then
      echo "error: only .ssh/config may be in git. Remove:" >&2
      echo "$extra" >&2
      exit 1
    fi

# Both agents read agents/AGENTS.md. A plain copy would drift.
check-agents:
    #!/usr/bin/env bash
    set -euo pipefail
    target="$(realpath agents/AGENTS.md)"
    status=0
    for link in .claude/CLAUDE.md .config/opencode/AGENTS.md; do
      if [[ ! -L $link || "$(realpath "$link")" != "$target" ]]; then
        echo "error: $link must be a symlink to agents/AGENTS.md." >&2
        status=1
      fi
    done
    exit "$status"

check-shell:
    shellcheck macos/*.sh .config/borders/bordersrc .claude/statusline.sh

check-lua:
    stylua --check .config/nvim
    luacheck .config/nvim
