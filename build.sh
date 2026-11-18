#!/bin/bash
set -e
export PATH="$HOME/.local/bin:$PATH"
export JAVA_HOME="$HOME/opt/jdk21"
SDK="$HOME/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.3.0-2026-10-20-95888f262"
cd "$(dirname "$0")"
"$SDK/bin/monkeyc" -f monkey.jungle -d fr165 -o build/fr165.prg \
  -y "$HOME/garmin-dev/keys/developer_key.der" -w -l 2
echo "built: $(pwd)/build/fr165.prg"
