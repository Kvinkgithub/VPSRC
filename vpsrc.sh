#!/bin/bash
# ============================================================
# VPS RESOURCES CHECKER by Kvink
# ============================================================

trap 'echo -e "\n👋 Пока!"; exit 0' INT TERM

# --- Цвета ---
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'
C='\033[0;36m'; M='\033[0;35m'; N='\033[0m'; W='\033[1;37m'
BD='\033[1m'; DM='\033[2m'

# --- Папка для логов ---
LOG_DIR="/var/log/cpu_monitor"
mkdir -p "$LOG_DIR" 2>/dev/null

# --- Мониторинг в фоне ---
if ! pgrep -f "vpsrc_daemon" >/dev/null 2>&1; then
    nohup bash -c '
        while true; do
            echo "[$(date +"%Y-%m-%d %H:%M:%S")]" >> '"$LOG_DIR"'/cpu_$(date +%Y%m%d).log
            ps aux --sort=-%cpu | head -11 | tail -10 >> '"$LOG_DIR"'/cpu_$(date +%Y%m%d).log
            echo "---" >> '"$LOG_DIR"'/cpu_$(date +%Y%m%d).log
            sleep 60
        done
    ' > /dev/null 2>&1 &
fi

# --- Очистка экрана ---
clear_screen() { printf "\033[2J\033[H"; }

# --- Логотип ---
logo() {
    clear_screen
    echo ""
    echo -e "  ${C}▸${N} ${W}VPS RESOURCES CHECKER${N} ${DM}by Kvink${N}"
    echo -e "  ${DM}  $(date '+%H:%M:%S')  |  $(hostname)${N}"
    echo ""
}

# --- Полоска ---
draw_bar() {
    local percent=$1
    local width=30
    local filled=$((percent * width / 100))
    [ "$filled" -gt "$width" ] && filled=$width
    [ "$filled" -lt 0 ] && filled=0
    local empty=$((width - filled))
    
    if [ "$filled" -gt 0 ]; then
        printf "%${filled}s" | tr ' ' '#'
    fi
    if [ "$empty" -gt 0 ]; then
        printf "%${empty}s" | tr ' ' '-'
    fi
}

# --- Показываем CPU ---
show_cpu() {
    local load=$(uptime | awk -F'load average:' '{print $2}' | xargs)
    echo -e "  ${Y}▸ Нагрузка:${N} $load"
    
    local idle=$(top -bn1 2>/dev/null | grep "Cpu(s)" | awk '{print $8}' | cut -d'%' -f1)
    if [ -n "$idle" ]; then
        local used=$(echo "100 - $idle" | bc 2>/dev/null || echo "0")
        used=$(printf "%.0f" "$used" 2>/dev/null || echo "0")
        
        if [ "$used" -lt 30 ]; then
            color=$G; emoji="🟢"
        elif [ "$used" -lt 60 ]; then
            color=$Y; emoji="🟡"
        else
            color=$R; emoji="🔴"
        fi
        
        local bar=$(draw_bar "$used")
        echo -e "  ${Y}▸ CPU:${N} ${color}${bar}${N} ${color}${used}%${N} $emoji"
    else
        echo -e "  ${Y}▸ CPU:${N} Нет данных"
    fi
}

# --- Показываем память ---
show_mem() {
    local total=$(free -m | awk '/^Mem:/{print $2}')
    local used=$(free -m | awk '/^Mem:/{print $3}')
    local free=$(free -m | awk '/^Mem:/{print $4}')
    local percent=$((used * 100 / total))
    [ "$percent" -lt 0 ] && percent=0
    [ "$percent" -gt 100 ] && percent=100
    
    if [ "$percent" -lt 30 ]; then
        color=$G; emoji="🟢"
    elif [ "$percent" -lt 60 ]; then
        color=$Y; emoji="🟡"
    else
        color=$R; emoji="🔴"
    fi
    
    local bar=$(draw_bar "$percent")
    echo -e "  ${Y}▸ Память:${N} ${color}${bar}${N} ${color}${used}MB / ${total}MB (${percent}%)${N} $emoji"
    echo -e "  ${DM}    свободно: ${free}MB${N}"
}

