#!/bin/bash
# Retired entrypoint. The historical implementation remains in Git history.
# No arguments or environment variables enable this script.
printf '%s\n' \
  'BLOCKED: legacy deployment/provider setup entrypoint is disabled.' \
  'Use the reviewed candidate -> qualification -> promotion workflow:' \
  '  Candidate: .github/workflows/firebase-release.yml' \
  '  Evidence: .github/workflows/web-release-observe.yml' \
  '  Qualification: .github/workflows/web-release-qualify.yml' \
  '  Promotion: .github/workflows/web-release-promote.yml' \
  'Provider configuration requires a separate reviewed project-specific change; providers remain disabled.' \
  'This entrypoint does not build, authenticate, configure, deploy, or dispatch a workflow.' >&2
exit 1
