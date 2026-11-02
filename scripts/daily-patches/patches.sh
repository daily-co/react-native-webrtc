#!/usr/bin/env bash
# Daily patch queue helper. Reads manifest.json next to this script.
#
#   patches.sh check <tag>          Report how each patch applies on top of upstream <tag>.
#   patches.sh generate [branch]    Regenerate patches/ from [branch] (default: manifest patchBranch),
#                                   one commit per patch, subject "<id>: <title>".
#   patches.sh verify <tag> <ref>   Apply all patches to <tag> and diff the result against <ref>,
#                                   ignoring regenerated files and repoOnly paths.
#   patches.sh audit <base> <new> <ref>
#                                   Check that <ref> brought every upstream change from <base>..<new>:
#                                   files differing from <new> must belong to a patch, and upstream
#                                   changes to patched files must still be present.
#   patches.sh build                npm run lint + npm run prepare, then check that index.d.ts
#                                   imports resolve and re-exports everything src/index.ts exports.
#   patches.sh coverage <tag> <ref> Check that every native method, JS method and native event the
#                                   patches add or change (<tag>..<ref>) is named in the self-test.
#   patches.sh api <base> <new>     Diff the public TypeScript declarations of upstream <base> and <new>.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$DIR/manifest.json"
cd "$(git -C "$DIR" rev-parse --show-toplevel)"

manifest() { node -e "const m=require('$MANIFEST'); $1"; }
patch_files() { manifest "m.patches.forEach(p => console.log(p.file))"; }
excludes() {
  manifest "m.regenerate.forEach(r => console.log(':!' + r.file));
            m.repoOnly.paths.forEach(p => console.log(':!' + p))"
}

WT=""
cleanup() { [ -n "$WT" ] && git worktree remove --force "$WT" >/dev/null 2>&1 || true; }
trap cleanup EXIT
new_worktree() {
  WT="$(mktemp -d)/wt"
  git worktree add -q --detach "$WT" "$1"
}

cmd_check() {
  local tag="$1" base
  base="$(manifest "console.log(m.upstream.baseTag)")"
  git rev-parse -q --verify "$tag^{commit}" >/dev/null || { echo "unknown tag: $tag (git fetch upstream --tags)"; exit 1; }
  new_worktree "$tag"
  local failed=0
  printf '%-36s %-16s %s\n' PATCH RESULT "UPSTREAM CHANGES ${base}..${tag} IN PATCHED FILES"
  while read -r rel; do
    local p="$DIR/$rel" id result detail="" files changed
    id="$(manifest "console.log(m.patches.find(p => p.file === '$rel').id)")"
    files="$(manifest "console.log(m.patches.find(p => p.file === '$rel').files.join('\n'))")"
    changed="$(git diff --name-only "$base" "$tag" -- $files | wc -l | tr -d ' ')"
    if git -C "$WT" apply --whitespace=nowarn --check "$p" 2>/dev/null; then
      git -C "$WT" apply --whitespace=nowarn --index "$p"; result=clean
    elif git -C "$WT" apply --whitespace=nowarn --check -R "$p" 2>/dev/null; then
      result=already-upstream
    elif git -C "$WT" apply --whitespace=nowarn --3way "$p" >/dev/null 2>&1; then
      result=3way
    else
      result=conflict; failed=1
      detail="$(git -C "$WT" diff --name-only --diff-filter=U | sed 's/^/      conflict: /')"
      git -C "$WT" reset -q --hard
    fi
    git -C "$WT" -c user.name=check -c user.email=check@localhost commit -q --no-verify --allow-empty -m "$id"
    printf '%-36s %-16s %s file(s)\n' "$id" "$result" "$changed"
    [ -n "$detail" ] && echo "$detail"
    if [ "$result" != clean ]; then
      manifest "const p=m.patches.find(p => p.file === '$rel');
                if (p.obsoleteWhen) console.log('      obsoleteWhen: ' + p.obsoleteWhen);
                if (p.notes) console.log('      notes: ' + p.notes);"
    fi
  done < <(patch_files)
  return $failed
}

