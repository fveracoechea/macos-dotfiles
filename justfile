set shell := ["bash", "-euo", "pipefail", "-c"]

# The zsh config sets these too. A first `just install` runs in a shell that
# started before stow, and Bun puts global packages under XDG_CACHE_HOME
# when BUN_INSTALL is not set.
export XDG_CONFIG_HOME := env("XDG_CONFIG_HOME", home_directory() / ".config")
export BUN_INSTALL := env("BUN_INSTALL", home_directory() / ".bun")

# Operator ships the CLI, the skills, and the global agent instructions.
# Upgrade this pin on a schedule.
operator_version := "2.3.2"
operator_release := "https://jsr.io/@fveracoechea/operator/" + operator_version

# OpenCode modes can advance without upgrading the Operator CLI or device state.
operator_agents_revision := "4377970223c5261ced50ced88125cb90efb61baa"

# The gh stack extension and its agent skill come from this release.
gh_stack_version := "v0.2.1"

# Shared Lua configuration and plugin lockfile, updated together.
neovim_revision := "54d70b33bde49dfe962ac1f89167cce868aa16a4"

# List the recipes.
default:
    @just --list

# Install the software, link the config into ~, and run the one-time setup.
install: brew stow bun-globals setup

brew:
    brew bundle --file=Brewfile

# Upgrade every Brewfile package. Casks that update themselves are skipped.
# Then reinstall the skills, so the herdr skill matches the new herdr.
upgrade: && skills
    brew update
    brew bundle --file=Brewfile
    brew cleanup

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
setup: hunk-gh gh-stack skills operator agents claude-mcp neovim
    # The Ghostty syntax ships inside Ghostty.app. Stow refuses absolute links.
    ln -sf /Applications/Ghostty.app/Contents/Resources/bat/syntaxes/ghostty.sublime-syntax ~/.config/bat/syntaxes/
    bat cache --build
    # cli.json already registers ./herdr-opencode, so the installer writes only its own files.
    herdr integration install opencode
    # settings.json already has the herdr hook, so the installer writes only the hook script.
    herdr integration install claude
    ya pkg install
    # Without a UI, the config waits until every plugin and parser is installed.
    nvim --headless +qa
    brew services start borders
    open -a AeroSpace

# A pinned checkout stays outside Stow ownership and refuses local edits.
_neovim-source:
    #!/usr/bin/env bash
    set -euo pipefail
    dir="${XDG_DATA_HOME:-$HOME/.local/share}/neovim-config"
    url=https://github.com/fveracoechea/neovim.git
    if [[ ! -d $dir/.git ]]; then
      [[ ! -e $dir ]] || { printf 'Neovim checkout path already exists: %s\n' "$dir" >&2; exit 1; }
      mkdir -p "$(dirname "$dir")"
      git clone --quiet "$url" "$dir"
    fi
    [[ $(git -C "$dir" remote get-url origin) == "$url" ]] || { printf 'Unexpected Neovim checkout origin\n' >&2; exit 1; }
    [[ -z $(git -C "$dir" status --porcelain) ]] || { printf 'Neovim checkout has local changes: %s\n' "$dir" >&2; exit 1; }
    if [[ $(git -C "$dir" rev-parse HEAD) != "{{ neovim_revision }}" ]]; then
      git -C "$dir" fetch --quiet origin "{{ neovim_revision }}"
      git -C "$dir" checkout --quiet --detach "{{ neovim_revision }}"
    fi

# Install the shared configuration without Nix or directory folding.
neovim: _neovim-source
    bash "${XDG_DATA_HOME:-$HOME/.local/share}/neovim-config/scripts/install.sh"

# Add missing user-wide MCP servers without replacing existing entries.
claude-mcp:
    claude mcp get datadog >/dev/null 2>&1 || claude mcp add --transport http --scope user datadog 'https://mcp.datadoghq.com/v1/mcp?toolsets=all'
    claude mcp get posthog >/dev/null 2>&1 || claude mcp add --transport http --scope user posthog https://mcp.posthog.com/mcp

# Hunk's own extension for `hunk gh`, at a pinned commit.
hunk-gh:
    #!/usr/bin/env bash
    set -euo pipefail
    dir="$HOME/.local/share/hunk-gh"
    [[ -d $dir/.git ]] || git clone --quiet https://github.com/modem-dev/hunk-gh "$dir"
    git -C "$dir" fetch --quiet origin
    git -C "$dir" checkout --quiet --detach bdf6f9613f575b286d3af6edafc733249e933ddf

# The gh stack extension at the pinned release.
gh-stack:
    #!/usr/bin/env bash
    set -euo pipefail
    installed="$(gh extension list | awk -F'\t' '$2 == "github/gh-stack" {print $3}')"
    if [[ $installed != "{{ gh_stack_version }}" ]]; then
      [[ -z $installed ]] || gh extension remove stack
      gh extension install github/gh-stack --pin "{{ gh_stack_version }}"
    fi

