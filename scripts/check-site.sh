#!/usr/bin/env bash
# Guards the public getwyrd.ai site: the approved copy on index.html is intact,
# the booking links work, every page links only to pages that exist, no page
# carries banned text, a stray contact detail or an unexpected request to another
# host, and nothing but site files is tracked.
#
# Usage: bash scripts/check-site.sh
# Prints PASS, or one "FAIL: <reason>" line per failure and exits 1.

set -u

cd "$(dirname "$0")/.." || exit 1

PAGE=index.html
PAGES=($(git ls-files '*.html')) # the pages that deploy; a page git doesn't track never reaches the site
fails=0

fail() {
  printf 'FAIL: %s\n' "$1"
  fails=$((fails + 1))
}

[ "${#PAGES[@]}" -gt 0 ] || { fail "git tracks no pages"; exit 1; }
for p in "${PAGES[@]}"; do
  [ -f "$p" ] || { fail "$p does not exist"; exit 1; }
done

# --- The approved copy and the markup the page is required to carry ----------

required=(
  "It's a wyrd time to run a business."
  'Your business, woven into one system you can trust.'
  'From one question to a full production system.'
  'Ask your business anything'
  'Full production systems'
  'Two people. You talk to the ones doing the work.'
  "We don't hand you a system and walk away."
  'Sebastopol, California'
  'id="work"'
  'https://getwyrd.ai/og-image.jpg'
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

# --- Every in-page link has a target; no contact detail but the shared inbox ----

for p in "${PAGES[@]}"; do
  for id in $(grep -oE 'href="#[^"]+"' "$p" | sed 's/href="#//;s/"//' | sort -u); do
    grep -qF "id=\"$id\"" "$p" || fail "link to #$id in $p has no target"
  done
done

for page in $(grep -ohE 'href="[^"#:/]+\.html' "${PAGES[@]}" | sed 's/href="//' | sort -u); do
  git ls-files --error-unmatch -- "$page" > /dev/null 2>&1 || fail "a link points to $page, which git does not track, so it would not deploy"
done

if grep -ohE '[[:alnum:]._%+-]+@[[:alnum:].-]+\.[a-z]{2,}' "${PAGES[@]}" | grep -vqx 'info@getwyrd.ai'; then
  fail "an email address other than info@getwyrd.ai is on a page"
fi

if grep -qE '\(?[0-9]{3}\)?[-. ][0-9]{3}[-. ][0-9]{4}' "${PAGES[@]}"; then
  fail "a phone number is on a page"
fi

# --- Booking links and the visible address -----------------------------------

booking='mailto:info@getwyrd.ai?subject=Book%20a%20call'
count=$(grep -oF -- "$booking" "$PAGE" | wc -l | tr -d '[:space:]')
if [ "$count" -lt 2 ]; then
  fail "the booking link appears $count time(s) in $PAGE, expected at least 2"
fi

count=$(grep -oF -- '>info@getwyrd.ai<' "$PAGE" | wc -l | tr -d '[:space:]')
if [ "$count" -lt 1 ]; then
  fail "info@getwyrd.ai is visible text $count time(s) in $PAGE, expected at least 1"
fi

# --- Claims, names and terms the page must never carry -----------------------

# This repo is public, so the one internal handle in the banned list is held as
# hex bytes rather than spelled out here. It still has to be caught in the page.
# The offer is bespoke work: no plugin-era wording, no promised call length, no
# jargon an owner would not know. Example prices are allowed (2026-11-18).
handle=$(printf '\x62\x6f\x6c\x69\x6a\x61\x68')
banned="cowork|always[- ]on|in the background|testimonial|impossible|rhapsody|${handle}|superpowers|hero\.jpg|one inbox|you approve|[0-9]+[- ]minute|twenty minutes|\bMCP\b"

while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  fail "banned text at $hit"
done < <(grep -niE -- "$banned" "${PAGES[@]}" | cut -c1-120)

# --- Requests to other hosts: one font sheet and the one 3D library ----------

fonts='<link rel="stylesheet" href="https://fonts.googleapis.com/css2?'
count=$(grep -cF -- "$fonts" "$PAGE")
if [ "$count" -gt 1 ]; then
  fail "$PAGE loads $count Google Fonts stylesheets, expected at most 1"
fi

three='<script src="https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js"></script>'
count=$(grep -oE -- '<script[^>]* src="http' "$PAGE" | wc -l | tr -d '[:space:]')
if [ "$count" -gt 1 ]; then
  fail "$PAGE loads $count scripts from other hosts, expected only the 3D library"
fi

# Ordinary links out (profiles) are allowed; anything that loads is not.
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  fail "external request at $hit"
done < <(grep -nE -- 'src="http|<link[^>]* href="http' "${PAGES[@]}" | grep -vE '<meta (property|name)="(og|twitter):' | grep -vF -- "$fonts" |
  grep -vF -- '<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>' | grep -vF -- "$three" |
  grep -vF -- '<link rel="canonical" href="https://getwyrd.ai/">' | cut -c1-120)

# --- Only site files are tracked ---------------------------------------------

allowed='.gitignore
.rhapsody/PROMPT.md
CNAME
README.md
bo.jpg
elijah.jpg
green-tech.html
index.html
og-image.jpg
scripts/check-site.sh
team.jpg'

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
