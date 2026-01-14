#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$root_dir"

swift build -c release
install -m 755 ".build/release/ink" "/usr/local/bin/ink"
echo "Installed /usr/local/bin/ink"
