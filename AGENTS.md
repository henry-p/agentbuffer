# Beads Issue Tracking
# BEGIN BEADS INTEGRATION

This project uses [Beads (bd)](https://github.com/steveyegge/beads) for issue tracking.

## Core Rules
- Track ALL work in bd (never use markdown TODOs or comment-based task lists)
- Use `bd ready` to find available work
- Use `bd create` to track new issues/tasks/bugs
- Use `bd sync` at end of session to sync with git remote
- Git hooks auto-sync on commit/merge

## Quick Reference
```bash
bd prime                              # Load complete workflow context
bd ready                              # Show issues ready to work (no blockers)
bd list --status=open                 # List all open issues
bd create --title="..." --type=task  # Create new issue
bd update <id> --status=in_progress  # Claim work
bd close <id>                         # Mark complete
bd dep add <issue> <depends-on>       # Add dependency (issue depends on depends-on)
bd sync                               # Sync with git remote
```

## Workflow
1. Check for ready work: `bd ready`
2. Claim an issue: `bd update <id> --status=in_progress`
3. Do the work
4. Mark complete: `bd close <id>`
5. Sync: `bd sync` (or let git hooks handle it)

## Context Loading
Run `bd prime` to get complete workflow documentation in AI-optimized format (~1-2k tokens). Running this is MANDATORY.

For detailed docs: see [QUICKSTART.md](https://github.com/steveyegge/beads/blob/main/docs/QUICKSTART.md), and/or run `bd --help`

# END BEADS INTEGRATION

# Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
