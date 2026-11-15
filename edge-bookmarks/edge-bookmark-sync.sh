#!/bin/bash
# edge-bookmark-sync.sh —— 用一台机器（默认 sun）的 Edge 收藏夹覆盖其它机器
#
# 用法:
#   ./edge-bookmark-sync.sh                      # sun → 本机 + surface
#   ./edge-bookmark-sync.sh --dry-run            # 只看会做什么
#   ./edge-bookmark-sync.sh --source sun --targets local,surface
#   ./edge-bookmark-sync.sh --restore            # 用最近一次备份回滚所有目标
#   ./edge-bookmark-sync.sh --keep-edge          # 不关闭 Edge（不推荐，会被回写）
#
# 其它参数: --profile Default  --no-verify
set -uo pipefail

SOURCE=sun
TARGETS="local,surface"
PROFILE="Default"
DRY_RUN=0
KEEP_EDGE=0
RESTORE=0
VERIFY=1

while [ $# -gt 0 ]; do
    case "$1" in
        --source)   SOURCE="$2"; shift 2 ;;
        --targets)  TARGETS="$2"; shift 2 ;;
        --profile)  PROFILE="$2"; shift 2 ;;
        --dry-run)  DRY_RUN=1; shift ;;
        --keep-edge) KEEP_EDGE=1; shift ;;
        --restore)  RESTORE=1; shift ;;
        --no-verify) VERIFY=0; shift ;;
        -h|--help)  sed -n '2,16p' "$0"; exit 0 ;;
        *) echo "未知参数: $1"; exit 2 ;;
    esac
done

REL=".config/microsoft-edge/$PROFILE/Bookmarks"
TS=$(date +%Y%m%d-%H%M%S)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

log()  { printf '%s\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*"; }
ok()   { printf '\033[32m%s\033[0m\n' "$*"; }
die()  { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

# ---------- 工具函数 ----------
# 读取某个目标（local 或 ssh 别名）上的文件内容到 stdout
read_remote() {   # $1=target(或 local)  $2=相对路径
    if [ "$1" = "local" ]; then cat "$HOME/$2" 2>/dev/null
    else ssh -o BatchMode=yes -o ConnectTimeout=8 "$1" "cat ~/$2" 2>/dev/null
    fi
}
run_remote() {    # $1=target  $2=命令
    if [ "$1" = "local" ]; then bash -c "$2"
    else ssh -o BatchMode=yes -o ConnectTimeout=8 "$1" "$2"
    fi
}
count_entries() { # stdin=Bookmarks json → 书签栏条目数
    /usr/bin/python3 -c '
import json,sys
try:
    d=json.load(sys.stdin)
except Exception:
    print("BAD"); raise SystemExit
def w(n):
    o=[]
    for c in n.get("children",[]):
        o.append(c); o+=w(c)
    return o
print(len(w(d.get("roots",{}).get("bookmark_bar",{}))))
'
}

# ---------- 1) 取源 ----------
log "== 源: $SOURCE ($REL) =="
read_remote "$SOURCE" "$REL" > "$TMP/Bookmarks.src"
[ -s "$TMP/Bookmarks.src" ] || die "取不到源文件：$SOURCE:~/$REL"

SRC_ENTRIES=$(count_entries < "$TMP/Bookmarks.src")
[ "$SRC_ENTRIES" != "BAD" ] || die "源文件不是合法 JSON，放弃同步"
SRC_MD5=$(md5sum "$TMP/Bookmarks.src" | cut -d' ' -f1)
SRC_SIZE=$(stat -c %s "$TMP/Bookmarks.src")
ok "源 OK: ${SRC_ENTRIES} 条 / ${SRC_SIZE}B / ${SRC_MD5:0:8}"

# ---------- 2) 逐个目标 ----------
IFS=',' read -r -a TARR <<< "$TARGETS"
FAIL=0
printf '\n%-12s %-8s %-10s %s\n' "目标" "条目" "MD5" "结果"
printf '%s\n' "-----------------------------------------------------"

for t in "${TARR[@]}"; do
    [ -z "$t" ] && continue

    if [ "$RESTORE" = "1" ]; then
        # 用该目标上最近一次 *.ours-* 备份回滚
        latest=$(run_remote "$t" "ls -1t ~/$REL.ours-* 2>/dev/null | head -1")
        [ -n "$latest" ] || { warn "$t: 没有可回滚的备份"; FAIL=1; continue; }
        if [ "$DRY_RUN" = "1" ]; then
            log "$t: [dry-run] 将回滚到 $(basename "$latest")"
            continue
        fi
        run_remote "$t" "pkill -x msedge 2>/dev/null; sleep 2; cp '$latest' ~/$REL && chmod 600 ~/$REL" \
            || { warn "$t: 回滚失败"; FAIL=1; continue; }
        newmd5=$(read_remote "$t" "$REL" | md5sum | cut -d' ' -f1)
        printf '%-12s %-8s %-10s %s\n' "$t" "-" "${newmd5:0:8}" "已回滚到 $(basename "$latest")"
        continue
    fi

    # 备份 + 关闭 Edge + 写入
    cmd="set -e
mkdir -p \$(dirname ~/$REL)
cp ~/$REL ~/$REL.ours-$TS 2>/dev/null || true
if [ '$KEEP_EDGE' != '1' ]; then pkill -x msedge 2>/dev/null || true; sleep 2; fi
cp '{SRCPLACEHOLDER}' ~/$REL
chmod 600 ~/$REL"
    if [ "$DRY_RUN" = "1" ]; then
        log "$t: [dry-run] 备份为 Bookmarks.ours-$TS，然后用源覆盖$( [ "$KEEP_EDGE" = "1" ] && echo '（不关 Edge）')"
        continue
    fi

    if [ "$t" = "local" ]; then
        cmd=${cmd//\{SRCPLACEHOLDER\}/$TMP/Bookmarks.src}
        bash -c "$cmd" || { warn "$t: 写入失败"; FAIL=1; continue; }
    else
        scp -q "$TMP/Bookmarks.src" "$t":/tmp/Bookmarks.src || { warn "$t: 传文件失败"; FAIL=1; continue; }
        cmd=${cmd//\{SRCPLACEHOLDER\}/\/tmp/Bookmarks.src}
        run_remote "$t" "$cmd" || { warn "$t: 写入失败"; FAIL=1; continue; }
    fi

    NEW=$(read_remote "$t" "$REL")
    NEW_MD5=$(run_remote "$t" "md5sum ~/$REL 2>/dev/null | cut -d' ' -f1")
    NEW_ENTRIES=$(printf '%s' "$NEW" | count_entries)

    if [ "$VERIFY" = "1" ] && [ "$NEW_MD5" != "$SRC_MD5" ]; then
        warn "$t: 写入后 MD5 不一致（可能 Edge 又把文件改回去了 = 开了收藏夹同步）"
        FAIL=1
    fi
    printf '%-12s %-8s %-10s %s\n' "$t" "$NEW_ENTRIES" "${NEW_MD5:0:8}" "$([ "$NEW_MD5" = "$SRC_MD5" ] && echo ✅ 一致 || echo ⚠️ 不一致)"
done

echo
if [ "$DRY_RUN" = "1" ]; then warn "dry-run 模式，未做任何修改"; exit 0; fi
if [ "$FAIL" = "0" ]; then ok "全部完成（源 $SRC_MD5）"; else die "有目标未成功，见上方警告"; fi