# Agent skills for Claude Code and OpenCode. Operator installs its own skills.
skills:
    bunx skills add -g modem-dev/hunk --skill hunk-review -a claude-code -a opencode -y
    # The skill matches the pinned gh stack extension.
    bunx skills add -g "github/gh-stack#{{ gh_stack_version }}" --skill gh-stack -a claude-code -a opencode -y
    # herdr prints its skill and does not install it.
    mkdir -p "$HOME/.claude/skills/herdr" "$XDG_CONFIG_HOME/opencode/skills/herdr"
    herdr --skill >"$HOME/.claude/skills/herdr/SKILL.md"
    herdr --skill >"$XDG_CONFIG_HOME/opencode/skills/herdr/SKILL.md"

# Operator at the pinned release, with its skills and its Herdr plugin.
operator:
    #!/usr/bin/env bash
    set -euo pipefail
    # .config/.bunfig.toml maps the @jsr scope to the JSR registry.
    bun add -g --exact "@fveracoechea/operator@npm:@jsr/fveracoechea__operator@{{ operator_version }}"
    cli="$(bun pm ls -g | head -n 1 | sed 's/ node_modules (.*//')/node_modules/@fveracoechea/operator/cli.js"
    # Every Operator command refuses until a project is registered. This checkout is the first one.
    bun "$cli" project register --json >/dev/null
    bun "$cli" install launcher --json >/dev/null
    operator="$(bun pm bin -g)/operator"
    # This also installs the upstream skills that operator ready requires.
    "$operator" install --opencode --claude --json >/dev/null
    "$operator" herdr install --json >/dev/null
    plan="$("$operator" config plan --set superAgent.host=opencode --json)"
    if [[ "$(jq -r .data.changed <<<"$plan")" == true ]]; then
      "$operator" config apply --set superAgent.host=opencode --plan "$(jq -r .data.planId <<<"$plan")" --json >/dev/null
    fi

# Global instructions from the release, plus independently pinned OpenCode modes.
agents:
    #!/usr/bin/env bash
    set -euo pipefail
    commit="$(curl -fsSL "{{ operator_release }}/release.json" | jq -er .commit)"
    agents="$(curl -fsSL "https://raw.githubusercontent.com/fveracoechea/operator/$commit/agents/AGENTS.md")"
    # OpenCode and Claude Code read the same instructions.
    for file in "$XDG_CONFIG_HOME/opencode/AGENTS.md" "$HOME/.claude/CLAUDE.md"; do
      mkdir -p "$(dirname "$file")"
      tmp="$(mktemp "$file.XXXXXX")"
      printf '%s\n' "$agents" >"$tmp"
      chmod 644 "$tmp"
      # mv replaces an old link. A write through the link would change its target.
      mv -f "$tmp" "$file"
    done
    just opencode-agents

# Operator owns the shared mode prompts and permissions. Stow owns only model overrides.
opencode-agents:
    #!/usr/bin/env bash
    set -euo pipefail
    directory="$XDG_CONFIG_HOME/opencode/agents"
    mkdir -p "$directory"
    for name in super worker; do
      file="$directory/$name.md"
      tmp="$(mktemp "$file.XXXXXX")"
      trap 'rm -f "$tmp"' EXIT
      curl -fsSL "https://raw.githubusercontent.com/fveracoechea/operator/{{ operator_agents_revision }}/agents/opencode/$name.md" >"$tmp"
      chmod 644 "$tmp"
      mv -f "$tmp" "$file"
    done

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
check: check-stow check-ssh check-agents check-shell check-neovim check-opencode

# Stow into an empty home. This catches conflicts, and repo-only files
# that .stow-local-ignore misses.
check-stow:
    #!/usr/bin/env bash
    set -euo pipefail
    home="$(mktemp -d)"
    trap 'rm -rf "$home"' EXIT
    stow --target="$home" .
    allowed=" .claude .config .ssh .zshenv bin "
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

# Operator owns the global instructions and opinions. Only the root AGENTS.md
# is repo-specific. Each skill that the pinned instructions load must be installed.
check-agents:
    #!/usr/bin/env bash
    set -euo pipefail
    status=0
    copies="$(git ls-files -- '*AGENTS.md' '*CLAUDE.md' '*OPINIONS.md' ':(top,exclude)AGENTS.md')"
    if [[ -n $copies ]]; then
      echo "error: only the root AGENTS.md is repo-specific. Edit global instructions in Operator and remove:" >&2
      echo "$copies" >&2
      status=1
    fi
    commit="$(curl -fsSL "{{ operator_release }}/release.json" | jq -er .commit)"
    agents="$(curl -fsSL "https://raw.githubusercontent.com/fveracoechea/operator/$commit/agents/AGENTS.md")"
    named="$(grep -o 'the `[a-z-]*` skill' <<<"$agents" | cut -d'`' -f2)"
    if [[ -z $named ]]; then
      echo "error: the pinned AGENTS.md names no skill. Update this check." >&2
      status=1
    fi
    # just skills names each skill with --skill or writes it to skills/<name>/SKILL.md.
    # just operator installs each skill in the release.
    release="$(curl -fsSL "{{ operator_release }}_meta.json" | jq -r '.manifest | keys[]' | sed -nE 's#^/skills/([^/]+)/SKILL\.md$#\1#p')"
    recipe="$(just --show skills | grep -oE -- '--skill [a-z-]+|/skills/[a-z-]+/SKILL\.md' | sed -E 's#^--skill ##; s#^/skills/##; s#/SKILL\.md$##')"
    installed=" $recipe $release "
    installed="$(tr '\n' ' ' <<<"$installed")"
    for name in $named; do
      if [[ $installed != *" $name "* ]]; then
        echo "error: the pinned AGENTS.md loads the $name skill, and no recipe installs it." >&2
        status=1
      fi
    done
    exit "$status"

