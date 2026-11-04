# Repository instructions

## Quality

1. Read `README.md` before changing the setup.
   Use `justfile` as the source of truth for installation and checks.
2. Inspect `git status` and the existing diff before editing.
   Preserve unrelated changes and keep the work within the request.
3. Keep the repository's `$HOME` layout and Stow behavior intact.
   Add repo-only files to `.stow-local-ignore` so they stay out of the user's home directory.
4. Keep credentials and machine-local state out of Git.
   Use OAuth or environment references for MCP credentials.
5. Verify changed behavior with the affected tool, not only by inspecting its configuration.
   Report authentication or manual setup that remains unverified.
6. Run `just check` and `git diff --check` before committing.
   Fix failing checks and flaky tests before declaring the work complete.

## Instruction ownership

This file contains repository-specific instructions only.
Operator owns the global agent instructions and skills described in `README.md`.
Edit those in Operator rather than copying them here.

## Commit and push

All requested changes must be committed and pushed to `main` after the checks pass.

1. Fetch `origin/main` and incorporate upstream changes before pushing.
   Preserve published history and never force-push `main`.
2. Review the staged diff and show the commit-message draft before committing.
   Commit only files that belong to the task.
3. Push to `origin main` and verify the push succeeded.
   Report the commit hash, checks, and any remaining uncommitted changes.
