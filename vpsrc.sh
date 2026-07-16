#!/bin/bash
# ============================================================
# VPS RESOURCES CHECKER by Kvink
# Версия: 2.6 (Persistent Background Logging)
# Изменения:
#   - Фоновое логирование работает постоянно (даже при закрытом скрипте)
#   - При выходе из скрипта процессы не убиваются
#   - Проверка дубликатов процессов при запуске
# ============================================================

# --- Цвета ---
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'
C='\033[0;36m'; M='\033[0;35m'; N='\033[0m'; W='\033[1;37m'
BD='\033[1m'; DM='\033[2m'

# --- Папка для логов ---
LOG_DIR="/var/log/cpu_monitor"
mkdir -p "$LOG_DIR" 2>/dev/null

# --- Интервал записи (сек) ---
ATOP_INTERVAL=60
TEXT_INTERVAL=60

# --- Автоустановка atop ---
ensure_atop() {
    if command -v atop >/dev/null 2>&1; then return 0; fi
    echo -e "  ${Y}⏳ atop не найден, устанавливаю...${N}"
    local sudo_cmd=""
    if [ "$(id -u)" -ne 0 ]; then
        if command -v sudo >/dev/null 2>&1; then sudo_cmd="sudo"
        else echo -e "  ${R}❌ Нужны права root (или sudo) для установки atop.${N}"; return 1; fi
    fi

    if command -v apt-get >/dev/null 2>&1; then $sudo_cmd apt-get update -qq >/dev/null 2>&1; $sudo_cmd apt-get install -y atop >/dev/null 2>&1
    elif command -v dnf >/dev/null 2>&1; then $sudo_cmd dnf install -y atop >/dev/null 2>&1
    elif command -v yum >/dev/null 2>&1; then $sudo_cmd yum install -y atop >/dev/null 2>&1
    elif command -v apk >/dev/null 2>&1; then $sudo_cmd apk add --no-cache atop >/dev/null 2>&1
    elif command -v pacman >/dev/null 2>&1; then $sudo_cmd pacman -S --noconfirm atop >/dev/null 2>&1
    else echo -e "  ${R}❌ Не удалось определить пакетный менеджер.${N}"; return 1; fi

    if command -v atop >/dev/null 2>&1; then echo -e "  ${G}✅ atop успешно установлен.${N}"; return 0
    else echo -e "  ${R}❌ Установка atop не удалась.${N}"; return 1; fi
}

# --- Мониторинг в фоне через atop (постоянный) ---
start_atop_logging() {
    ensure_atop || return
    # Проверяем, не запущен ли уже atop
    if pgrep -f "atop -w $LOG_DIR/atop_" >/dev/null 2>&1; then
        echo -e "  ${DM}  ℹ️ atop уже работает в фоне${N}"
        return 0
    fi
    
    local today_log="$LOG_DIR/atop_$(date +%Y%m%d).log"
    nohup atop -w "$today_log" "$ATOP_INTERVAL" > /dev/null 2>&1 &
    disown 2>/dev/null
    echo -e "  ${G}  ✅ atop запущен в фоне (PID $!)${N}"
}

# --- Текстовый логгер (постоянный) ---
start_text_logging() {
    # Проверяем, не запущен ли уже логгер
    if pgrep -f "vpsrc_text_daemon_loop" >/dev/null 2>&1; then
        echo -e "  ${DM}  ℹ️ Текстовый логгер уже работает в фоне${N}"
        return 0
    fi
    
    (
        # Помечаем процесс уникальным именем
        exec -a "vpsrc_text_daemon_loop" bash -c '
            while true; do
                day=$(date +%Y-%m-%d)
                log="'"$LOG_DIR"'/text_${day}.log"
                {
                    echo "=========================================="
                    echo "📅 $(date "+%Y-%m-%d %H:%M:%S")"
                    echo "⏱️ Uptime: $(uptime -p 2>/dev/null || uptime | awk -F"up " "{print \$2}" | awk -F"," "{print \$1}")"
                    
                    mem_info=$(free -m | awk "/^Mem:/")
                    total=$(echo "$mem_info" | awk "{print \$2}")
                    used=$(echo "$mem_info" | awk "{print \$3}")
                    avail=$(echo "$mem_info" | awk "{print \$7}")
                    [ -z "$avail" ] && avail=$(echo "$mem_info" | awk "{print \$4}")
                    
                    echo "💾 RAM: ${used}MB / ${total}MB ($(( used * 100 / total ))%) | Avail: ${avail}MB"
                    echo "💿 Disk: $(df -h / | awk "NR==2{printf \"%s / %s (%s)\", \$3, \$2, \$5}")"
                    echo "🔝 Top-5 CPU:"
                    ps -eo pid,pcpu,pmem,comm --sort=-pcpu 2>/dev/null | head -6 | tail -5 | awk "{printf \"   PID:%-6s CPU:%-5s MEM:%-5s %s\\n\", \$1, \$2, \$3, \$4}"
                    echo "=========================================="
                } >> "$log" 2>/dev/null
                sleep '"$TEXT_INTERVAL"'
            done
        '
    ) &
    disown 2>/dev/null
    echo -e "  ${G}  ✅ Текстовый логгер запущен в фоне (PID $!)${N}"
}

