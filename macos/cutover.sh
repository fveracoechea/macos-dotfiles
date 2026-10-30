#!/bin/bash
# One-time cutover of the macbook-pro host from Nix to Homebrew and stow.
# It runs steps 2 to 10 of https://github.com/fveracoechea/dotfiles/issues/47
# and stops before the reboot. It lives in ~/nix-cutover, outside both repos.

# A Nix PATH can start this file with the Nix bash. Use the bash from macOS.
[[ $BASH == /bin/bash ]] || exec /bin/bash "$0" "$@"

set -Eeuo pipefail

BREW=/opt/homebrew
# Homebrew and macOS only. Nothing from /nix, /etc/profiles, /run, or ~/.volta.
export PATH="$BREW/bin:$BREW/sbin:/usr/bin:/bin:/usr/sbin:/sbin"

WORK="$HOME/nix-cutover"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG="$WORK/cutover-$STAMP.log"
BACKUP="$WORK/backup-$STAMP"
DONE_DIR="$WORK/done"
ASKPASS="$WORK/askpass"
AGENTS="org.nix-community.home.aerospace org.nix-community.home.jankyborders"
SECRETS="$HOME/.config/zsh/secrets.zsh"
HISTORY="$HOME/.config/zsh/.zsh_history"
# Each line: an /etc file that nix-darwin links, and the file step 8 restores.
ETC_RESTORE="
/etc/zshrc /etc/zshrc.before-nix-darwin
/etc/zprofile /etc/zprofile.before-nix-darwin
/etc/shells /etc/shells.before-nix-darwin
/etc/bashrc /etc/bashrc.backup-before-nix
/etc/nix/nix.conf /etc/nix/nix.conf.before-nix-darwin
"

usage() {
	cat <<EOF
Usage: cutover.sh <path-to-macos-dotfiles> [--dry-run] [--from <step>]

Runs steps 2 to 10 of the cutover in fveracoechea/dotfiles#47, in order.
It stops before the reboot. It does not reboot the Mac.

  --dry-run      Run the preflight checks, then print each step and each
                 command that would change something. Change nothing.
  --from <step>  Start at this step (2 to 10). Use it after a failure.

Each step prints "skip" for work that is already done, so a second run
after a failure is safe.

Log:     $WORK/cutover-<time>.log
Backups: $WORK/backup-<time>/

Start the real run from a session with no Nix process:
  1. Open Terminal.app. Do not use Ghostty.
  2. Run: brew install --cask claude-code
  3. Quit Ghostty, tmux, herdr, Neovim, and every other app from Nix.
  4. In Terminal.app, run:
       exec env ZDOTDIR=/var/empty SHELL=/bin/zsh /opt/homebrew/bin/claude
     exec replaces the login shell, which loaded zsh plugins from
     /nix/store. ZDOTDIR=/var/empty stops the shells of the agent from
     loading them again.
  5. Tell the agent to run this script with its Bash tool. Run it with
     --dry-run first, then without.

sudo shows a macOS password dialog, or asks for Touch ID.
EOF
}

usage_error() {
	printf 'error: %s\n\n' "$1" >&2
	usage >&2
	exit 2
}

REPO=""
DRY_RUN=0
FROM=2
while (($# > 0)); do
	case $1 in
	--dry-run) DRY_RUN=1 ;;
	--from)
		[[ ${2:-} =~ ^([2-9]|10)$ ]] || usage_error "--from needs a step number from 2 to 10."
		FROM=$2
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	-*) usage_error "unknown option: $1" ;;
	*)
		[[ -z $REPO ]] || usage_error "give only one repo path."
		REPO=$1
		;;
	esac
	shift
done
[[ -n $REPO ]] || usage_error "give the path to the macos-dotfiles clone."

mkdir -p "$WORK"
exec > >(tee -a "$LOG") 2>&1

# Remove what the Nix shell setup exported, such as SSL_CERT_FILE, which
# points at a file that step 8 removes.
for name in $(compgen -e); do
	case $name in PATH | HOME | USER | LOGNAME | TERM | TMPDIR | LANG) continue ;; esac
	case ${!name} in
	*/nix/* | */etc/profiles/* | */run/current-system* | */.volta* | /etc/ssl/certs/ca-certificates.crt) unset "$name" ;;
	esac
	case $name in NIX_*) unset "$name" ;; esac
