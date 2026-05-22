#!/bin/sh

# удалить ранние main/default for ros = 7.22
ip rule | awk '
/lookup main/ && $1+0 < 32766 {gsub(":","",$1); print $1}
/lookup default/ && $1+0 < 32767 {gsub(":","",$1); print $1}
' | while read prio; do
    ip rule del priority "$prio" 2>/dev/null
done
# гарантировать системные правила
ip rule | grep -q "lookup main" || \
    ip rule add lookup main priority 32766

ip rule | grep -q "lookup default" || \
    ip rule add lookup default priority 32767

exec /sbin/init