#!/usr/bin/env bash
set -euo pipefail

# Copy this file, replace SERVER_IP and SSH_KEY, then run it locally.
# Keep the remote services bound to localhost; expose them only through SSH.

SERVER_IP="<SERVER_IP>"
SSH_KEY="${HOME}/.ssh/<SSH_PRIVATE_KEY>"

exec autossh -M 0 -fN -T \
  -i "${SSH_KEY}" \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=30 \
  -o ServerAliveCountMax=3 \
  -L 127.0.0.1:18317:127.0.0.1:8317 \
  -L 127.0.0.1:15173:127.0.0.1:5173 \
  -L 127.0.0.1:1455:127.0.0.1:1455 \
  "ubuntu@${SERVER_IP}"