# --- Показываем диск ---
show_disk() {
    local total=$(df -h / | awk 'NR==2{print $2}')
    local used=$(df -h / | awk 'NR==2{print $3}')
    local free=$(df -h / | awk 'NR==2{print $4}')
    local percent=$(df -h / | awk 'NR==2{print $5}' | tr -d '%')
    [ -z "$percent" ] && percent=0
    [ "$percent" -lt 0 ] && percent=0
    [ "$percent" -gt 100 ] && percent=100
    
    if [ "$percent" -lt 60 ]; then
        color=$G; emoji="🟢"
    elif [ "$percent" -lt 80 ]; then
        color=$Y; emoji="🟡"
    else
        color=$R; emoji="🔴"
    fi
    
    local bar=$(draw_bar "$percent")
    echo -e "  ${Y}▸ Диск:${N} ${color}${bar}${N} ${color}${used} / ${total} (${percent}%)${N} $emoji"
    echo -e "  ${DM}    свободно: ${free}${N}"
}

# --- Топ процессов ---
show_top() {
    echo ""
    echo -e "  ${Y}▸ Кто жрёт CPU:${N}"
    
    ps aux --sort=-%cpu 2>/dev/null | head -6 | tail -5 | while read line; do
        local cpu=$(echo "$line" | awk '{printf "%.1f", $3}')
        local mem=$(echo "$line" | awk '{printf "%.1f", $4}')
        local cmd=$(echo "$line" | awk '{for(i=11;i<=NF;i++) printf "%s ", $i; print ""}' | cut -c1-35)
        cmd=$(echo "$cmd" | sed 's/\/usr\/local\/bin\///g' | sed 's/\/usr\/bin\///g')
        
        if (( $(echo "$cpu > 10" | bc -l 2>/dev/null) )); then
            color=$R
        elif (( $(echo "$cpu > 3" | bc -l 2>/dev/null) )); then
            color=$Y
        else
            color=$N
        fi
        
        printf "    ${color}%6s%%${N}  %5s%%  %s\n" "$cpu" "$mem" "$cmd"
    done
}

# --- Процессы ---
show_processes() {
    local olc_count=$(ps aux | grep -c '[o]lcrtc' 2>/dev/null || echo "0")
    local olc_cpu=$(ps aux | grep '[o]lcrtc' 2>/dev/null | awk '{sum+=$3} END {printf "%.1f", sum}' || echo "0")
    local olc_mem=$(ps aux | grep '[o]lcrtc' 2>/dev/null | awk '{sum+=$6} END {printf "%.1f", sum/1024}' || echo "0")
    
    local xui_count=$(ps aux | grep -c '[x]-ui' 2>/dev/null || echo "0")
    local xui_cpu=$(ps aux | grep '[x]-ui' 2>/dev/null | awk '{sum+=$3} END {printf "%.1f", sum}' || echo "0")
    local xui_mem=$(ps aux | grep '[x]-ui' 2>/dev/null | awk '{sum+=$6} END {printf "%.1f", sum/1024}' || echo "0")
    
    echo ""
    if [ "$olc_count" -gt 0 ]; then
        echo -e "  ${M}▸ olcRTC:${N} ${olc_count} процессов, ${olc_cpu}% CPU, ${olc_mem}MB памяти"
    fi
    if [ "$xui_count" -gt 0 ]; then
        echo -e "  ${M}▸ x-ui:${N} ${xui_count} процессов, ${xui_cpu}% CPU, ${xui_mem}MB памяти"
    fi
    if [ "$olc_count" -eq 0 ] && [ "$xui_count" -eq 0 ]; then
        echo -e "  ${DM}▸ Специфичных процессов не найдено${N}"
    fi
}

# --- Меню ---
menu() {
    echo ""
    echo -e "  ${DM}────────────────────────────────────${N}"
    echo ""
    echo -e "  ${B}1${N}  🔄 Обновить"
    echo -e "  ${B}2${N}  📊 olcRTC — детали"
    echo -e "  ${B}3${N}  📊 x-ui — детали"
    echo -e "  ${B}4${N}  📋 История за сегодня"
    echo -e "  ${B}5${N}  🖥️  GPU — диагностика"
    echo -e "  ${B}0${N}  👋 Выйти"
    echo ""
    echo -n "  ➜ "
}