done
export SHELL=/bin/zsh

# sudo has no TTY in the Bash tool of Claude Code. It reads the password
# from this helper, and brew bundle uses the same helper for casks.
cat >"$ASKPASS" <<'ASKPASS_EOF'
#!/bin/bash
# sudo runs this with its prompt as $1 and reads the password from stdout.
exec /usr/bin/osascript - "${1:-Password:}" <<'APPLESCRIPT'
on run argv
	set reply to display dialog ("sudo for the Nix cutover. " & item 1 of argv) with title "Nix cutover" default answer "" with hidden answer with icon caution
	return text returned of reply
end run
APPLESCRIPT
ASKPASS_EOF
chmod 700 "$ASKPASS"
export SUDO_ASKPASS="$ASKPASS"

STEP_NAME="preflight"
DRY_RUN_FAILED=0

# Ends the run with the step, the command, and the exit code.
abort() { # reason [command] [exit code]
	local rc=${3:-1}
	((rc != 0)) || rc=1
	printf '\nerror: %s\n' "$1"
	[[ -z ${2:-} ]] || printf 'command: %s\n' "$2"
	printf 'exit code: %s\n' "$rc"
	printf 'log: %s\n' "$LOG"
	printf 'Fix the cause, then run the script again. Finished work prints skip.\n'
	printf 'The cutover stopped at %s.\n' "$STEP_NAME"
	exit "$rc"
}

# A failed check ends a real run. A dry run reports it and goes on.
stop() { # reason [command] [exit code]
	if ((DRY_RUN)); then
		printf 'dry run: the real run stops here: %s\n' "$1"
		DRY_RUN_FAILED=1
		return 0
	fi
	abort "$@"
}

trap 'rc=$?; abort "a command failed" "$BASH_COMMAND" "$rc"' ERR

# Prints a command that changes the Mac, then runs it. A dry run only prints it.
run() {
	printf '+'
	printf ' %q' "$@"
	printf '\n'
	if ((DRY_RUN)); then return 0; fi
	local rc=0
	"$@" || rc=$?
	((rc == 0)) || abort "a command failed" "$*" "$rc"
}

begin_step() { # number title
	STEP_NAME="step $1 ($2)"
	printf '\n== step %s: %s ==\n' "$1" "$2"
}

skip() {
	printf 'skip: %s\n' "$1"
}

# Steps 6 and 7 run idempotent setup that no cheap check can confirm, so
# they leave a marker when they finish.
step_done() { [[ -f $DONE_DIR/step-$1 ]]; }
mark_done() {
	if ((DRY_RUN)); then return 0; fi
	mkdir -p "$DONE_DIR"
	touch "$DONE_DIR/step-$1"
}

# Copies a path into the backup directory under its absolute path. A link
# is recorded in symlinks.txt, and the content of a linked file is copied.
# A linked directory is a store tree, so only the link is recorded.
backup() {
	local path=$1 dest="$BACKUP$1"
	printf 'backup: %s\n' "$path"
	if ((DRY_RUN)); then return 0; fi
	mkdir -p "$(dirname "$dest")"
	if [[ -L $path ]]; then
		printf '%s -> %s\n' "$path" "$(readlink "$path")" >>"$BACKUP/symlinks.txt"
		if [[ -f $path ]]; then cp -L "$path" "$dest"; fi
	else
		cp -Rp "$path" "$dest"
	fi
}

# For files of the user, the move into the backup directory is the delete.
move_to_backup() {
	if ((!DRY_RUN)); then mkdir -p "$(dirname "$BACKUP$1")"; fi
	run mv "$1" "$BACKUP$1"
}

# Writes text to a file in the work directory, to copy into place with sudo.
work_file() { # name text
	local file="$WORK/$1"
	if ((!DRY_RUN)); then printf '%s\n' "$2" >"$file"; fi
	printf '%s' "$file"
}

agent_pids() {
	launchctl list | awk -v agents="$AGENTS" '
		BEGIN { n = split(agents, list, " "); for (i = 1; i <= n; i++) want[list[i]] = 1 }
		($3 in want) && $1 != "-" { print $1 }'
}

