#!/usr/bin/env bash
# Live driver: runs the real bin/fm-bootstrap.sh against fixture homes whose
# projects/ clones carry different origin URLs and records the exact stdout.
set -u
ROOT=$1; EV=$2
WORK=$(mktemp -d "${TMPDIR:-/tmp}/fm-glab-live.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
FAKEBIN="$WORK/fakebin"; mkdir -p "$FAKEBIN"
BASE_PATH=/usr/bin:/bin:/usr/sbin:/sbin
unset TMUX TMUX_PANE HERDR_ENV HERDR_PANE_ID HERDR_SESSION HERDR_SOCKET_PATH CMUX_WORKSPACE_ID CMUX_SURFACE_ID CMUX_SOCKET_PATH CMUX_TAB_ID CMUX_PANEL_ID 2>/dev/null || true
export FM_BACKEND_CMUX_BUNDLE_BIN="$WORK/no-bundled-cmux"
stub() { for t in "$@"; do printf '#!/usr/bin/env bash\nexit 0\n' > "$FAKEBIN/$t"; chmod +x "$FAKEBIN/$t"; done; }
vstub() { printf '#!/usr/bin/env bash\n[ "${1:-}" = --version ] && { printf "%%s\\n" "%s"; exit 0; }\nexit 0\n' "$2" > "$FAKEBIN/$1"; chmod +x "$FAKEBIN/$1"; }
stub tmux node chrome-devtools-axi gh
vstub lavish-axi 0.1.46; vstub gh-axi 0.1.29; vstub quota-axi 0.1.29
vstub no-mistakes 'no-mistakes version v1.46.0 (fake) 2026-06-27T00:02:18Z'
cat > "$FAKEBIN/treehouse" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = get ] && [ "${2:-}" = --help ] && { echo 'Usage: treehouse get [--lease] [--lease-holder <holder>]'; exit 0; }
exit 0
SH
chmod +x "$FAKEBIN/treehouse"
cat > "$FAKEBIN/tasks-axi" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = --version ] && { echo 0.2.4; exit 0; }
[ "${1:-}" = update ] && [ "${2:-}" = --help ] && { printf '%s\n' 'usage: tasks-axi update <id> [flags]' '  --body-file <path>' '  --archive-body'; exit 0; }
[ "${1:-}" = mv ] && [ "${2:-}" = --help ] && { echo 'usage: tasks-axi mv <id> [<id>...] --to <path-or-dir>'; exit 0; }
exit 0
SH
chmod +x "$FAKEBIN/tasks-axi"

HOME_DIR="$WORK/home"; mkdir -p "$HOME_DIR/config" "$HOME_DIR/projects"
echo manual > "$HOME_DIR/config/backlog-backend"
n=0
addrepo() { n=$((n+1)); local d="$HOME_DIR/projects/$1"; git init -q "$d"; [ -n "${2:-}" ] && git -C "$d" remote add origin "$2"; }
run() {
  local label=$1 out err rc
  out=$(PATH="$FAKEBIN:$BASE_PATH" FM_HOME="$HOME_DIR" FM_ROOT_OVERRIDE="$HOME_DIR" "$ROOT/bin/fm-bootstrap.sh" 2>"$WORK/err"); rc=$?
  err=$(cat "$WORK/err")
  printf '== %s\n   origins: %s\n   exit=%s\n   stdout: %s\n' "$label" "$(for p in "$HOME_DIR"/projects/*; do [ -d "$p" ] && printf '[%s] ' "$(git -C "$p" remote get-url origin 2>/dev/null || echo none)"; done)" "$rc" "${out:-<empty>}"
  [ -z "$err" ] || printf '   stderr: %s\n' "$err"
}
echo "# fm-bootstrap.sh live run: glab requirement vs. origin hosts  ($(date -u +%FT%TZ))"
echo "# glab on PATH: no (fakebin + $BASE_PATH only)"
addrepo gh-scp git@github.com:owner/repo.git
addrepo gh-https https://github.com/owner/repo.git
addrepo gh-ssh-port ssh://git@github.com:22/owner/repo.git
addrepo gh-upper https://GitHub.COM/owner/repo.git
addrepo file-origin "file://$HOME_DIR/remotes/x.git"
addrepo no-origin
addrepo bad-host git@my_host:owner/repo.git
: > "$HOME_DIR/projects/stray-file"
run "S1 GitHub-only home (scp, https, ssh+port, upper-case, file://, origin-less, underscore host, stray file) -> expect silence"

addrepo ksb-scp git@git.ksb-intax.app:ksb/ai-chat.git
run "S2 captain's self-hosted GitLab scp origin -> expect MISSING: glab"
rm -rf "$HOME_DIR/projects/ksb-scp"

addrepo gl-https https://Git.Example.Test/group/sub/proj.git
run "S3 https mixed-case self-hosted host, no 'gitlab' in name -> expect MISSING: glab"
git -C "$HOME_DIR/projects/gl-https" remote set-url origin ssh://git@git.example.test:2222/group/proj.git
run "S4 ssh:// with port -> expect MISSING: glab"
git -C "$HOME_DIR/projects/gl-https" remote set-url origin https://oauth2:tok@gitlab.com/group/proj.git
run "S5 https with user:token@ credential in URL -> expect MISSING: glab"
rm -rf "$HOME_DIR/projects/gl-https"

addrepo gh-alias git@github-work:owner/repo.git
run "S6 ADVERSARIAL GitHub SSH alias host -> documented false positive: expect MISSING: glab"
rm -rf "$HOME_DIR/projects/gh-alias"

addrepo gl-again git@git.ksb-intax.app:ksb/ai-chat.git
ln -s "$(command -v glab)" "$FAKEBIN/glab"
echo "# now linking the real glab ($(command -v glab), $(glab --version 2>/dev/null | head -1)) into PATH"
run "S7 GitLab origin present AND real glab on PATH -> expect silence"
rm -f "$FAKEBIN/glab"
run "S8 remove glab again -> expect MISSING: glab back"