# --- Авто-сжатие и очистка ---
auto_cleanup_logs() {
    find "$LOG_DIR" -maxdepth 1 -type f \( -name "text_*.log" -o -name "atop_*.log" \) -mtime +7 ! -name "*.gz" -exec gzip -9 {} \; 2>/dev/null
    find "$LOG_DIR" -maxdepth 1 -type f \( -name "*.log" -o -name "*.gz" \) -mtime +30 -delete 2>/dev/null
}

# --- 🧹 ПРИНУДИТЕЛЬНАЯ ОЧИСТКА С ПОДТВЕРЖДЕНИЕМ ---
manual_cleanup() {
    clear_screen; logo
    echo -e "  ${W}🧹 Принудительная очистка старых логов${N}"
    echo -e "  ${DM}────────────────────────────────────${N}"
    echo ""

    local count
    count=$(find "$LOG_DIR" -maxdepth 1 -type f \( -name "*.log" -o -name "*.gz" \) -mtime +30 2>/dev/null | wc -l)

    if [ "$count" -eq 0 ] || [ -z "$count" ]; then
        echo -e "  ${G}✅ Старых логов (>30 дней) не найдено. Нечего удалять.${N}"
    else
        echo -e "  ${Y}⚠️ Найдено файлов для удаления: ${count}${N}"
        echo -e "  ${DM}(Будут удалены все .log и .gz файлы старше 30 дней)${N}"
        echo ""
        echo -n "  Вы уверены, что хотите продолжить? [y/N]: "
        read -r confirm
        if [[ "$confirm" == [Yy]* ]]; then
            find "$LOG_DIR" -maxdepth 1 -type f \( -name "*.log" -o -name "*.gz" \) -mtime +30 -delete 2>/dev/null
            echo -e "  ${G}✅ Очистка завершена. Удалено файлов: $count${N}"
        else
            echo -e "  ${Y}⏸️ Операция отменена пользователем.${N}"
        fi
    fi
    echo -e "\n  ${DM}Нажми Enter чтобы вернуться в меню... ${N}"
    read -r
}