# Prints "pid command path" once for each process with a file open under
# /nix. With "code", only the executable and the loaded libraries count.
nix_open_files() { # code|all
	[[ $(mount) == *" on /nix ("* ]] || return 0
	local cmd=(lsof -nP -F pcfn /nix)
	if [[ $1 == all ]] && ((!DRY_RUN)); then cmd=(sudo -A "${cmd[@]}"); fi
	{ "${cmd[@]}" 2>/dev/null || true; } | awk -v mode="$1" '
		/^p/ { pid = substr($0, 2) }
		/^c/ { command = substr($0, 2) }
		/^f/ { fd = substr($0, 2) }
		# The volume keeps its own Spotlight and fsevents files open.
		/^n\/nix\/\.(fseventsd|Spotlight-V100)/ { next }
		/^n\/nix/ && (mode == "all" || fd == "txt") && !(pid in seen) {
			seen[pid] = 1
			print pid, command, substr($0, 2)
		}'
}

# Lists each process that still uses /nix, and fails if there is one.
# Unmounting the store would fail, or break that process.
check_nix_processes() { # code|all ignore-agents|keep-agents
	local ignore=" " found="" pid rest
	if [[ $2 == ignore-agents ]]; then ignore=" $(agent_pids | tr '\n' ' ') "; fi
	while read -r pid rest; do
		[[ -n $pid ]] || continue
		case $ignore in *" $pid "*) continue ;; esac
		found+="  PID $pid  $rest"$'\n'
	done <<<"$(nix_open_files "$1")"
	if [[ -z $found ]]; then
		printf 'ok: no process uses /nix\n'
		return 0
	fi
	printf 'error: these processes use files under /nix. Quit each one, or run kill <PID>:\n%s' "$found"
	return 1
}

preflight() {
	printf '== preflight ==\n'
	local problems=0 target src shell

	if ((EUID == 0)); then
		printf 'error: run the script as your user, not as root.\n'
		problems=$((problems + 1))
	fi

	if [[ -d $REPO/.git && -f $REPO/Brewfile && -f $REPO/justfile && -f $REPO/.stowrc ]] &&
		grep -q 'macos-dotfiles' "$REPO/.git/config"; then
		REPO="$(cd "$REPO" && pwd -P)"
		printf 'ok: macos-dotfiles clone at %s\n' "$REPO"
	else
		printf 'error: %s is not a clone of macos-dotfiles.\n' "$REPO"
		problems=$((problems + 1))
	fi

	if [[ -x $BREW/bin/brew ]]; then
		printf 'ok: Homebrew at %s\n' "$BREW"
	else
		printf 'error: Homebrew is not installed at %s.\n' "$BREW"
		problems=$((problems + 1))
	fi

	shell="$(dscl . -read "/Users/$(id -un)" UserShell | awk '{print $2}')"
	if [[ $shell == /bin/zsh ]]; then
		printf 'ok: the login shell is /bin/zsh\n'
	else
		printf 'error: the login shell is %s, not /bin/zsh.\n' "$shell"
		problems=$((problems + 1))
	fi

	# Step 8 needs a backup only for a file that is still a nix-darwin link.
	while read -r target src <&3; do
		[[ -n $target && -L $target ]] || continue
		if [[ -f $src ]]; then
			printf 'ok: step 8 can restore %s from %s\n' "$target" "$src"
		else
			printf 'error: %s is missing. Step 8 needs it to restore %s.\n' "$src" "$target"
			problems=$((problems + 1))
		fi
	done 3<<<"$ETC_RESTORE"
	if [[ -L /etc/shells && -f /etc/shells.before-nix-darwin ]] &&
		! grep -qx /bin/zsh /etc/shells.before-nix-darwin; then
		printf 'error: /etc/shells.before-nix-darwin does not list /bin/zsh, the login shell.\n'
		problems=$((problems + 1))
	fi

	# Step 4 stops the two Home Manager agents, so they may still run here.
	if ! check_nix_processes code ignore-agents; then
		problems=$((problems + 1))
	fi

	if ((problems == 0)); then
		printf 'ok: preflight passed\n'
		return 0
	fi
	stop "the preflight found $problems problem(s)."
	if ((DRY_RUN)); then printf 'The steps follow, so you can review them.\n'; fi
}

