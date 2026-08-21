#!/usr/bin/env bash
#
# tmignore.sh - a ".gitignore" for Time Machine.
#
# Walks one or more folders, reports every project it finds grouped by type
# (node, react, flutter, angular, ...), and excludes the rebuildable artifact
# directories (node_modules, .next, .angular, build, Pods, target, ...) from
# Time Machine backups.
#
# Usage:
#   ./tmignore.sh                     scan the current directory
#   ./tmignore.sh ~/Projects          scan one folder
#   ./tmignore.sh ~/Projects ~/Work   scan several
#   ./tmignore.sh -n ~/Projects       dry run - show the list, change nothing
#   ./tmignore.sh -y ~/Projects       apply without the confirmation prompt
#   ./tmignore.sh -r ~/Projects       project inventory only, skip exclusions
#   ./tmignore.sh -s ~/Projects       include size estimates (slower)
#
# Safety: inside a git repo, a directory is only excluded if git itself
# ignores it. A "build/" of committed source is therefore left alone while a
# "build/" of output is excluded. Pass --no-git-check to rely on the built-in
# lists alone.
#
# Nothing is excluded until you confirm: the full list is built and shown
# first, then you approve it at the prompt.
#
# Requires macOS (tmutil) to apply exclusions; --dry-run works anywhere.
# Written for the stock /bin/bash 3.2 that ships with macOS.

set -uo pipefail

VERSION="1.0.0"
MAX_DEPTH=6
DRY_RUN="false"
REPORT_ONLY="false"
SHOW_SIZE="false"
GIT_CHECK="true"
ASSUME_YES="false"
EXTRA_IGNORES=()

# Override to test without touching real Time Machine state.
TMUTIL_BIN="${TMIGNORE_TMUTIL:-tmutil}"

# ---------------------------------------------------------------- appearance

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m';  C_DIM=$'\033[2m';    C_BOLD=$'\033[1m'
  C_RED=$'\033[31m';   C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m';  C_CYAN=$'\033[36m'
else
  C_RESET=""; C_DIM=""; C_BOLD=""
  C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_CYAN=""
fi

say()  { printf '%s\n' "$*"; }
warn() { printf '%s%s%s\n' "${C_YELLOW}" "$*" "${C_RESET}" >&2; }
die()  { printf '%s%s%s\n' "${C_RED}" "$*" "${C_RESET}" >&2; exit 1; }

rule() {
  printf '%s-- %s %s%s\n' "${C_DIM}" "$1" \
    "$(printf '%.0s-' $(seq 1 $(( 56 - ${#1} )) ))" "${C_RESET}"
}

# Shorten $HOME to ~ for display.
tilde() { printf '%s' "${1/#$HOME/\~}"; }

human_bytes() {
  awk -v b="$1" 'BEGIN{
    split("B KB MB GB TB",u); i=1;
    while (b>=1024 && i<5) {b/=1024; i++}
    printf "%.1f %s", b, u[i]
  }'
}

usage() {
  awk 'NR>2 && /^#/ { sub(/^# ?/, ""); print; next } NR>2 { exit }' "$0"
  cat <<'EOF'

Options:
  -n, --dry-run       Report what would be excluded, but change nothing
  -r, --report-only   Only list projects; do not touch Time Machine at all
  -y, --yes           Skip the confirmation prompt and apply straight away
  -s, --size          Show a size estimate per excluded directory (slower)
  -d, --depth N       How deep to search below each folder (default 6)
  -i, --ignore NAME   Never descend into directories with this name (repeatable)
      --no-git-check  Skip the "is it gitignored?" safety check
  -h, --help          Show this help
  -V, --version       Print version
EOF
}

# ------------------------------------------------------------ project types

ALL_TYPES="node react nextjs angular vue svelte nuxt astro react_native flutter android xcode python rust go maven php ruby dotnet"

type_label() {
  case "$1" in
    node)         echo "Node.js" ;;
    react)        echo "React" ;;
    nextjs)       echo "Next.js" ;;
    angular)      echo "Angular" ;;
    vue)          echo "Vue" ;;
    svelte)       echo "Svelte" ;;
    nuxt)         echo "Nuxt" ;;
    astro)        echo "Astro" ;;
    react_native) echo "React Native / Expo" ;;
    flutter)      echo "Flutter / Dart" ;;
    android)      echo "Android / Gradle" ;;
    xcode)        echo "Xcode / iOS" ;;
    python)       echo "Python" ;;
    rust)         echo "Rust" ;;
    go)           echo "Go" ;;
    maven)        echo "Java / Maven" ;;
    php)          echo "PHP / Composer" ;;
    ruby)         echo "Ruby" ;;
    dotnet)       echo ".NET" ;;
    *)            echo "$1" ;;
  esac
}