cmd_generate() {
  local branch="${1:-$(manifest "console.log(m.patchBranch)")}" base tmp
  base="$(manifest "console.log(m.upstream.baseTag)")"
  if git log --format=%B "$base..$branch" | grep -qi '^Co-Authored-By: Claude'; then
    echo "commit messages on $branch contain Claude attribution; remove it first"; exit 1
  fi
  tmp="$(mktemp -d)"
  # --no-numbered keeps subjects ("[PATCH] <id>: <title>") stable when patches are added or dropped.
  git format-patch --zero-commit --no-signature --no-numbered -q -o "$tmp" "$base..$branch"
  for f in "$tmp"/*.patch; do
    local n id
    n="$(basename "$f" | cut -d- -f1)"
    id="$(sed -n 's/^Subject: \[PATCH\] \([a-z0-9-]*\):.*/\1/p' "$f")"
    [ -n "$id" ] || { echo "$(basename "$f"): subject is not '<id>: <title>'"; exit 1; }
    mv "$f" "$tmp/$n-$id.patch"
  done
  # Sync manifest order, file names and file lists with the generated patches.
  node - "$MANIFEST" "$tmp" <<'EOF'
const fs = require('fs'), path = require('path');
const [manifestPath, dir] = process.argv.slice(2);
const m = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
const byId = new Map(m.patches.map(p => [p.id, p]));
const generated = fs.readdirSync(dir).filter(f => f.endsWith('.patch')).sort();
const ids = generated.map(f => f.replace(/^\d+-/, '').replace(/\.patch$/, ''));
const missing = ids.filter(id => !byId.has(id));
const stale = m.patches.map(p => p.id).filter(id => !ids.includes(id));
if (missing.length || stale.length) {
  if (missing.length) console.error('commits without a manifest entry: ' + missing.join(', '));
  if (stale.length) console.error('manifest entries without a commit: ' + stale.join(', '));
  process.exit(1);
}
m.patches = generated.map((f, i) => {
  const p = byId.get(ids[i]);
  const text = fs.readFileSync(path.join(dir, f), 'utf8');
  p.file = 'patches/' + f;
  p.files = [...text.matchAll(/^diff --git a\/(\S+) /gm)].map(x => x[1]).sort();
  return p;
});
fs.writeFileSync(manifestPath, JSON.stringify(m, null, 2) + '\n');
EOF
  # Same formatting lint-staged applies on commit.
  node_modules/.bin/prettier --write --loglevel warn "$MANIFEST"
  rm -f "$DIR"/patches/*.patch
  mv "$tmp"/*.patch "$DIR/patches/"
  rmdir "$tmp"
  echo "generated $(ls "$DIR"/patches/*.patch | wc -l | tr -d ' ') patches from $branch"
}

cmd_verify() {
  local tag="$1" ref="$2"
  new_worktree "$tag"
  local files=()
  while read -r rel; do files+=("$DIR/$rel"); done < <(patch_files)
  git -C "$WT" -c user.name=verify -c user.email=verify@localhost am -q -3 --whitespace=nowarn "${files[@]}"
  echo "applied ${#files[@]} patches to $tag"
  local diff
  diff="$(git -C "$WT" diff --stat HEAD "$ref" -- . $(excludes))"
  if [ -n "$diff" ]; then
    echo "$ref differs from patched $tag:"; echo "$diff"; exit 1
  fi
  echo "$ref is identical to patched $tag (ignoring: $(excludes | tr '\n' ' '))"
}

cmd_audit() {
  local base="$1" new="$2" ref="$3" failed=0 patched upstream
  patched="$(manifest "console.log([...new Set(m.patches.flatMap(p => p.files))].join('\n'))")"
  upstream="$(git diff --name-only "$base" "$new")"

  echo "upstream $base..$new changed $(echo "$upstream" | grep -c . || true) file(s)"
  local drift=()
  while read -r f; do
    [ -z "$f" ] && continue
    grep -qxF "$f" <<<"$patched" || drift+=("$f")
  done < <(git diff --name-only "$new" "$ref" -- . $(excludes))
  if [ ${#drift[@]} -gt 0 ]; then
    failed=1
    echo "differs from $new but not part of any patch (lost upstream change or unrecorded Daily change):"
    printf '  %s\n' "${drift[@]}"
  else
    echo "every file that differs from $new belongs to a patch"
  fi

  # Upstream changes to files a patch also touches: reverse-apply upstream's diff on <ref>.
  local idx overlap=0 d apply_args
  idx="$(mktemp)"
  GIT_INDEX_FILE="$idx" git read-tree "$ref"
  while read -r f; do
    [ -z "$f" ] && continue
    grep -qxF "$f" <<<"$patched" || continue
    overlap=1
    if [ "$f" = package.json ]; then
      # fork-packaging always replaces upstream's "version", so leave those hunks out.
      d="$(git diff -U0 "$base" "$new" -- "$f" | awk '
        function flush() { if (inhunk && keep) out = out hunk }
        /^@@/ { flush(); hunk = $0 "\n"; keep = 0; inhunk = 1; next }
        inhunk { hunk = hunk $0 "\n"; if ($0 ~ /^[-+]/ && $0 !~ /^[-+][[:space:]]*"version":/) keep = 1; next }
        { header = header $0 "\n" }
        END { flush(); if (out != "") printf "%s%s", header, out }')"
      if [ -z "$d" ]; then
        printf '  %-70s only "version" changed upstream\n' "$f"; continue
      fi
      apply_args=(--unidiff-zero)
    else
      d="$(git diff "$base" "$new" -- "$f")"
      apply_args=()
    fi
    if GIT_INDEX_FILE="$idx" git apply --cached --check -R --whitespace=nowarn ${apply_args[@]+"${apply_args[@]}"} <<<"$d" 2>/dev/null; then
      printf '  %-70s upstream change present\n' "$f"
    elif git diff --quiet "$new" "$ref" -- "$f" 2>/dev/null; then
      printf '  %-70s identical to %s\n' "$f" "$new"
    else
      printf '  %-70s REVIEW: upstream change not found verbatim\n' "$f"
      failed=1
    fi
  done <<<"$upstream"
  rm -f "$idx"
  [ $overlap -eq 0 ] && echo "no upstream change touches a patched file"
  return $failed
}

cmd_build() {
  npm run lint
  npm run prepare
  node - <<'EOF'
const fs = require('fs'), path = require('path');
const dts = fs.readFileSync('index.d.ts', 'utf8');
const missing = [...dts.matchAll(/from '(\.[^']+)'/g)].map(m => m[1])
  .filter(p => !['.d.ts', '.ts', '/index.d.ts'].some(ext => fs.existsSync(path.resolve(p + ext))));
const names = src => new Set([...src.matchAll(/export\s*\{([^}]*)\}/g)]
  .flatMap(m => m[1].split(','))
  .map(n => n.replace(/\btype\b/, '').trim().split(/\s+as\s+/).pop())
  .filter(Boolean));
const exported = names(fs.readFileSync('src/index.ts', 'utf8')), declared = names(dts);
const notReexported = [...exported].filter(n => !declared.has(n));
if (missing.length) console.error('index.d.ts imports that do not resolve: ' + missing.join(', '));
if (notReexported.length) console.error('exported by src/index.ts but not by index.d.ts: ' + notReexported.join(', '));
if (missing.length || notReexported.length) process.exit(1);
console.log('index.d.ts: imports resolve and re-exports match src/index.ts');
EOF
}

cmd_coverage() {
  local tag="$1" ref="$2"
  # Lines the patches add to the library itself (not the self-test app or fork tooling).
  node - "$MANIFEST" "$ref" <(git diff -U0 "$tag" "$ref" -- android ios src $(excludes)) <<'EOF'
const { execFileSync } = require('child_process');
const [manifestPath, ref, diffPath] = process.argv.slice(2);
const { coverage } = require(manifestPath);
const diff = require('fs').readFileSync(diffPath, 'utf8');
const found = new Map(); // name -> where
const constants = new Map(), sent = [];
let file = '', prevAdded = '';
for (const line of diff.split('\n')) {
  if (line.startsWith('+++ ')) { file = line.slice(6); prevAdded = ''; continue; }
  if (!line.startsWith('+') || line.startsWith('+++')) { prevAdded = ''; continue; }
  const l = line.slice(1), code = l.trim();
  if (code.startsWith('//') || code.startsWith('*')) continue;
  const add = (name, kind) => found.has(name) || found.set(name, `${kind} in ${file}`);
  let m;
  if ((m = l.match(/RCT_EXPORT_METHOD\(\s*(\w+)/))) add(m[1], 'iOS method');
  if (/^@ReactMethod\b/.test(prevAdded) && (m = l.match(/^\s*public\s+[\w<>\[\]]+\s+(\w+)\s*\(/))) add(m[1], 'Android method');
  // Events are sent by literal or by a string constant, resolved once all constants are known.
  if ((m = l.match(/static final String (\w+) = "(\w+)"/)) || (m = l.match(/NSString \*const (\w+) = @"(\w+)"/))) constants.set(m[1], m[2]);
  if ((m = l.match(/(?:sendEvent\s*\(|sendEventWithName:)\s*@?"(\w+)"/))) add(m[1], 'native event');
  if ((m = l.match(/(?:sendEvent\s*\(|sendEventWithName:)\s*(\w+)/))) sent.push([m[1], file]);
  if (file === 'src/EventEmitter.ts' && (m = l.match(/^\s*'(\w+)',?$/))) add(m[1], 'native event');
  // Class members are indented by exactly 4 spaces in src/.
  if (file.startsWith('src/') && (m = l.match(/^ {4}(?:async\s+)?(\w+)\s*\(.*\)\s*(?::\s*[^=]+)?\{$/))) add(m[1], 'JS method');
  prevAdded = code;
}
for (const [id, where] of sent) {
  if (constants.has(id) && !found.has(constants.get(id))) found.set(constants.get(id), `native event in ${where}`);
}
if (!found.size) {
  console.error('found no API added by the patches; is <tag> the upstream tag the patches apply to?');
  process.exit(1);
}
const test = execFileSync('git', ['show', `${ref}:${coverage.selfTest}`], { encoding: 'utf8' });
const ignored = new Set(['constructor', ...Object.keys(coverage.internal)]);
const missing = [...found].filter(([name]) => !ignored.has(name) && !new RegExp(`\\b${name}\\b`).test(test));
for (const [name, where] of [...found].sort()) {
  const status = ignored.has(name) ? 'internal' : missing.some(([n]) => n === name) ? 'MISSING' : 'covered';
  console.log(`  ${name.padEnd(52)} ${status.padEnd(9)} ${where}`);
}
if (missing.length) {
  console.error(`not named in ${coverage.selfTest}: ${missing.map(([n]) => n).join(', ')}`);
  console.error('add a check for it, or list it in manifest coverage.internal with the reason');
  process.exit(1);
}
console.log(`every API the patches add or change is named in ${coverage.selfTest}`);
EOF
}

cmd_api() {
  local base="$1" new="$2" out tag
  out="$(mktemp -d)"
  for tag in "$base" "$new"; do
    new_worktree "$tag"
    ln -s "$PWD/node_modules" "$WT/node_modules"
    # Type errors (older upstream configs, missing dependencies) don't block emitting declarations.
    node_modules/.bin/tsc -p "$WT" --declaration --emitDeclarationOnly --noEmit false --skipLibCheck \
      --types react,react-native,debug --outDir "$out/$tag" >/dev/null 2>&1 || true
    [ -n "$(ls -A "$out/$tag" 2>/dev/null)" ] || { echo "tsc emitted no declarations for $tag"; exit 1; }
    cleanup; WT=""
  done
  # The vendored event-target-shim is third-party; its declarations are copied, not generated.
  (cd "$out" && diff -ru -x vendor "$base" "$new") || true
  rm -rf "$out"
}

case "${1:-}" in
  check) [ $# -eq 2 ] || { echo "usage: $0 check <tag>"; exit 2; }; cmd_check "$2" ;;
  generate) cmd_generate "${2:-}" ;;
  verify) [ $# -eq 3 ] || { echo "usage: $0 verify <tag> <ref>"; exit 2; }; cmd_verify "$2" "$3" ;;
  audit) [ $# -eq 4 ] || { echo "usage: $0 audit <base> <new> <ref>"; exit 2; }; cmd_audit "$2" "$3" "$4" ;;
  build) cmd_build ;;
  coverage) [ $# -eq 3 ] || { echo "usage: $0 coverage <tag> <ref>"; exit 2; }; cmd_coverage "$2" "$3" ;;
  api) [ $# -eq 3 ] || { echo "usage: $0 api <base> <new>"; exit 2; }; cmd_api "$2" "$3" ;;
  *) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