step_2() {
	begin_step 2 "install the Homebrew software"
	if HOMEBREW_NO_AUTO_UPDATE=1 brew bundle check --file="$REPO/Brewfile" >/dev/null 2>&1; then
		skip "brew bundle check passes"
	else
		run brew bundle --file="$REPO/Brewfile"
	fi
	if ((DRY_RUN)); then return 0; fi
	# Later steps run these from Homebrew, never from Nix.
	local tool
	for tool in stow just bun git nvim tmux herdr hunk; do
		[[ -x $BREW/bin/$tool ]] || stop "$BREW/bin/$tool is missing after brew bundle."
	done
	printf 'check: stow, just, bun, git, nvim, tmux, herdr, and hunk are in %s/bin\n' "$BREW"
}

step_3() {
	begin_step 3 "fix Touch ID for sudo"
	local file=/etc/pam.d/sudo_local reattach="$BREW/lib/pam/pam_reattach.so" want old new
	want="auth       optional       $reattach
auth       sufficient     pam_tid.so"
	if [[ -f $file && ! -L $file && $(stat -f '%Su:%Sg:%Lp' "$file") == root:wheel:444 && $(<"$file") == "$want" ]]; then
		skip "$file is a root file that loads the Homebrew pam_reattach"
		return 0
	fi
	if [[ ! -f $reattach ]]; then
		if ((DRY_RUN && FROM <= 2)); then
			printf 'note: %s is missing now. Step 2 installs it, and the real run checks it here.\n' "$reattach"
		else
			stop "$reattach is missing. Step 2 installs it with brew bundle."
		fi
	fi
	old="$(readlink "$file" || true)"
	backup "$file"
	printf 'new %s:\n%s\n' "$file" "$want"
	new="$(work_file sudo_local "$want")"
	run sudo -A install -o root -g wheel -m 444 "$new" "$file.cutover"
	run sudo -A mv -f "$file.cutover" "$file"
	if ((DRY_RUN)); then return 0; fi
	# -k ignores the cached credentials for this one command only. The cache
	# stays, so the old file can go back if the new one fails.
	printf 'check: sudo with the new %s. Use Touch ID or the password.\n' "$file"
	if sudo -A -k true; then
		printf 'check: sudo works with the new %s\n' "$file"
		return 0
	fi
	printf 'error: sudo failed with the new %s. Restoring the old one.\n' "$file"
	if [[ -n $old ]]; then
		sudo -n ln -sfh "$old" "$file"
	else
		sudo -n cp "$BACKUP$file" "$file"
	fi
	abort "sudo failed with the new $file." "sudo -A -k true"
}

step_4() {
	begin_step 4 "stop the Home Manager agents"
	local label plist
	for label in $AGENTS; do
		if launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1; then
			run launchctl bootout "gui/$(id -u)/$label"
		else
			skip "$label is not loaded"
		fi
		plist="$HOME/Library/LaunchAgents/$label.plist"
		if [[ -e $plist || -L $plist ]]; then
			backup "$plist"
			run rm -f "$plist"
		else
			skip "$plist does not exist"
		fi
	done
}

step_5() {
	begin_step 5 "remove the Home Manager links"
	local links link list="$BACKUP/home-manager-links.txt" kept="" file
	links="$(find "$HOME" -xdev -type l -lname '/nix/store/*' -print 2>/dev/null || true)"
	if [[ -z $links ]]; then
		skip "no link under ~ points into /nix/store"
		return 0
	fi
	printf '%s links under ~ point into /nix/store.\n' "$(wc -l <<<"$links" | tr -d ' ')"
	if ((!DRY_RUN)); then
		mkdir -p "$BACKUP"
		while IFS= read -r link; do
			printf '%s -> %s\n' "$link" "$(readlink "$link")"
		done <<<"$links" >"$list"
		printf 'saved the list: %s\n' "$list"
	fi
	for file in "$SECRETS" "$HISTORY"; do
		if [[ -e $file ]]; then kept+="$file"$'\n'; fi
	done
	while IFS= read -r link <&3; do
		if [[ $link == "$SECRETS" || $link == "$HISTORY" ]]; then
			printf 'keep: %s\n' "$link"
			continue
		fi
		run rm -f "$link"
	done 3<<<"$links"
	while IFS= read -r file; do
		[[ -z $file || -e $file ]] || abort "$file is gone. It must stay."
	done <<<"$kept"
	# The loop above removes it when it is a link. A real directory stays until here.
	link="$HOME/Applications/Home Manager Apps"
	if [[ -e $link && ! -L $link ]]; then
		backup "$link"
		run rm -rf "$link"
	fi
}