# Directories each project type generates and can always rebuild.
type_artifacts() {
  case "$1" in
    node) cat <<'EOF'
node_modules
.cache
.turbo
.parcel-cache
.vite
coverage
dist
build
out
EOF
    ;;
    react) cat <<'EOF'
build
EOF
    ;;
    nextjs) cat <<'EOF'
.next
.vercel
out
EOF
    ;;
    angular) cat <<'EOF'
.angular
.nx
dist
coverage
EOF
    ;;
    vue|astro) cat <<'EOF'
dist
.astro
EOF
    ;;
    svelte) cat <<'EOF'
.svelte-kit
build
dist
EOF
    ;;
    nuxt) cat <<'EOF'
.nuxt
.output
dist
EOF
    ;;
    react_native) cat <<'EOF'
.expo
ios/Pods
ios/build
ios/DerivedData
android/build
android/.gradle
android/app/build
EOF
    ;;
    flutter) cat <<'EOF'
.dart_tool
build
ios/Pods
ios/.symlinks
macos/Pods
macos/.symlinks
android/.gradle
android/build
android/app/build
EOF
    ;;
    android) cat <<'EOF'
.gradle
build
app/build
EOF
    ;;
    xcode) cat <<'EOF'
Pods
build
DerivedData
.swiftpm
EOF
    ;;
    python) cat <<'EOF'
__pycache__
.venv
venv
.mypy_cache
.pytest_cache
.ruff_cache
.tox
.eggs
build
dist
EOF
    ;;
    rust|maven) cat <<'EOF'
target
EOF
    ;;
    go) cat <<'EOF'
bin
dist
EOF
    ;;
    php) cat <<'EOF'
vendor
node_modules
EOF
    ;;
    ruby) cat <<'EOF'
.bundle
vendor/bundle
tmp/cache
EOF
    ;;
    dotnet) cat <<'EOF'
bin
obj
packages
EOF
    ;;
    *) return 0 ;;
  esac
}

has_any() {
  local p
  for p in "$@"; do
    [[ -e "$p" ]] && return 0
  done
  return 1
}

pkg_has_dep() {
  grep -qE "\"$2\"[[:space:]]*:" "$1/package.json" 2>/dev/null
}

