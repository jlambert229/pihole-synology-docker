# Contributing to Pi-hole Synology Docker

First off, thanks for taking the time to contribute! 🎉

## How Can I Contribute?

### Reporting Issues

Found a bug or have a suggestion? Open an issue with:
- Clear title and description
- Steps to reproduce (for bugs)
- Your environment (DSM version, Docker version)
- Expected vs actual behavior

### Suggesting Blocklists

Have a better blocklist recommendation?

**Include:**
- List URL
- Maintainer/source
- Tier (Essential/Recommended/Aggressive)
- Testing you've done (how long, what sites/services)
- Known false positives

### Whitelist Additions

Found a false positive that should be whitelisted?

**Include:**
- Domain name
- What service/site it breaks
- Which blocklist(s) catch it
- Testing confirmation (blocked → whitelisted → works)

### Code Contributions

**Pull requests welcome for:**
- Bug fixes
- Script improvements
- Documentation clarifications
- New features (discuss in an issue first)

**Guidelines:**
- Test your changes on a Synology NAS
- Update README if behavior changes
- Keep commits atomic and well-described
- Follow existing code style (bash best practices)

## Development Setup

1. Fork the repo
2. Create a feature branch: `git checkout -b feature/my-improvement`
3. Test on your Synology (or VM if possible)
4. Commit with clear messages: `git commit -m "fix: resolve DNS timeout issue"`
5. Push and open a PR

## Testing Checklist

Before submitting a PR, verify:

- [ ] Scripts are executable (`chmod +x`)
- [ ] Scripts run without errors
- [ ] README updated if needed
- [ ] No hardcoded credentials/IPs (use placeholders)
- [ ] Tested on actual Synology hardware (or document testing approach)

## Style Guide

**Shell scripts:**
- Use `#!/usr/bin/env bash` (not `#!/bin/bash`)
- Use `set -euo pipefail` for safety
- Quote variables: `"${VAR}"` not `$VAR`
- Comment non-obvious sections
- Use functions for repeated logic

**Documentation:**
- Clear headings and structure
- Examples for complex concepts
- Link to official docs where relevant
- Prefer showing over telling

## Questions?

Open an issue with the `question` label. No question is too small.

---

**Thank you for helping make this project better!**
