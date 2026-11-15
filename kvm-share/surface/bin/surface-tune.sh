#!/bin/bash
# Surface Pro 5 性能调优：解除人为的频率上限（不是去掉温控）
# 用法: surface-tune.sh [perf|balanced|powersave]
MODE=${1:-balanced}
P=/sys/devices/system/cpu/intel_pstate
case "$MODE" in
  perf)
     echo 0 > $P/no_turbo 2>/dev/null; echo 100 > $P/max_perf_pct 2>/dev/null
     EPP=performance; PP=performance ;;
  powersave)
     echo 1 > $P/no_turbo 2>/dev/null; echo 40 > $P/max_perf_pct 2>/dev/null
     EPP=power; PP=low-power ;;
  *)
     echo 0 > $P/no_turbo 2>/dev/null; echo 100 > $P/max_perf_pct 2>/dev/null
     EPP=balance_performance; PP=balanced-performance ;;
esac
echo "$PP" > /sys/firmware/acpi/platform_profile 2>/dev/null
for c in /sys/devices/system/cpu/cpufreq/policy*/energy_performance_preference; do
    [ -w "$c" ] && echo "$EPP" > "$c" 2>/dev/null
done
echo "mode=$MODE no_turbo=$(cat $P/no_turbo) max_perf_pct=$(cat $P/max_perf_pct) epp=$(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null) profile=$(cat /sys/firmware/acpi/platform_profile 2>/dev/null)"