# Print every type that matches this directory, one per line. A project can
# legitimately match several (a Flutter app is also an Android project).
detect_types() {
  local d="$1"

  if [[ -f "$d/package.json" ]]; then
    echo "node"
    pkg_has_dep "$d" "react"        && echo "react"
    pkg_has_dep "$d" "vue"          && echo "vue"
    pkg_has_dep "$d" "react-native" && echo "react_native"
    has_any "$d"/next.config.*   && echo "nextjs"
    has_any "$d"/nuxt.config.*   && echo "nuxt"
    has_any "$d"/svelte.config.* && echo "svelte"
    has_any "$d"/astro.config.*  && echo "astro"
    [[ -f "$d/angular.json" ]]   && echo "angular"
    [[ -f "$d/app.json" || -f "$d/expo.json" || -d "$d/.expo" ]] && echo "react_native"
  fi

  [[ -f "$d/pubspec.yaml" ]] && echo "flutter"
  has_any "$d"/build.gradle* "$d"/settings.gradle* && echo "android"
  has_any "$d"/*.xcodeproj "$d"/*.xcworkspace "$d"/Podfile && echo "xcode"
  has_any "$d/pyproject.toml" "$d/requirements.txt" "$d/setup.py" "$d/Pipfile" && echo "python"
  [[ -f "$d/Cargo.toml" ]]     && echo "rust"
  [[ -f "$d/go.mod" ]]         && echo "go"
  [[ -f "$d/pom.xml" ]]        && echo "maven"
  [[ -f "$d/composer.json" ]]  && echo "php"
  [[ -f "$d/Gemfile" ]]        && echo "ruby"
  has_any "$d"/*.csproj "$d"/*.sln && echo "dotnet"

  return 0
}

# ------------------------------------------------------------------ walking

# Only prune directories that can never themselves contain a project. Notably
# absent: dist, build, out, bin, vendor, packages, app - "packages/" is the
# standard monorepo layout, so pruning it would hide every workspace member.
prune_names() {
  cat <<'EOF'
.git
.hg
.svn
.Trash
Library
node_modules
.next
.nuxt
.output
.svelte-kit
.astro
.angular
.nx
.turbo
.parcel-cache
.vite
.cache
.dart_tool
.expo
.gradle
.symlinks
Pods
DerivedData
.swiftpm
__pycache__
.venv
venv
.mypy_cache
.pytest_cache
.ruff_cache
.tox
.eggs
target
coverage
EOF
  local extra
  for extra in ${EXTRA_IGNORES[@]+"${EXTRA_IGNORES[@]}"}; do
    printf '%s\n' "$extra"
  done
}

walk_dirs() {
  local root="$1"
  local prune=() name
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    [[ "${#prune[@]}" -gt 0 ]] && prune+=(-o)
    prune+=(-name "$name")
  done < <(prune_names | sort -u)

  find "$root" -maxdepth "$MAX_DEPTH" \( "${prune[@]}" \) -prune -o -type d -print 2>/dev/null
}

# --------------------------------------------------------------- exclusions

# Never exclude these, whatever a scanner claims - relative to project root.
is_protected() {
  local rel="${2#"$1/"}"
  case "$2" in */.git|*/.git/*) return 0 ;; esac
  case "$rel" in
    src|src/*|lib|lib/*|assets|assets/*) return 0 ;;
  esac
  return 1
}

# True when git considers the path ignored - i.e. it is genuinely generated.
git_ignores() {
  local root="$1" path="$2"
  git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 2
  git -C "$root" check-ignore -q "$path" 2>/dev/null
}

tm_is_excluded() {
  "$TMUTIL_BIN" isexcluded "$1" 2>/dev/null | grep -q '\[Excluded\]'
}

# ------------------------------------------------------------- argument parse

SEARCH_PATHS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--dry-run)     DRY_RUN="true"; shift ;;
    -y|--yes)         ASSUME_YES="true"; shift ;;
    -r|--report-only) REPORT_ONLY="true"; shift ;;
    -s|--size)        SHOW_SIZE="true"; shift ;;
    --no-git-check)   GIT_CHECK="false"; shift ;;
    -d|--depth)
      [[ "${2:-}" =~ ^[0-9]+$ ]] || die "--depth needs a number"
      MAX_DEPTH="$2"; shift 2 ;;
    -i|--ignore)
      [[ -n "${2:-}" ]] || die "--ignore needs a directory name"
      EXTRA_IGNORES+=("$2"); shift 2 ;;
    -h|--help)    usage; exit 0 ;;
    -V|--version) echo "$VERSION"; exit 0 ;;
    -*)           usage >&2; die "Unknown option: $1" ;;
    *)            SEARCH_PATHS+=("$1"); shift ;;
  esac
done

[[ "${#SEARCH_PATHS[@]}" -eq 0 ]] && SEARCH_PATHS=("$PWD")

if [[ "$REPORT_ONLY" != "true" && "$DRY_RUN" != "true" ]]; then
  command -v "$TMUTIL_BIN" >/dev/null 2>&1 || \
    die "tmutil not found. This needs macOS - use --dry-run or --report-only elsewhere."
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/tmignore.XXXXXX")" || die "cannot create temp dir"
trap 'rm -rf "$WORK"' EXIT INT TERM
PROJECTS="$WORK/projects.tsv"
CANDIDATES="$WORK/candidates.tsv"
: > "$PROJECTS"; : > "$CANDIDATES"

# ------------------------------------------------------------------- scanning

collect_candidates() {
  local root="$1" types="$2"
  local t rel cand
  while IFS= read -r t; do
    [[ -z "$t" ]] && continue
    while IFS= read -r rel; do
      [[ -z "$rel" ]] && continue
      cand="$root/$rel"
      [[ -d "$cand" ]] || continue
      is_protected "$root" "$cand" && continue
      printf '%s\t%s\t%s\n' "$root" "$t" "$cand" >> "$CANDIDATES"
    done <<< "$(type_artifacts "$t")"
  done <<< "$types"
}

printf '%s%s%s\n' "${C_BOLD}${C_CYAN}" "tmignore ${VERSION} - a .gitignore for Time Machine" "${C_RESET}"
echo ""

for raw_root in "${SEARCH_PATHS[@]}"; do
  root="${raw_root/#\~/$HOME}"
  if [[ ! -d "$root" ]]; then
    warn "Skipping (not a directory): $raw_root"
    continue
  fi
  root="$(cd "$root" && pwd)"
  say "${C_DIM}Scanning $(tilde "$root") (depth ${MAX_DEPTH})...${C_RESET}"

  while IFS= read -r dir; do
    types="$(detect_types "$dir")"
    [[ -z "$types" ]] && continue
    while IFS= read -r t; do
      [[ -z "$t" ]] && continue
      printf '%s\t%s\t%s\n' "$t" "$(basename "$dir")" "$dir" >> "$PROJECTS"
    done <<< "$types"
    collect_candidates "$dir" "$types"
  done < <(walk_dirs "$root")
done
echo ""

PROJECT_COUNT="$(cut -f3 "$PROJECTS" | sort -u | grep -c . )"
if [[ "$PROJECT_COUNT" -eq 0 ]]; then
  say "No projects found. Try a different folder or a larger --depth."
  exit 0
fi

# --------------------------------------------------------------- type summary

rule "Project types found"
sort -u "$PROJECTS" | cut -f1 | sort | uniq -c | sort -rn | while read -r count t; do
  printf '  %s%-22s%s %s%3d%s\n' "${C_BOLD}" "$(type_label "$t")" "${C_RESET}" \
    "${C_CYAN}" "$count" "${C_RESET}"
done
echo ""

# ------------------------------------------------------------ project listing

rule "Projects"
for t in $ALL_TYPES; do
  hits="$(awk -F'\t' -v t="$t" '$1==t {print $3}' "$PROJECTS" | sort -u)"
  [[ -z "$hits" ]] && continue
  printf '  %s%s%s\n' "${C_BOLD}${C_BLUE}" "$(type_label "$t")" "${C_RESET}"
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    printf '    %-26s %s%s%s\n' "$(basename "$p")" "${C_DIM}" "$(tilde "$p")" "${C_RESET}"
  done <<< "$hits"
done
echo ""

if [[ "$REPORT_ONLY" == "true" ]]; then
  rule "Summary"
  printf '  Projects found      %s%d%s\n' "${C_BOLD}" "$PROJECT_COUNT" "${C_RESET}"
  say "  ${C_DIM}(--report-only: Time Machine was not touched)${C_RESET}"
  exit 0
fi

# ---------------------------------------------------------------- build plan
#
# Decide everything up front and write it down, so the whole list can be
# reviewed before a single exclusion is applied.

PLAN="$WORK/plan.tsv"

sort -u -t$'\t' -k3,3 "$CANDIDATES" | while IFS=$'\t' read -r proj type cand; do
  [[ -z "$cand" ]] && continue

  if [[ "$GIT_CHECK" == "true" ]]; then
    git_ignores "$proj" "$cand"; rc=$?
    if [[ "$rc" -eq 1 ]]; then
      printf 'skipped\t%s\t0\t%s\n' "$type" "$cand"
      continue
    fi
  fi

  if tm_is_excluded "$cand"; then
    printf 'already\t%s\t0\t%s\n' "$type" "$cand"
    continue
  fi

  bytes=0
  if [[ "$SHOW_SIZE" == "true" ]]; then
    kb="$(du -sk "$cand" 2>/dev/null | awk '{print $1}')"
    [[ -n "$kb" ]] && bytes=$((kb * 1024))
  fi
  printf 'exclude\t%s\t%s\t%s\n' "$type" "$bytes" "$cand"
done > "$PLAN"

plan_count() { awk -F'\t' -v a="$1" '$1==a{n++} END{print n+0}' "$PLAN"; }
n_exclude="$(plan_count exclude)"
n_already="$(plan_count already)"
n_skipped="$(plan_count skipped)"
plan_bytes="$(awk -F'\t' '$1=="exclude"{s+=$3} END{print s+0}' "$PLAN")"

# ----------------------------------------------------------------- the list

if [[ "$n_skipped" -gt 0 ]]; then
  rule "Left alone (git tracks these, so they are not generated)"
  awk -F'\t' '$1=="skipped" {print $2 "\t" $4}' "$PLAN" |
    while IFS=$'\t' read -r type path; do
      printf '  %s-%s %s%-14s%s %s\n' \
        "${C_YELLOW}" "${C_RESET}" "${C_DIM}" "$type" "${C_RESET}" "$(tilde "$path")"
    done
  echo ""
fi

rule "To be excluded"
if [[ "$n_exclude" -eq 0 && "$((n_already + n_skipped))" -eq 0 ]]; then
  say "  ${C_DIM}No build artifacts found yet - nothing to exclude.${C_RESET}"
elif [[ "$n_exclude" -eq 0 ]]; then
  say "  ${C_DIM}Nothing new - everything found is already excluded.${C_RESET}"
else
  awk -F'\t' '$1=="exclude" {print $2 "\t" $3 "\t" $4}' "$PLAN" |
    while IFS=$'\t' read -r type bytes path; do
      note=""
      [[ "$SHOW_SIZE" == "true" && "$bytes" -gt 0 ]] && \
        note="  ${C_DIM}($(human_bytes "$bytes"))${C_RESET}"
      printf '  %s+%s %s%-14s%s %s%s\n' \
        "${C_GREEN}" "${C_RESET}" "${C_DIM}" "$type" "${C_RESET}" "$(tilde "$path")" "$note"
    done
fi
echo ""

rule "Summary"
printf '  Projects found        %s%d%s\n' "${C_BOLD}" "$PROJECT_COUNT" "${C_RESET}"
printf '  To exclude            %s%d%s\n' "${C_GREEN}" "$n_exclude" "${C_RESET}"
printf '  Already excluded      %d\n' "$n_already"
[[ "$n_skipped" -gt 0 ]] && \
  printf '  Left alone (in git)   %s%d%s\n' "${C_YELLOW}" "$n_skipped" "${C_RESET}"
[[ "$SHOW_SIZE" == "true" ]] && \
  printf '  Size to keep out      %s%s%s\n' "${C_BOLD}" "$(human_bytes "$plan_bytes")" "${C_RESET}"
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
  say "${C_DIM}Dry run - nothing was changed. Re-run without -n to apply.${C_RESET}"
  exit 0
fi

[[ "$n_exclude" -eq 0 ]] && exit 0

# --------------------------------------------------------------- confirmation

confirm() {
  [[ "$ASSUME_YES" == "true" ]] && return 0

  local reply=""
  local noun="directories"
  [[ "$n_exclude" -eq 1 ]] && noun="directory"

  printf '%sExclude the %d %s listed above from Time Machine? [y/N] %s' \
    "${C_BOLD}" "$n_exclude" "$noun" "${C_RESET}"

  # Reads a tty, a pipe, or a heredoc alike; EOF counts as "no".
  if ! read -r reply; then
    echo ""
    warn "No input available - re-run with --yes to apply."
    return 1
  fi

  case "$reply" in
    y|Y|yes|YES|Yes) return 0 ;;
    *) return 1 ;;
  esac
}

if ! confirm; then
  echo ""
  say "${C_DIM}Cancelled - nothing was changed.${C_RESET}"
  exit 0
fi
echo ""

# --------------------------------------------------------------------- apply

rule "Applying"
applied=0
failed=0
while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  if "$TMUTIL_BIN" addexclusion "$path" >/dev/null 2>&1; then
    applied=$((applied + 1))
    printf '  %s+ excluded%s  %s\n' "${C_GREEN}" "${C_RESET}" "$(tilde "$path")"
  else
    failed=$((failed + 1))
    printf '  %s! failed%s    %s\n' "${C_RED}" "${C_RESET}" "$(tilde "$path")"
  fi
done < <(awk -F'\t' '$1=="exclude" {print $4}' "$PLAN")

echo ""
printf '%sDone.%s Excluded %s%d%s of %d.' \
  "${C_BOLD}" "${C_RESET}" "${C_GREEN}" "$applied" "${C_RESET}" "$n_exclude"
[[ "$failed" -gt 0 ]] && printf ' %s%d failed.%s' "${C_RED}" "$failed" "${C_RESET}"
echo ""
[[ "$failed" -gt 0 ]] && exit 1
exit 0
