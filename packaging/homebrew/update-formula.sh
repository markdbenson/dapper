#!/bin/sh
# Print the Homebrew formula for a released version, with the checksum of its
# single-file build. Usage: packaging/homebrew/update-formula.sh 1.00
set -e
version="$1"
[ -n "$version" ] || { echo "usage: $0 <version>" >&2; exit 2; }
url="https://github.com/markdbenson/dapper/releases/download/v$version/dapper"
sha=$(curl -fsSL "$url" | shasum -a 256 | cut -d' ' -f1)
sed -e "s|download/v[0-9.]*/dapper|download/v$version/dapper|" \
    -e "s|version \"[0-9.]*\"|version \"$version\"|" \
    -e "s|sha256 \"[^\"]*\"|sha256 \"$sha\"|" \
    "$(dirname "$0")/dapper.rb"
