# Security Policy

## Supported versions
Only the latest release (or `main`) receives fixes.

## Reporting a vulnerability
Please do not open a public issue for security problems. Use GitHub's **private vulnerability reporting** ("Security" tab → "Report a vulnerability") on this repository.

Include steps to reproduce, the affected version, and the impact. You can expect an acknowledgement within a few days.

## Scope notes
- Router stores place history **unencrypted** in `~/Library/Application Support/Router/router.sqlite`. This is documented behaviour.
- Router runs a few system commands (`networkQuality`, `route`, `ping`, `curl`). Reports about command injection or unsafe handling of network-supplied data (such as SSIDs) are especially welcome.
