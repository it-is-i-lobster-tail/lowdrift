#!/usr/bin/env bash
# Fails if the owner's personal information appears in the tracked files or in any
# commit's message, author or committer reachable from HEAD.
#
# The protected words are stored only as SHA-256 hashes so this script does not
# itself contain them. Every word (lowercase letters and digits) is hashed and
# compared. To protect another word, add `printf %s word | sha256sum` below.
# Short words can be recovered from a hash by guessing, so this only keeps them
# out of plain sight; it is not a secret store.
#
# It also rejects home-directory paths (/Users/<name>, /home/<name>) and any
# email address that is not a noreply address.
set -euo pipefail
cd "$(dirname "$0")/.."

blocked_hashes='
1710acac4d03c5f9144ad290695ea9ca4e3fae778dd59b3be01462c5131ff52f
c604dabc9591840978d2585238a908898b22e3337b207dc722ae208eb204c291
4ee55aabedb9ba90cab4e2b5bff0081b6ae0751b631959bf70e756e61fe43299
'

status=0
fail() { echo "personal-info-check: $*" >&2; status=1; }

hash_words() {
    tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '\n' | grep -v '^$' | sort -u |
        while IFS= read -r word; do
            printf '%s %s\n' "$(printf %s "$word" | sha256sum | cut -c1-64)" "$word"
        done
}

check_words() { # $1 = label; text on stdin
    local hits
    hits=$(hash_words | while read -r h w; do
        if grep -qx "$h" <<<"$blocked_hashes"; then echo "$w"; fi
    done)
    if [ -n "$hits" ]; then
        fail "$1 contains a protected word (shown as hash prefixes): $(
            while read -r w; do printf '%s ' "$(printf %s "$w" | sha256sum | cut -c1-12)"; done <<<"$hits")"
    fi
}

# 1. Tracked files (text only).
while IFS= read -r -d '' f; do
    [ -f "$f" ] || continue
    grep -Iq . "$f" 2>/dev/null || continue
    check_words "$f" <"$f"
    check_words "file name $f" <<<"$f"
    if grep -nE '/(Users|home)/[A-Za-z0-9._-]+' "$f" | grep -vE '/home/runner|/home/user/?$' >/dev/null; then
        fail "$f contains a home-directory path"
    fi
done < <(git ls-files -z)

# 2. Commit messages, authors and committers (needs full history in CI).
if git rev-parse --verify -q HEAD >/dev/null; then
    git log --format='%an%n%ae%n%cn%n%ce%n%B' HEAD | check_words "commit history"
    bad_emails=$(git log --format='%ae%n%ce' HEAD | sort -u |
        grep -viE '(noreply\.github\.com|^noreply@github\.com|^noreply@anthropic\.com)$' || true)
    if [ -n "$bad_emails" ]; then
        fail "commits use a non-noreply email address ($(wc -l <<<"$bad_emails") distinct)"
    fi
fi

# 3. Branch name (CI provides it).
for ref in "${GITHUB_HEAD_REF:-}" "${GITHUB_REF_NAME:-}"; do
    [ -n "$ref" ] && check_words "branch name" <<<"$ref"
done

if [ "$status" -eq 0 ]; then echo "personal-info-check: passed"; fi
exit "$status"
