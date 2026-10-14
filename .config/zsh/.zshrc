HISTFILE="$ZDOTDIR/.zsh_history"
HISTSIZE=5000
SAVEHIST=5000
setopt HIST_FCNTL_LOCK HIST_IGNORE_ALL_DUPS HIST_IGNORE_DUPS HIST_IGNORE_SPACE SHARE_HISTORY

autoload -U compinit && compinit

# Completion styling
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls --color $realpath'
zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview 'ls --color $realpath'

source "$HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
ZSH_AUTOSUGGEST_STRATEGY=(history)

eval "$(zoxide init zsh)"

source "$HOMEBREW_PREFIX/share/zsh-vi-mode/zsh-vi-mode.plugin.zsh"
# fzf-tab wraps the completion widget, so it loads after compinit.
source "$HOMEBREW_PREFIX/share/fzf-tab/fzf-tab.zsh"

source <(fzf --zsh)

# zsh-vi-mode resets the key bindings when it starts, so bind ^R again after it.
function zvm_after_init() {
  bindkey '^R' fzf-history-widget
}

bindkey '^y' autosuggest-accept

[[ -r "$ZDOTDIR/secrets.zsh" ]] && source "$ZDOTDIR/secrets.zsh"

autoload -U promptinit; promptinit
prompt pure

zstyle :prompt:pure:git:stash show yes
zstyle :prompt:pure:path:separator dim yes

function y() {
  local tmp="$(mktemp -t "yazi-cwd.XXXXX")"
  command yazi "$@" --cwd-file="$tmp"
  if cwd="$(<"$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
    builtin cd -- "$cwd"
  fi
  rm -f -- "$tmp"
}

function lg() {
  export LAZYGIT_NEW_DIR_FILE=~/.lazygit/newdir
  command lazygit "$@"
  if [ -f $LAZYGIT_NEW_DIR_FILE ]; then
    cd "$(cat $LAZYGIT_NEW_DIR_FILE)"
    rm -f $LAZYGIT_NEW_DIR_FILE > /dev/null
  fi
}

# gh keeps its token in the keychain, so `hunk gh` cannot see it.
# The guard keeps the keychain read off the hot `hunk pager` path.
function hunk() {
  if [[ $1 == gh && -z $GH_TOKEN && -z $GITHUB_TOKEN ]]; then
    GH_TOKEN="$(gh auth token 2>/dev/null)" command hunk "$@"
  else
    command hunk "$@"
  fi
}

if [[ -r "$GHOSTTY_RESOURCES_DIR"/shell-integration/zsh/ghostty-integration ]]; then
  source "$GHOSTTY_RESOURCES_DIR"/shell-integration/zsh/ghostty-integration
fi

alias ..='cd ..'
alias c=clear
alias cat=bat
alias cc='claude --dangerously-skip-permissions'
alias cd=z
alias e=exit
alias la='eza -abghHl --no-user --icons'
alias ll='eza -l'
alias lla='eza -la'
alias ls=eza
alias lt='eza --tree'
alias t='tmux new-session -A -s "$(basename "$PWD")"'
alias vi=nvim
alias vim=nvim
alias vimdiff='nvim -d'

# zsh-syntax-highlighting must load last, after every widget exists.
source "$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
ZSH_HIGHLIGHT_HIGHLIGHTERS=(main)