# --- Детали olcRTC ---
details_olcrtc() {
    clear_screen
    logo
    echo ""
    echo -e "  ${W}📊 olcRTC — детали${N}"
    echo -e "  ${DM}─────────────────────────${N}"
    echo ""
    
    local count=$(ps aux | grep -c '[o]lcrtc' 2>/dev/null || echo "0")
    local cpu=$(ps aux | grep '[o]lcrtc' 2>/dev/null | awk '{sum+=$3} END {printf "%.1f", sum}' || echo "0")
    local mem=$(ps aux | grep '[o]lcrtc' 2>/dev/null | awk '{sum+=$6} END {printf "%.1f", sum/1024}' || echo "0")
    
    echo -e "  ${Y}Всего:${N} $count процессов"
    echo -e "  ${Y}CPU:${N} $cpu%"
    echo -e "  ${Y}Память:${N} $mem MB"
    echo ""
    
    if [ "$count" -gt 0 ]; then
        ps aux | grep '[o]lcrtc' 2>/dev/null | grep -v grep | while read line; do
            local pid=$(echo "$line" | awk '{print $2}')
            local cpu2=$(echo "$line" | awk '{printf "%.1f", $3}')
            local mem2=$(echo "$line" | awk '{printf "%.1f", $4}')
            local rss=$(echo "$line" | awk '{printf "%.1f", $6/1024}')
            local cmd=$(echo "$line" | awk '{print $11}' | rev | cut -d'/' -f1 | rev)
            echo -e "  ${C}PID${N} $pid  ${C}CPU${N} ${cpu2}%  ${C}MEM${N} ${mem2}%  ${C}RSS${N} ${rss}MB  ${DM}$cmd${N}"
        done
    else
        echo -e "  ${DM}Нет запущенных процессов${N}"
    fi
    
    echo ""
    echo -n "  Нажми Enter чтобы вернуться... "
    read -r
}

# --- Детали x-ui ---
details_xui() {
    clear_screen
    logo
    echo ""
    echo -e "  ${W}📊 x-ui — детали${N}"
    echo -e "  ${DM}─────────────────────────${N}"
    echo ""
    
    local count=$(ps aux | grep -c '[x]-ui' 2>/dev/null || echo "0")
    local cpu=$(ps aux | grep '[x]-ui' 2>/dev/null | awk '{sum+=$3} END {printf "%.1f", sum}' || echo "0")
    local mem=$(ps aux | grep '[x]-ui' 2>/dev/null | awk '{sum+=$6} END {printf "%.1f", sum/1024}' || echo "0")
    
    echo -e "  ${Y}Всего:${N} $count процессов"
    echo -e "  ${Y}CPU:${N} $cpu%"
    echo -e "  ${Y}Память:${N} $mem MB"
    echo ""
    
    if [ "$count" -gt 0 ]; then
        ps aux | grep '[x]-ui' 2>/dev/null | grep -v grep | while read line; do
            local pid=$(echo "$line" | awk '{print $2}')
            local cpu2=$(echo "$line" | awk '{printf "%.1f", $3}')
            local mem2=$(echo "$line" | awk '{printf "%.1f", $4}')
            local rss=$(echo "$line" | awk '{printf "%.1f", $6/1024}')
            local cmd=$(echo "$line" | awk '{print $11}' | rev | cut -d'/' -f1 | rev)
            echo -e "  ${C}PID${N} $pid  ${C}CPU${N} ${cpu2}%  ${C}MEM${N} ${mem2}%  ${C}RSS${N} ${rss}MB  ${DM}$cmd${N}"
        done
    else
        echo -e "  ${DM}Нет запущенных процессов${N}"
    fi
    
    echo ""
    echo -e "  ${Y}▸ Атаки на x-ui (за 2 дня):${N}"
    local attacks=$(journalctl --since "2 days ago" -u x-ui 2>/dev/null | grep -c "TLS handshake error" 2>/dev/null || echo "0")
    if [ "$attacks" -gt 0 ]; then
        echo -e "  ${R}⚠️  $attacks попыток атак${N}"
        echo -e "  ${DM}  Топ атакующих IP:${N}"
        journalctl --since "2 days ago" -u x-ui 2>/dev/null | grep "TLS handshake error" | awk -F'from ' '{print $2}' | awk '{print $1}' | sort | uniq -c | sort -rn | head -3 | while read count ip; do
            echo -e "  ${DM}    $count раз — $ip${N}"
        done
    else
        echo -e "  ${G}✅ Атак не обнаружено${N}"
    fi
    
    echo ""
    echo -n "  Нажми Enter чтобы вернуться... "
    read -r
}

