# PATH goes here, not in .zshenv: /etc/zprofile runs path_helper, which moves
# every earlier PATH entry behind the system directories.
eval "$(/opt/homebrew/bin/brew shellenv zsh)"

typeset -U path
path=("$HOME/bin" "$HOME/.bun/bin" $path)
