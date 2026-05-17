#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOTNET_BIN="/opt/homebrew/bin/dotnet"
ASPIRE_BIN="${HOME}/.aspire/bin/aspire"

if [[ ! -x "$DOTNET_BIN" ]]; then
  echo "Missing .NET 10 at $DOTNET_BIN. Install it with: brew install dotnet" >&2
  exit 1
fi

if [[ ! -x "$ASPIRE_BIN" ]]; then
  echo "Missing Aspire CLI at $ASPIRE_BIN. Install it with: curl -sSL https://aspire.dev/install.sh | bash" >&2
  exit 1
fi

export DOTNET_ROOT="$("$DOTNET_BIN" --info | awk -F'[][]' '/DOTNET_ROOT/ { print $2; exit }')"
if [[ -z "${DOTNET_ROOT:-}" ]]; then
  DOTNET_ROOT="/opt/homebrew/Cellar/dotnet/10.0.107/libexec"
fi

export PATH="/opt/homebrew/bin:${HOME}/.aspire/bin:${PATH}"

cd "$ROOT_DIR"

echo "Using dotnet: $("$DOTNET_BIN" --version) from $DOTNET_BIN"
echo "Using aspire: $("$ASPIRE_BIN" --version)"
echo
echo "When Aspire starts, open the Dashboard URL printed below."
echo "Stop it with Ctrl+C in this terminal."
echo

exec "$ASPIRE_BIN" run --project WeatherLiveStream.AppHost/WeatherLiveStream.AppHost.csproj