# --- История ---
show_history() {
    clear_screen
    logo
    echo ""
    echo -e "  ${W}📋 История за сегодня${N}"
    echo -e "  ${DM}─────────────────────────${N}"
    echo ""
    
    local today=$(date +%Y%m%d)
    local log="$LOG_DIR/cpu_${today}.log"
    
    if [ -f "$log" ]; then
        echo -e "  ${DM}📁 $log${N}"
        echo ""
        echo -e "  ${Y}Последние записи:${N}"
        
        tail -20 "$log" 2>/dev/null | while read line; do
            if [[ "$line" =~ ^\[.*\]$ ]]; then
                echo -e "  ${C}${line}${N}"
            elif [[ "$line" =~ "CPU:" ]]; then
                echo -e "  ${G}  $line${N}"
            elif [[ "$line" =~ "---" ]]; then
                echo -e "  ${DM}  $line${N}"
            else
                echo -e "  ${DM}  $line${N}"
            fi
        done
    else
        echo -e "  ${Y}⏳ Лог ещё не создан. Подожди 5-10 минут.${N}"
    fi
    
    echo ""
    echo -n "  Нажми Enter чтобы вернуться... "
    read -r
}

# --- Диагностика GPU ---
check_gpu() {
    clear_screen
    logo
    echo ""
    echo -e "  ${W}🖥️  GPU — диагностика${N}"
    echo -e "  ${DM}─────────────────────────${N}"
    echo ""
    
    echo -e "  ${Y}▸ /dev/dri/:${N}"
    if [ -d "/dev/dri" ]; then
        echo -e "  ${R}⚠️  /dev/dri/ существует!${N}"
        ls -la /dev/dri/ 2>/dev/null | while read line; do
            echo -e "  ${DM}  $line${N}"
        done
    else
        echo -e "  ${G}✅ /dev/dri/ не найден. GPU отключен.${N}"
    fi
    echo ""
    
    echo -e "  ${Y}▸ Ошибки virtio_gpu:${N}"
    local errors=$(dmesg -T 2>/dev/null | grep -c "virtio_gpu.*failed" 2>/dev/null || echo "0")
    if [ "$errors" -gt 0 ]; then
        echo -e "  ${R}⚠️  Найдено $errors ошибок${N}"
        dmesg -T 2>/dev/null | grep "virtio_gpu.*failed" 2>/dev/null | tail -2 | while read line; do
            echo -e "  ${DM}  $line${N}"
        done
    else
        echo -e "  ${G}✅ Ошибок нет${N}"
    fi
    echo ""
    
    echo -e "  ${Y}▸ Параметры загрузки:${N}"
    if cat /proc/cmdline 2>/dev/null | grep -q "nomodeset"; then
        echo -e "  ${G}✅ nomodeset активен${N}"
    else
        echo -e "  ${R}⚠️  nomodeset НЕ активен${N}"
        echo -e "  ${DM}  Добавь в GRUB и перезагрузись:${N}"
        echo -e "  ${DM}  sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*/& nomodeset/' /etc/default/grub${N}"
        echo -e "  ${DM}  update-grub && reboot${N}"
    fi
    
    echo ""
    echo -n "  Нажми Enter чтобы вернуться... "
    read -r
}

# --- Главный цикл ---
main() {
    while true; do
        logo
        show_cpu
        show_mem
        show_disk
        show_top
        show_processes
        menu
        read -r choice
        
        case "$choice" in
            1) continue ;;
            2) details_olcrtc ;;
            3) details_xui ;;
            4) show_history ;;
            5) check_gpu ;;
            0) clear_screen; echo -e "\n${G}👋 Пока!${N}\n"; exit 0 ;;
            *) echo -e "\n  ${R}❌ Неверный выбор${N}"; sleep 1 ;;
        esac
    done
}

# --- Запуск ---
main "$@"
