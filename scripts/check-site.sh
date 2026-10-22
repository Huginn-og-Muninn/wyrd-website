#!/usr/bin/env bash
# Guards index.html for the public getwyrd.ai site: the approved copy is intact,
# the booking links work, nothing external is requested, and nothing but site
# files is tracked.
#
# Usage: bash scripts/check-site.sh
# Prints PASS, or one "FAIL: <reason>" line per failure and exits 1.

set -u

cd "$(dirname "$0")/.." || exit 1

PAGE=index.html
fails=0

fail() {
  printf 'FAIL: %s\n' "$1"
  fails=$((fails + 1))
}

if [ ! -f "$PAGE" ]; then
  fail "$PAGE does not exist"
  exit 1
fi

# --- The approved copy and the markup the page is required to carry ----------

required=(
  'Everything coming in, read. The work, already drafted.'
  'We help you hold yours.'
  'Reads all your inbound'
  'Sorts life into spheres'
  'Drafts the work'
  'Waits for your yes'
  'Your morning, in one look'
  'wyrd, set up and looked after'
  'id="what"'
  'color-scheme: light'
  'https://getwyrd.ai/og-image.png'
  'aria-hidden="true"'
)

for needle in "${required[@]}"; do
  grep -qF -- "$needle" "$PAGE" || fail "missing from $PAGE: $needle"
done

# The closing headline may carry its apostrophe raw or as an entity.
if ! grep -qF -- 'Tell us what&#39;s eating your week.' "$PAGE" &&
  ! grep -qF -- "Tell us what's eating your week." "$PAGE"; then
  fail "missing from $PAGE: Tell us what's eating your week."
fi

# --- Booking links and the visible address -----------------------------------

booking='mailto:info@getwyrd.ai?subject=Booking%20a%20call'
count=$(grep -oF -- "$booking" "$PAGE" | wc -l | tr -d '[:space:]')
if [ "$count" -lt 3 ]; then
  fail "the booking link appears $count time(s) in $PAGE, expected at least 3"
fi

count=$(grep -oF -- '>info@getwyrd.ai<' "$PAGE" | wc -l | tr -d '[:space:]')
if [ "$count" -lt 2 ]; then
  fail "info@getwyrd.ai is visible text $count time(s) in $PAGE, expected at least 2"
fi

# --- Claims, names and scripts the page must never carry ---------------------

# This repo is public, so the one internal handle in the banned list is held as
# hex bytes rather than spelled out here. It still has to be caught in the page.
handle=$(printf '\x62\x6f\x6c\x69\x6a\x61\x68')
banned="<script|cowork|always[- ]on|in the background|testimonial|impossible|rhapsody|${handle}|superpowers|hero\.jpg"

while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  fail "banned text in $PAGE, line $hit"
done < <(grep -niE -- "$banned" "$PAGE")

# --- No external requests, bar the link-preview meta tags --------------------

while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  fail "external request in $PAGE, line $hit"
done < <(grep -nE -- 'src="http|href="http' "$PAGE" | grep -vE '<meta (property|name)="(og|twitter):')

# --- Only site files are tracked ---------------------------------------------

allowed='.gitignore
.rhapsody/PROMPT.md
CNAME
README.md
index.html
og-image.png
scripts/check-site.sh'

if ! git ls-files > /dev/null 2>&1; then
  fail "git ls-files failed, so the list of tracked files could not be checked"
fi

while IFS= read -r tracked; do
  [ -n "$tracked" ] || continue
  printf '%s\n' "$allowed" | grep -qFx -- "$tracked" ||
    fail "git tracks a file that does not belong on the site: $tracked"
done < <(git ls-files 2>/dev/null)

if [ "$fails" -gt 0 ]; then
  exit 1
fi

echo PASS
