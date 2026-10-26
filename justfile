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
    # cli.json already registers ./herdr-opencode, so the installer writes only its own files.
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

# Agent skills for OpenCode. herdr installs its own skill.
skills:
    bunx skills add -g anthropics/skills --skill frontend-design -a opencode -y
    bunx skills add -g fveracoechea/operator --skill no-slop --skill pr-review -a opencode -y
    bunx skills add -g modem-dev/hunk --skill hunk-review -a opencode -y

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
check: check-stow check-ssh check-agents check-shell check-lua check-opencode

# Stow into an empty home. This catches conflicts, and repo-only files
# that .stow-local-ignore misses.
check-stow:
    #!/usr/bin/env bash
    set -euo pipefail
    home="$(mktemp -d)"
    trap 'rm -rf "$home"' EXIT
    stow --target="$home" .
    allowed=" .config .ssh .zshenv OPINIONS.md bin "
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
    if [[ "$(realpath "$home/.config/opencode/AGENTS.md")" != "$(realpath agents/AGENTS.md)" ]]; then
      echo "error: ~/.config/opencode/AGENTS.md does not resolve to agents/AGENTS.md." >&2
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

# OpenCode reads agents/AGENTS.md through a link. A plain copy would drift.
check-agents:
    #!/usr/bin/env bash
    set -euo pipefail
    link=.config/opencode/AGENTS.md
    if [[ ! -L $link || "$(realpath "$link")" != "$(realpath agents/AGENTS.md)" ]]; then
      echo "error: $link must be a symlink to agents/AGENTS.md." >&2
      exit 1
    fi

check-shell:
    shellcheck macos/*.sh .config/borders/bordersrc

check-lua:
    stylua --check .config/nvim
    luacheck .config/nvim

# OpenCode drops a setting it does not know with no warning, so the schemas
# catch typos. Then the installed OpenCode and herdr run against the stowed
# config in an empty home, the way `just install` runs them.
check-opencode:
    #!/usr/bin/env bash
    set -euo pipefail
    version="$(opencode --version)"
    if [[ $version != "opencode v2."* ]]; then
      echo "error: $version is not OpenCode v2. Run brew upgrade opencode." >&2
      exit 1
    fi
    for file in .config/opencode/opencode.json .config/opencode/cli.json; do
      check-jsonschema --schemafile "$(jq -r '.["$schema"]' "$file")" "$file"
    done
    home="$(mktemp -d)"
    trap 'rm -rf "$home"' EXIT
    stow --target="$home" .
    isolated=(env -i PATH="$PATH" HOME="$home" XDG_CONFIG_HOME="$home/.config"
      XDG_STATE_HOME="$home/.local/state" XDG_DATA_HOME="$home/.local/share" XDG_CACHE_HOME="$home/.cache")
    cli="$home/.config/opencode/cli.json"
    before="$(shasum .config/opencode/cli.json)"
    # Twice, because setup must converge when it runs again.
    "${isolated[@]}" herdr integration install opencode >/dev/null
    "${isolated[@]}" herdr integration install opencode >/dev/null
    status=0
    if [[ ! -L $cli ]]; then
      echo "error: herdr replaced the cli.json link with a file." >&2
      status=1
    fi
    if [[ "$(shasum .config/opencode/cli.json)" != "$before" ]]; then
      echo "error: herdr changed .config/opencode/cli.json. Add its change to the repo:" >&2
      git diff -- .config/opencode/cli.json >&2
      status=1
    fi
    if [[ "$(jq '[.plugins[] | select(. == "./herdr-opencode")] | length' "$cli")" != 1 ]]; then
      echo "error: cli.json must register ./herdr-opencode once." >&2
      status=1
    fi
    log="$home/opencode.log"
    loaded="$(cd "$home" && "${isolated[@]}" opencode api --standalone config.get --print-logs 2>"$log")"
    if grep -E 'level=(WARN|ERROR|FATAL)' "$log" >&2; then
      echo "error: OpenCode warned when it loaded opencode.json." >&2
      status=1
    fi
    if ! jq -e '
      [.[] | select(.type == "document") | .info][0]
      | .agents.build.model.variant == "high"
        and .providers.openai.models["gpt-6.1-sol"].variants[0].id == "high"
        and .providers.openrouter.models["z-ai/glm-5.3-flash"].variants[0].id == "high"
        and .permissions == [{action: "*", resource: "*", effect: "allow"}]
        and .providers.openrouter.body.provider == {
          sort: "throughput", only: ["baseten", "novita", "fireworks"],
          allow_fallbacks: true, data_collection: "deny", zdr: true
        }
        and .websearch.provider == "exa"
    ' <<<"$loaded" >/dev/null; then
      echo "error: OpenCode did not load the expected settings from opencode.json." >&2
      status=1
    fi
    exit "$status"