# --- 📜 ПРОСМОТР ЛОГОВ ЗА КОНКРЕТНЫЙ ДЕНЬ ---
view_specific_log() {
    clear_screen; logo
    echo -e "  ${W}📜 Просмотр текстовых логов за конкретный день${N}"
    echo -e "  ${DM}────────────────────────────────────${N}"
    echo ""

    local available_dates
    available_dates=$(find "$LOG_DIR" -maxdepth 1 -type f -name "text_*.log*" 2>/dev/null | sed -E 's/.*text_([0-9]{4}-[0-9]{2}-[0-9]{2})\.log(\.gz)?/\1/' | sort -u | tail -10)

    if [ -z "$available_dates" ]; then
        echo -e "  ${R}❌ Текстовые логи не найдены в папке ${LOG_DIR}${N}"
    else
        echo -e "  ${Y}📂 Последние доступные даты с логами:${N}"
        echo "$available_dates" | awk '{print "    • " $1}'
    fi

    echo ""
    echo -n "  Введите дату для просмотра (ГГГГ-ММ-ДД) или оставьте пустым для сегодня: "
    read -r target_date

    if [ -z "$target_date" ]; then
        target_date=$(date +%Y-%m-%d)
    fi

    if ! [[ "$target_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        echo -e "  ${R}❌ Неверный формат даты. Используйте ГГГГ-ММ-ДД (например, 2026-07-15).${N}"
    else
        local log_file="$LOG_DIR/text_${target_date}.log"
        local log_file_gz="$LOG_DIR/text_${target_date}.log.gz"

        if [ -f "$log_file" ]; then
            echo -e "  ${G}✅ Загружаю полный лог за $target_date...${N}\n"
            sleep 1
            clear_screen
            cat "$log_file"
        elif [ -f "$log_file_gz" ]; then
            echo -e "  ${Y}⚠️ Лог за $target_date архивирован (.gz). Читаю на лету...${N}\n"
            sleep 1
            clear_screen
            zcat "$log_file_gz"
        else
            echo -e "  ${R}❌ Лог за $target_date не найден.${N}"
        fi
    fi

    echo -e "\n\n  ${DM}────────────────────────────────────${N}"
    echo -e "  ${DM}Нажми Enter чтобы вернуться в меню... ${N}"
    read -r
}

# --- Очистка экрана ---
clear_screen() { printf "\033[2J\033[H"; }

# --- Логотип ---
logo() {
    clear_screen
    echo ""
    echo -e "  ${C}▸${N} ${W}VPS RESOURCES CHECKER${N} ${DM}by Kvink (v2.6)${N}"
    echo -e "  ${DM}  $(date '+%H:%M:%S')  |  $(hostname)${N}"
    echo ""
}

# --- Функция получения CPU ---
get_cpu_usage() {
    local cpu_line
    cpu_line=$(grep '^cpu ' /proc/stat 2>/dev/null)
    [ -z "$cpu_line" ] && echo "0" && return
    read -r _ user nice system idle iowait irq softirq steal _ <<< "$cpu_line"
    [ -z "$steal" ] && steal=0
    local total=$((user + nice + system + idle + iowait + irq + softirq + steal))
    [ "$total" -eq 0 ] && echo "0" && return
    local used=$((total - idle))
    echo "$((used * 100 / total))"
}

# --- Полоска ---
draw_bar() {
    local percent=$1 width=30
    local filled=$((percent * width / 100))
    [ "$filled" -gt "$width" ] && filled=$width
    [ "$filled" -lt 0 ] && filled=0
    local empty=$((width - filled))
    [ "$filled" -gt 0 ] && printf "%${filled}s" | tr ' ' '#'
    [ "$empty" -gt 0 ] && printf "%${empty}s" | tr ' ' '-'
}

# --- Показываем CPU ---
show_cpu() {
    local load=$(uptime | awk -F'load average:' '{print $2}' | xargs)
    echo -e "  ${Y}▸ Нагрузка:${N} $load"
    local used=$(get_cpu_usage)
    [ -z "$used" ] && used=0
    local used_int=$((used))
    if [ "$used_int" -lt 30 ]; then color=$G; emoji="🟢"
    elif [ "$used_int" -lt 60 ]; then color=$Y; emoji="🟡"
    else color=$R; emoji="🔴"; fi
    local bar=$(draw_bar "$used_int")
    echo -e "  ${Y}▸ CPU:${N} ${color}${bar}${N} ${color}${used}%${N} $emoji"
}

# --- Показываем память ---
show_mem() {
    local mem_data
    mem_data=$(free -m | awk '/^Mem:/ {print $2, $3, $4, $7}')
    local total=$(echo "$mem_data" | awk '{print $1}')
    local used=$(echo "$mem_data" | awk '{print $2}')
    local free_val=$(echo "$mem_data" | awk '{print $3}')
    local avail=$(echo "$mem_data" | awk '{print $4}')
    
    if [ -z "$avail" ] || [ "$avail" == "0" ]; then
        avail=$free_val
    fi

    local percent=$((used * 100 / total))
    [ "$percent" -lt 0 ] && percent=0; [ "$percent" -gt 100 ] && percent=100

    if [ "$percent" -lt 30 ]; then color=$G; emoji="🟢"
    elif [ "$percent" -lt 60 ]; then color=$Y; emoji="🟡"
    else color=$R; emoji="🔴"; fi

    local bar=$(draw_bar "$percent")
    echo -e "  ${Y}▸ Память:${N} ${color}${bar}${N} ${color}${used}MB / ${total}MB (${percent}%)${N} $emoji"
    echo -e "  ${DM}      доступно: ${avail}MB | свободно: ${free_val}MB${N}"
}

# --- Swap ---
show_swap() {
    local total used free percent
    read -r _ total used free _ <<< $(free -m | awk '/^Swap:/')
    [ "$total" -eq 0 ] && return
    percent=$((used * 100 / total))
    [ "$percent" -lt 0 ] && percent=0; [ "$percent" -gt 100 ] && percent=100
    if [ "$percent" -lt 30 ]; then color=$G; emoji="🟢"
    elif [ "$percent" -lt 60 ]; then color=$Y; emoji="🟡"
    else color=$R; emoji="🔴"; fi
    local bar=$(draw_bar "$percent")
    echo -e "  ${Y}▸ Swap:${N} ${color}${bar}${N} ${color}${used}MB / ${total}MB (${percent}%)${N} $emoji"
    echo -e "  ${DM}      свободно: ${free}MB${N}"
}

# --- Статус atop ---
show_atop_status() {
    local pid=$(pgrep -f "atop -w $LOG_DIR/atop_" 2>/dev/null | head -1)
    if [ -n "$pid" ]; then
        local today_log="$LOG_DIR/atop_$(date +%Y%m%d).log"
        local size="0"
        [ -f "$today_log" ] && size=$(du -h "$today_log" 2>/dev/null | awk '{print $1}')
        echo -e "  ${Y}▸ atop:${N} ${G}🟢 пишет лог${N} ${DM}(PID $pid, интервал ${ATOP_INTERVAL}с, файл ${size:-0})${N}"
    else
        echo -e "  ${Y}▸ atop:${N} ${R}🔴 не запущен${N}"
    fi
}

# --- Статус текстового логгера ---
show_text_log_status() {
    local pid=$(pgrep -f "vpsrc_text_daemon_loop" 2>/dev/null | head -1)
    if [ -n "$pid" ]; then
        local today_log="$LOG_DIR/text_$(date +%Y-%m-%d).log"
        local size="0"
        [ -f "$today_log" ] && size=$(du -h "$today_log" 2>/dev/null | awk '{print $1}')
        echo -e "  ${Y}▸ Текстовый лог:${N} ${G}🟢 пишет лог${N} ${DM}(PID $pid, интервал ${TEXT_INTERVAL}с, файл ${size:-0})${N}"
    else
        echo -e "  ${Y}▸ Текстовый лог:${N} ${R}🔴 не запущен${N}"
    fi
}

# --- Показываем диск ---
show_disk() {
    local total used free percent
    read -r _ total used free percent _ <<< $(df -h / | awk 'NR==2')
    percent=${percent%\%}
    [ -z "$percent" ] && percent=0
    [ "$percent" -lt 0 ] && percent=0; [ "$percent" -gt 100 ] && percent=100
    if [ "$percent" -lt 60 ]; then color=$G; emoji="🟢"
    elif [ "$percent" -lt 80 ]; then color=$Y; emoji="🟡"
    else color=$R; emoji="🔴"; fi
    local bar=$(draw_bar "$percent")
    echo -e "  ${Y}▸ Диск:${N} ${color}${bar}${N} ${color}${used} / ${total} (${percent}%)${N} $emoji"
    echo -e "  ${DM}      свободно: ${free}${N}"
}

# --- Топ процессов ---
show_top() {
    echo ""
    echo -e "  ${Y}▸ Кто жрёт CPU:${N}"
    echo -e "  ${DM}  %CPU  %MEM  ПРОЦЕСС${N}"
    ps -eo pcpu,pmem,comm --sort=-pcpu 2>/dev/null | head -6 | tail -5 | while read -r cpu mem cmd; do
        local cpu_int=${cpu%.*}
        local color=$N
        if [ "$cpu_int" -ge 10 ]; then color=$R
        elif [ "$cpu_int" -ge 3 ]; then color=$Y; fi
        cmd=$(echo "$cmd" | sed 's/\/usr\/local\/bin\///g; s/\/usr\/bin\///g' | cut -c1-25)
        printf "  ${color}%6s%%${N}  %5s%%  %s\n" "$cpu" "$mem" "$cmd"
    done
}

# --- Процессы olcRTC и x-ui ---
show_processes() {
    local olc_count=$(ps -eo comm | grep -c '[o]lcrtc' 2>/dev/null || echo "0")
    local olc_cpu=$(ps -eo pcpu,comm | grep '[o]lcrtc' 2>/dev/null | awk '{sum+=$1} END {printf "%.1f", sum}')
    local olc_mem=$(ps -eo pmem,comm | grep '[o]lcrtc' 2>/dev/null | awk '{sum+=$1} END {printf "%.1f", sum}')

    local xui_count=$(ps -eo comm | grep -c '[x]-ui' 2>/dev/null || echo "0")
    local xui_cpu=$(ps -eo pcpu,comm | grep '[x]-ui' 2>/dev/null | awk '{sum+=$1} END {printf "%.1f", sum}')
    local xui_mem=$(ps -eo pmem,comm | grep '[x]-ui' 2>/dev/null | awk '{sum+=$1} END {printf "%.1f", sum}')

    echo ""
    [ "$olc_count" -gt 0 ] && echo -e "  ${M}▸ olcRTC:${N} ${olc_count} проц., ${olc_cpu:-0}% CPU, ${olc_mem:-0}% RAM"
    [ "$xui_count" -gt 0 ] && echo -e "  ${M}▸ x-ui:${N} ${xui_count} проц., ${xui_cpu:-0}% CPU, ${xui_mem:-0}% RAM"
    [ "$olc_count" -eq 0 ] && [ "$xui_count" -eq 0 ] && echo -e "  ${DM}▸ Специфичных процессов не найдено${N}"
}

# --- Меню ---
menu() {
    echo ""
    echo -e "  ${DM}────────────────────────────────────${N}"
    echo ""
    echo -e "  ${B}1${N}  🔄 Обновить данные"
    echo -e "  ${B}2${N}  📊 olcRTC — детали процессов"
    echo -e "  ${B}3${N}  📊 x-ui — детали и атаки"
    echo -e "  ${B}4${N}  📋 История за сегодня (atop)"
    echo -e "  ${B}5${N}  🧹 Принудительная очистка логов"
    echo -e "  ${B}6${N}  📜 Текстовые логи за конкретный день"
    echo -e "  ${B}7${N}  🛑 Остановить фоновое логирование"
    echo -e "  ${B}0${N}  👋 Выйти (логи продолжат писаться)"
    echo ""
    echo -n "  ➜ "
}

# --- Остановка фонового логирования ---
stop_background_logging() {
    clear_screen; logo
    echo -e "  ${W}🛑 Остановка фонового логирования${N}"
    echo -e "  ${DM}────────────────────────────────────${N}"
    echo ""
    
    local atop_pid=$(pgrep -f "atop -w $LOG_DIR/atop_" 2>/dev/null | head -1)
    local text_pid=$(pgrep -f "vpsrc_text_daemon_loop" 2>/dev/null | head -1)
    
    if [ -z "$atop_pid" ] && [ -z "$text_pid" ]; then
        echo -e "  ${Y}ℹ️ Фоновое логирование уже остановлено${N}"
    else
        echo -e "  ${Y}⚠️ Будут остановлены следующие процессы:${N}"
        [ -n "$atop_pid" ] && echo -e "    • atop (PID $atop_pid)"
        [ -n "$text_pid" ] && echo -e "    • Текстовый логгер (PID $text_pid)"
        echo ""
        echo -n "  Вы уверены? [y/N]: "
        read -r confirm
        if [[ "$confirm" == [Yy]* ]]; then
            [ -n "$atop_pid" ] && kill "$atop_pid" 2>/dev/null && echo -e "  ${G}✅ atop остановлен${N}"
            [ -n "$text_pid" ] && kill "$text_pid" 2>/dev/null && echo -e "  ${G}✅ Текстовый логгер остановлен${N}"
            echo -e "\n  ${G}✅ Фоновое логирование остановлено${N}"
        else
            echo -e "  ${Y}⏸️ Операция отменена${N}"
        fi
    fi
    
    echo -e "\n  ${DM}Нажми Enter чтобы вернуться в меню... ${N}"
    read -r
}

# --- Детали olcRTC ---
details_olcrtc() {
    clear_screen; logo
    echo -e "  ${W}📊 olcRTC — детали${N}\n  ${DM}─────────────────────────${N}\n"
    ps -eo pid,pcpu,pmem,rss,comm | grep '[o]lcrtc' | grep -v grep | awk 'BEGIN {printf "  %-6s %-6s %-6s %-8s %s\n", "PID", "CPU%", "MEM%", "RSS(MB)", "CMD"} {printf "  %-6s %-6s %-6s %-8s %s\n", $1, $2, $3, $6/1024, $5}'
    echo -e "\n  ${DM}Нажми Enter чтобы вернуться... ${N}"; read -r
}

# --- Детали x-ui ---
details_xui() {
    clear_screen; logo
    echo -e "  ${W}📊 x-ui — детали${N}\n  ${DM}─────────────────────────${N}\n"
    ps -eo pid,pcpu,pmem,rss,comm | grep '[x]-ui' | grep -v grep | awk 'BEGIN {printf "  %-6s %-6s %-6s %-8s %s\n", "PID", "CPU%", "MEM%", "RSS(MB)", "CMD"} {printf "  %-6s %-6s %-6s %-8s %s\n", $1, $2, $3, $6/1024, $5}'
    
    echo -e "\n  ${Y}▸ Атаки на x-ui (за 2 дня):${N}"
    local attacks=$(journalctl --since "2 days ago" -u x-ui 2>/dev/null | grep -c "TLS handshake error" || echo "0")
    if [ "$attacks" -gt 0 ]; then
        echo -e "  ${R}⚠️  $attacks попыток атак${N}"
        echo -e "  ${DM}  Топ атакующих IP:${N}"
        journalctl --since "2 days ago" -u x-ui 2>/dev/null | grep "TLS handshake error" | awk -F'from ' '{print $2}' | awk '{print $1}' | sort | uniq -c | sort -rn | head -3 | awk '{printf "  ${DM}    %s раз — %s${N}\n", $1, $2}'
    else
        echo -e "  ${G}✅ Атак не обнаружено${N}"
    fi
    echo -e "\n  ${DM}Нажми Enter чтобы вернуться... ${N}"; read -r
}

# --- История (через atop) ---
show_history() {
    clear_screen; logo
    echo -e "  ${W}📋 История за сегодня (atop)${N}\n  ${DM}─────────────────────────${N}\n"
    if ! ensure_atop; then read -r; return; fi
    local today=$(date +%Y%m%d)
    local log="$LOG_DIR/atop_${today}.log"
    if [ -f "$log" ]; then
        echo -e "  ${DM}📁 $log${N}\n  ${Y}Открываю интерактивный просмотр atop...${N}\n  ${DM}  Управление: t/T — время, q — выход${N}\n"
        sleep 1; atop -r "$log"
    elif [ -f "$log.gz" ]; then
        echo -e "  ${DM}📁 $log.gz (сжатый)${N}\n  ${Y}Открываю интерактивный просмотр atop...${N}\n"
        sleep 1; zcat "$log.gz" | atop -r -
    else
        echo -e "  ${Y}⏳ Лог ещё не создан. Подожди $((ATOP_INTERVAL)) секунд.${N}"
        echo -e "\n  ${DM}Нажми Enter чтобы вернуться... ${N}"; read -r
    fi
}

# --- Главный цикл ---
main() {
    clear_screen
    echo -e "\n  ${Y}⏳ Запуск фонового логирования...${N}\n"
    
    start_atop_logging
    start_text_logging
    auto_cleanup_logs 
    
    sleep 1

    while true; do
        # Перепроверяем, не упал ли atop
        if ! pgrep -f "atop -w $LOG_DIR/atop_" >/dev/null 2>&1; then
            start_atop_logging >/dev/null 2>&1
        fi

        logo
        show_cpu
        show_mem
        show_swap
        show_disk
        show_atop_status
        show_text_log_status
        show_top
        show_processes
        menu
        read -r choice

        case "$choice" in
            1) continue ;;
            2) details_olcrtc ;;
            3) details_xui ;;
            4) show_history ;;
            5) manual_cleanup ;;
            6) view_specific_log ;;
            7) stop_background_logging ;;
            0) clear_screen; echo -e "\n${G}👋 Пока! Фоновое логирование продолжает работать.${N}\n"; exit 0 ;;
            *) echo -e "\n  ${R}❌ Неверный выбор${N}"; sleep 1 ;;
        esac
    done
}

main "$@"
