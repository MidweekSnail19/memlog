#!/system/bin/sh
# memlog.sh — 真机内存行为采样器(测量研究第 0 步)
# 运行环境: Android + root(KernelSU),POSIX sh,无 bash 依赖
# 用法:    su -c 'sh memlog.sh &'
#          可用环境变量覆盖: INTERVAL=15 LOGDIR=... ZRAM=...
# 停止:    kill $(cat $LOGDIR/memlog.pid)

INTERVAL=${INTERVAL:-30}                      # 采样间隔(秒),嫌分辨率不够改 10-15
LOGDIR=${LOGDIR:-/data/local/tmp/memlog}
ZRAM=${ZRAM:-/sys/block/zram0/mm_stat}

mkdir -p "$LOGDIR" || exit 1

# 计数器随重启清零 → 每次开机一个新文件,跨重启不做差分
TAG=$(date +%Y%m%d_%H%M%S)
LOG="$LOGDIR/mem_$TAG.csv"
echo $$ > "$LOGDIR/memlog.pid"

# 一次性抓环境元数据 —— 报告里"实验环境"一节的原始材料
{
  echo "start:      $(date)"
  echo "kernel:     $(uname -r)"
  echo "MemTotal:   $(awk '/^MemTotal:/{print $2}' /proc/meminfo) kB"
  echo "swappiness: $(cat /proc/sys/vm/swappiness 2>/dev/null)"
  echo "zram size:  $(cat /sys/block/zram0/disksize 2>/dev/null)"
  echo "zram algo:  $(cat /sys/block/zram0/comp_algorithm 2>/dev/null)"
  echo "page size:  $(getconf PAGE_SIZE 2>/dev/null)"
} > "$LOGDIR/meta_$TAG.txt"

# 列说明:
#   epoch/uptime        — 时间戳 / 开机秒数(uptime 回跳 = 发生过重启)
#   mem_avail/swap_free — kB,来自 /proc/meminfo
#   refault_*           — workingset refault 事件数(累计,单位:次)
#   pswpin/pswpout      — 换入/换出页数(累计,单位:页)
#   pgmajfault          — 主缺页(累计)
#   psi_*               — avg10 为百分比,total 为累计微秒
#   zr_*                — zram mm_stat 九个字段,前三个为字节
#                         zr_huge_pages = 不可压缩页数(熵代理)
echo "epoch,uptime,mem_avail_kb,swap_free_kb,refault_anon,refault_file,pswpin,pswpout,pgmajfault,psi_some_avg10,psi_some_total_us,psi_full_avg10,psi_full_total_us,zr_orig_bytes,zr_compr_bytes,zr_used_bytes,zr_limit,zr_max_used,zr_same_pages,zr_compacted,zr_huge_pages,zr_huge_since" > "$LOG"

while :; do
  E=$(date +%s)
  UP=$(cut -d' ' -f1 /proc/uptime)

  MEM=$(awk '/^MemAvailable:/{a=$2} /^SwapFree:/{s=$2} END{printf "%s,%s",a,s}' /proc/meminfo)

  VMS=$(awk '$1=="workingset_refault_anon"{a=$2}
             $1=="workingset_refault_file"{f=$2}
             $1=="pswpin"{i=$2}
             $1=="pswpout"{o=$2}
             $1=="pgmajfault"{m=$2}
             END{printf "%s,%s,%s,%s,%s",a,f,i,o,m}' /proc/vmstat)

  PSI=$(awk '$1=="some"{split($2,a,"="); split($5,t,"="); sa=a[2]; st=t[2]}
             $1=="full"{split($2,a,"="); split($5,t,"="); fa=a[2]; ft=t[2]}
             END{printf "%s,%s,%s,%s",sa,st,fa,ft}' /proc/pressure/memory)

  if [ -r "$ZRAM" ]; then
    Z=$(sed 's/^ *//; s/ *$//; s/  */,/g' "$ZRAM")
  else
    Z=",,,,,,,,"            # 设备不在时占位,保持列数稳定
  fi

  echo "$E,$UP,$MEM,$VMS,$PSI,$Z" >> "$LOG"
  sleep "$INTERVAL"
done