check-shell:
    shellcheck macos/*.sh .config/borders/bordersrc

# Exercise the actual consumer recipe and shared assertions in an empty home.
check-neovim:
    #!/usr/bin/env bash
    set -euo pipefail
    home="$(mktemp -d)"
    trap 'rm -rf "$home"' EXIT
    isolated=(env -i PATH="$PATH" HOME="$home" BUN_INSTALL="$BUN_INSTALL"
      XDG_CONFIG_HOME="$home/.config" XDG_DATA_HOME="$home/.local/share"
      XDG_STATE_HOME="$home/.local/state" XDG_CACHE_HOME="$home/.cache")
    "${isolated[@]}" just neovim
    "${isolated[@]}" just neovim
    source="$home/.local/share/neovim-config"
    "${isolated[@]}" just --justfile "$source/justfile" check
    "${isolated[@]}" bash "$source/tests/start.sh"

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
    # check-jsonschema never refreshes a cached schema, so new settings would fail.
    for file in .config/opencode/opencode.json .config/opencode/cli.json; do
      check-jsonschema --no-cache --schemafile "$(jq -r '.["$schema"]' "$file")" "$file"
    done
    home="$(mktemp -d)"
    trap 'rm -rf "$home"' EXIT
    stow --target="$home" .
    isolated=(env -i PATH="$PATH" HOME="$home" XDG_CONFIG_HOME="$home/.config"
      XDG_STATE_HOME="$home/.local/state" XDG_DATA_HOME="$home/.local/share" XDG_CACHE_HOME="$home/.cache")
    "${isolated[@]}" just opencode-agents
    "${isolated[@]}" just opencode-agents
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
      | .model == {providerID: "claude-agent", model: "opus"}
        and .agents.build.model == {providerID: "claude-agent", model: "opus", variant: "high"}
        and .agents.super == {model: {providerID: "claude-agent", model: "opus", variant: "high"}}
        and .agents.worker == {model: {providerID: "claude-agent", model: "opus", variant: "high"}}
        and (.default_agent // "build") == "build"
        and .providers["claude-agent"].models.opus.settings.effort == "high"
        and .providers.openai.models["gpt-6.1-sol"].variants[0].id == "high"
        and .providers.openai.settings.compaction == {type: "native"}
        and .compaction == {buffer: "25%", keep: {tokens: 25000}}
        and .formatter == true
        and .permissions == [{action: "*", resource: "*", effect: "allow"}]
        and .websearch.provider == "exa"
    ' <<<"$loaded" >/dev/null; then
      echo "error: OpenCode did not load the expected settings from opencode.json." >&2
      status=1
    fi
    agents="$(cd "$home" && "${isolated[@]}" opencode debug agents --standalone --print-logs 2>"$log")"
    if grep -E 'level=(WARN|ERROR|FATAL)' "$log" >&2; then
      echo "error: OpenCode warned when it loaded the agent modes." >&2
      status=1
    fi
    if ! jq -e '
      def agent($id): .[] | select(.id == $id);
      def rule($action; $resource; $effect):
        any(.permissions[]; .action == $action and .resource == $resource and .effect == $effect);
      (agent("super")
        | .mode == "primary"
          and .model == {providerID: "claude-agent", id: "opus", variant: "high"}
          and (.system | contains("load the `super-agent` skill"))
          and rule("edit"; "*"; "deny")
          and rule("edit"; "/tmp/operator-plans/*"; "allow")
          and rule("edit"; "/tmp/operator-answers/*"; "allow")
          and rule("question"; "*"; "deny")
          and rule("subagent"; "*"; "deny")
          and (rule("subagent"; "explore"; "allow") | not))
      and (agent("worker")
        | .mode == "primary"
          and .model == {providerID: "claude-agent", id: "opus", variant: "high"}
          and (.system | contains("load the `worker-agent` skill"))
          and rule("question"; "*"; "deny"))
    ' <<<"$agents" >/dev/null; then
      echo "error: OpenCode did not load the expected mode prompts, models, or permissions." >&2
      status=1
    fi
    exit "$status"