step_6() {
	begin_step 6 "stow the new config and run the setup"
	if step_done 6; then
		skip "an earlier run finished this step ($DONE_DIR/step-6)"
		return 0
	fi
	cd "$REPO"
	if ((DRY_RUN)); then
		printf 'check: stow -n -v . (the run stops on a conflict)\n'
	else
		local out rc=0
		printf 'check: stow -n -v .\n'
		out="$(stow -n -v . 2>&1)" || rc=$?
		printf '%s\n' "$out"
		if ((rc != 0)) || grep -qi conflict <<<"$out"; then
			stop "stow reports a conflict. Move each file it names out of ~, then run again." "stow -n -v ." "$rc"
		fi
	fi
	run just stow
	run just bun-globals
	run just setup
	run open /Applications/Ghostty.app
	mark_done 6
}

step_7() {
	begin_step 7 "apply the macOS defaults"
	if step_done 7; then
		skip "an earlier run finished this step ($DONE_DIR/step-7)"
		return 0
	fi
	cd "$REPO"
	run just macos
	mark_done 7
}

step_8() {
	begin_step 8 "remove nix-darwin from /etc"
	local target src link links
	# A dry run that starts at step 3 or before also prints the step 3 fix.
	if [[ $(readlink /etc/pam.d/sudo_local || true) == /etc/static/* ]] && ! ((DRY_RUN && FROM <= 3)); then
		stop "/etc/pam.d/sudo_local still links into /etc/static. Run step 3 first."
	fi
	while read -r target src <&3; do
		[[ -n $target ]] || continue
		if [[ ! -L $target ]]; then
			skip "$target is not a link"
			continue
		fi
		backup "$target"
		run sudo -A cp -p "$src" "$target.cutover"
		run sudo -A mv -f "$target.cutover" "$target"
	done 3<<<"$ETC_RESTORE"

	# macOS ships without /etc/zshenv.
	if [[ -e /etc/zshenv || -L /etc/zshenv ]]; then
		backup /etc/zshenv
		run sudo -A rm -f /etc/zshenv
	else
		skip "/etc/zshenv does not exist"
	fi

	# Every other nix-darwin link, such as /etc/sudoers.d/10-nix-darwin-extra-config.
	# A dangling link there can break sudo once /etc/static is gone.
	links="$(find /etc/ -type l -lname '/etc/static/*' 2>/dev/null || true)"
	if [[ -z $links ]]; then
		skip "no other link under /etc points into /etc/static"
	fi
	while IFS= read -r link <&3; do
		# Step 3 replaces sudo_local, and the code above handles the other files.
		# In a real run they are not links here. In a dry run they still are.
		[[ -n $link && $link != /etc/pam.d/sudo_local && $link != /etc/zshenv ]] || continue
		[[ $ETC_RESTORE != *$'\n'"$link "* ]] || continue
		backup "$link"
		run sudo -A rm -f "$link"
	done 3<<<"$links"
	# rmdir removes only empty directories.
	if [[ -d /etc/profiles/per-user ]]; then run sudo -A rmdir /etc/profiles/per-user; fi
	if [[ -d /etc/profiles ]]; then run sudo -A rmdir /etc/profiles; fi

	if [[ -e /etc/static || -L /etc/static ]]; then
		backup /etc/static
		run sudo -A rm -f /etc/static
	else
		skip "/etc/static does not exist"
	fi

	link="/Applications/Nix Apps"
	if [[ -e $link ]]; then
		printf 'backup: the file list of %s\n' "$link"
		if ((!DRY_RUN)); then
			mkdir -p "$BACKUP"
			ls -laR "$link" >"$BACKUP/nix-apps-files.txt"
		fi
		run sudo -A rm -rf "$link"
	else
		skip "$link does not exist"
	fi
}

# Removes the lines that match a condition from a root file. When only
# comments and blank lines are left, it removes the file.
strip_lines() { # file awk-condition
	local file=$1 drop=$2 rest new
	if [[ ! -f $file ]]; then
		skip "$file does not exist"
		return 0
	fi
	if ! awk "$drop { found = 1 } END { exit !found }" "$file"; then
		skip "$file has no Nix line"
		return 0
	fi
	backup "$file"
	printf 'remove from %s:\n' "$file"
	awk "$drop" "$file" | sed 's/^/  /'
	rest="$(awk "!($drop)" "$file")"
	if [[ -z $(grep -Ev '^[[:space:]]*(#|$)' <<<"$rest" || true) ]]; then
		run sudo -A rm -f "$file"
	else
		new="$(work_file "$(basename "$file")" "$rest")"
		run sudo -A cp "$new" "$file"
	fi
}

# The Nix Store volume, found by name, so it works when /nix is not mounted.
nix_volume() {
	local dev
	dev="$(diskutil list | awk '/APFS Volume Nix Store / { print $NF }')"
	[[ -n $dev ]] || return 0
	[[ $(diskutil info -plist "$dev" | plutil -extract VolumeName raw -o - -) == "Nix Store" ]] || return 0
	printf '%s' "$dev"
}

step_9() {
	begin_step 9 "uninstall Nix"
	local ignore=keep-agents plist label found=0 users user dir dev uuid
	# A dry run comes before step 4, which stops the agents.
	if ((DRY_RUN)); then ignore="ignore-agents"; fi
	check_nix_processes all "$ignore" || stop "a process still uses /nix."

	for plist in /Library/LaunchDaemons/org.nixos.*.plist; do
		[[ -e $plist ]] || continue
		found=1
		label="$(basename "$plist" .plist)"
		if ((DRY_RUN)); then
			printf 'if system/%s is loaded:\n' "$label"
			run sudo -A launchctl bootout "system/$label"
		elif sudo -A launchctl print "system/$label" >/dev/null 2>&1; then
			run sudo -A launchctl bootout "system/$label"
		fi
		backup "$plist"
		run sudo -A rm -f "$plist"
	done
	((found)) || skip "no /Library/LaunchDaemons/org.nixos.* plist"

	# The run line is the one nix-darwin added for /run.
	# shellcheck disable=SC2016 # awk expands the fields, not bash.
	strip_lines /etc/synthetic.conf '$1 == "nix" || ($1 == "run" && $2 == "private/var/run")'
	# Not vifs: the edit must not need an editor.
	# shellcheck disable=SC2016 # awk expands the fields, not bash.
	strip_lines /etc/fstab '$1 !~ /^#/ && $2 == "/nix"'

	users="$(dscl . -list /Users | grep -E '^_nixbld[0-9]+$' || true)"
	if [[ -n $users ]]; then
		# shellcheck disable=SC2086 # One user name per word.
		if ((!DRY_RUN)); then mkdir -p "$BACKUP/dscl"; fi
		for user in $users; do
			printf 'backup: the record of %s\n' "$user"
			if ((!DRY_RUN)); then dscl . -read "/Users/$user" >"$BACKUP/dscl/$user.txt"; fi
			run sudo -A dscl . -delete "/Users/$user"
		done
	else
		skip "no _nixbld user"
	fi
	if dscl . -read /Groups/nixbld >/dev/null 2>&1; then
		printf 'backup: the record of the nixbld group\n'
		if ((!DRY_RUN)); then
			mkdir -p "$BACKUP/dscl"
			dscl . -read /Groups/nixbld >"$BACKUP/dscl/nixbld.txt"
		fi
		run sudo -A dscl . -delete /Groups/nixbld
	else
		skip "no nixbld group"
	fi

	for dir in "$HOME/.nix-profile" "$HOME/.nix-defexpr" "$HOME/.nix-channels" "$HOME/.cache/nix" "$HOME/.local/state/nix"; do
		if [[ -e $dir || -L $dir ]]; then
			move_to_backup "$dir"
		else
			skip "$dir does not exist"
		fi
	done
	# Only root can see into /var/root.
	for dir in /var/root/.nix-profile /var/root/.nix-defexpr /var/root/.nix-channels; do
		if ((DRY_RUN)); then
			printf 'if %s exists:\n' "$dir"
			run sudo -A rm -rf "$dir"
		elif sudo -A test -e "$dir" || sudo -A test -L "$dir"; then
			run sudo -A rm -rf "$dir"
		else
			skip "$dir does not exist"
		fi
	done
	if [[ -e /etc/nix ]]; then
		backup /etc/nix
		run sudo -A rm -rf /etc/nix
	else
		skip "/etc/nix does not exist"
	fi

	dev="$(nix_volume)"
	if [[ -z $dev ]]; then
		skip "no Nix Store volume"
		return 0
	fi
	# Immediately before the delete, because the steps above take time.
	check_nix_processes all "$ignore" || stop "a process still uses /nix."
	uuid="$(diskutil info -plist "$dev" | plutil -extract VolumeUUID raw -o - -)"
	if security find-generic-password -s "$uuid" /Library/Keychains/System.keychain >/dev/null 2>&1; then
		run sudo -A security delete-generic-password -s "$uuid" /Library/Keychains/System.keychain
	else
		skip "no keychain password for the Nix Store volume"
	fi
	run sudo -A diskutil apfs deleteVolume "$dev"
}

step_10() {
	begin_step 10 "clean up"
	local dir file lines new
	for dir in "$HOME/Library/Fonts/HomeManager" "$HOME/.volta"; do
		if [[ -e $dir ]]; then
			move_to_backup "$dir"
		else
			skip "$dir does not exist"
		fi
	done

	if brew list --formula node@22 >/dev/null 2>&1; then
		run brew uninstall node@22
	else
		skip "node@22 is not installed"
	fi

	# secrets.zsh is not in the list. The script does not edit it.
	for file in "$HOME/.zshenv" "$HOME/.zprofile" "$HOME/.zshrc" "$HOME/.zlogin" \
		"$HOME/.bash_profile" "$HOME/.bashrc" "$HOME/.profile" \
		"$HOME/.config/zsh/.zshenv" "$HOME/.config/zsh/.zprofile" "$HOME/.config/zsh/.zshrc" "$HOME/.config/zsh/.zlogin"; do
		[[ -f $file ]] || continue
		lines="$(grep -i volta "$file" || true)"
		if [[ -z $lines ]]; then continue; fi
		if [[ -L $file ]]; then
			printf 'warning: %s links to %s and has Volta lines. Remove them in the repo:\n%s\n' \
				"$file" "$(readlink "$file")" "$lines"
			continue
		fi
		backup "$file"
		printf 'remove from %s:\n%s\n' "$file" "$lines"
		new="$(work_file "$(basename "$file").new" "$(grep -vi volta "$file" || true)")"
		run cp "$new" "$file"
	done
	printf 'check: Volta lines in the shell files are handled\n'
}

finish() {
	STEP_NAME="the end"
	printf '\n== manual steps ==\n'
	printf 'The script cannot do these:\n'
	printf '  1. Reboot the Mac.\n'
	printf '  2. Turn on the caps lock rule in Karabiner-Elements > Complex Modifications.\n'
	printf '  3. Give AeroSpace the Accessibility permission in System Settings > Privacy & Security > Accessibility.\n'
	printf '  4. After the reboot, do the Verification list in fveracoechea/dotfiles#47.\n'
	printf '\nlog: %s\n' "$LOG"
	if [[ -d $BACKUP ]]; then
		printf 'backups: %s\n' "$BACKUP"
		printf 'Delete the backups when the Verification list passes. Some files are root files, so use sudo.\n'
	fi
}

main() {
	if ((DRY_RUN)); then printf 'dry run: nothing on the Mac changes.\n'; fi
	preflight
	if ((FROM > 2)); then printf '\nStart at step %s (--from %s).\n' "$FROM" "$FROM"; fi
	local n
	for n in 2 3 4 5 6 7 8 9 10; do
		if ((n >= FROM)); then "step_$n"; fi
	done
	if ((DRY_RUN && DRY_RUN_FAILED)); then
		STEP_NAME="the dry run"
		printf '\nThe dry run found problems. The real run stops at the first one.\n'
		exit 1
	fi
	finish
	if ((DRY_RUN)); then printf '\nThe dry run is done. Nothing changed.\n'; else printf '\nThe cutover is done. Reboot now.\n'; fi
}

main
