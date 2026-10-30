# Nix cutover run

This file describes a real run of `~/nix-cutover/cutover.sh`, and what you do before, during, and after it.
The script runs steps 2 to 10 of the cutover in [fveracoechea/dotfiles#47](https://github.com/fveracoechea/dotfiles/issues/47).
The review of the script is in [#1](https://github.com/fveracoechea/macos-dotfiles/issues/1).

## Before the run

1. Start Claude Code with `--setting-sources project,local`, as step 6 shows.
   The user settings in `~/.claude/settings.json` run a status line script and a herdr hook from `/nix/store`.
   While one of them runs, it holds a file open under `/nix`, and step 9 stops.
2. Commit or push all work in your repos.
   After step 5, your git and ssh config are gone until step 6 links the new ones.
3. Open Terminal.app. Do not use Ghostty.
4. Run `brew install --cask claude-code`.
5. Quit every app that runs from Nix: Ghostty, tmux, herdr, Neovim, OpenCode, and all Claude Code sessions.
   AeroSpace and borders can stay. Step 4 stops them.
6. In Terminal.app, run:

   ```sh
   cd ~/Code/macos-dotfiles
   exec env ZDOTDIR=/var/empty SHELL=/bin/zsh /opt/homebrew/bin/claude --setting-sources project,local
   ```

7. Tell the agent to run `~/nix-cutover/cutover.sh ~/Code/macos-dotfiles --dry-run`, and read the output.
   The preflight must pass. If it lists processes, quit them and do the dry run again.
8. Tell the agent to run the script without `--dry-run`.
9. Keep the Mac awake and online. Stay at the Mac, because macOS dialogs ask for your password or Touch ID.

## During the run

**Start.** The script uses the macOS `/bin/bash` and a `PATH` with only Homebrew and the system directories.
It removes the Nix variables from the environment.
It writes the log to `~/nix-cutover/cutover-<time>.log` and the backups to `~/nix-cutover/backup-<time>/`.

**Preflight.** The script checks the clone, Homebrew, the login shell, the `/etc` backups, and the processes that run from `/nix`.
If one check fails, it stops before it changes anything.

**Step 2: install the Homebrew software.** The script runs `brew bundle` from the Brewfile.
This takes a long time. Some casks show a password dialog.

**Step 3: fix Touch ID for sudo.** The script replaces the `/etc/pam.d/sudo_local` link with a root file that loads the Homebrew `pam_reattach`.
Then it tests `sudo`. Use Touch ID or type your password when it asks.
If the test fails, the script puts the old link back and stops.

**Step 4: stop the Home Manager agents.** The script stops AeroSpace and borders and removes their plists.
Your windows stop tiling until step 6.

**Step 5: remove the Home Manager links.** The script saves a list of the links into `/nix/store`, then removes them.
The dry run on Oct 30 found 113.
They include your zsh, Neovim, git, ssh, OpenCode, and Claude Code config, `~/OPINIONS.md`, and the Volta shims.
`~/.config/zsh/secrets.zsh` and `~/.config/zsh/.zsh_history` stay.

**Step 6: stow and run the setup.** The script checks for stow conflicts, then runs `just stow`, `just bun-globals`, and `just setup`.
This step downloads from GitHub and jsr.io.
It installs the Neovim plugins, the tmux plugins, the agent skills, and Operator.
It starts borders and AeroSpace from Homebrew and opens Ghostty.
Do not work in the new Ghostty until the run is done. Stay in the run session.

**Step 7: apply the macOS defaults.** The script runs `just macos`.
The Dock and Finder restart, and the theme, key repeat, and Dock settings change.

**Step 8: remove nix-darwin from `/etc`.** The script puts back the original `/etc/zshrc`, `/etc/zprofile`, `/etc/shells`, `/etc/bashrc`, and `/etc/nix/nix.conf`.
It removes `/etc/zshenv`, the other nix-darwin links (sudoers, ssh, ssl certificate, terminfo), `/etc/profiles`, `/etc/static`, and `/Applications/Nix Apps`.

**Step 9: uninstall Nix.** You cannot undo this step.
The script checks the processes again.
It stops the five `org.nixos` daemons and removes their plists.
It removes `/etc/synthetic.conf` and `/etc/fstab`, deletes the 32 `_nixbld` users and the `nixbld` group, moves your Nix directories into the backup, and removes `/etc/nix`.
Then it checks the processes one more time and deletes the `Nix Store` volume.

**Step 10: clean up.** The script moves `~/Library/Fonts/HomeManager` and `~/.volta` into the backup.
It uninstalls `node@22` and removes the Volta lines from your shell files.

**End.** The script prints the manual steps and "The cutover is done. Reboot now." The exit code is 0.

## If the script stops

The script prints the step, the command, and the exit code.
Fix the cause, then run the script again. Work that is done prints `skip`.
To start at a given step, use `--from <step>`.

A stop before step 9 leaves Nix in place.
Nix still works for the most part, but your config is partly old and partly new.

## After the run

1. Reboot.
2. Turn on the caps lock rule in Karabiner-Elements > Complex Modifications.
3. Give AeroSpace the Accessibility permission in System Settings > Privacy & Security > Accessibility.
4. Set the pointer size to 1.5 in System Settings > Accessibility > Pointer Control.
5. Run `gh auth login`, then `operator ready --json`.
6. Run `brew uninstall --cask claude-code`. The Brewfile does not install Claude Code.
7. Do the Verification list in [fveracoechea/dotfiles#47](https://github.com/fveracoechea/dotfiles/issues/47).
8. When everything works, delete `~/nix-cutover/backup-*` with `sudo rm -rf`. Some backups are root files.

The script does not print items 4 to 6 yet. Its usage text also does not show `--setting-sources project,local`.
