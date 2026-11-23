## Container image scan (Trivy), portfolio:1.0

- 0 CRITICAL, 45 HIGH, all in Debian base packages with no fix released yet.
- 45 findings come from 9 distinct CVEs repeated across packages sharing the same library.
- Python dependencies: 0 HIGH or CRITICAL.
- None are reachable in practice: the container runs as a non-root user, with all Linux
  capabilities dropped, no-new-privileges, and a read-only filesystem. systemd, Perl,
  terminal tools and SQLite are not used by the running app.
- Action: rebuild with `--pull --no-cache` when Debian releases fixes, as a new version tag.
- Future improvement: a smaller base image (for example distroless or a minimal image)
  would remove most of these packages entirely.