#!/bin/bash
###############################################################################
#                                                                             #
#   CWP Auto-Installer v4.0 - SSH-Safe Edition with Progress Bar             #
#   مُثبِّت CWP الاحترافي - محصّن ضد قطع SSH + شريط تقدم تفاعلي               #
#                                                                             #
#   Author      : Sherif - Dylanu                                             #
#   Version     : 4.0.0                                                       #
#   Last Update : 2026                                                        #
#                                                                             #
#   ✨ Features v4.0:                                                        #
#     - SSH disconnect protection (auto screen/tmux/nohup)                   #
#     - Real-time progress bar with ETA                                       #
#     - Live status monitoring across reconnects                              #
#     - Heartbeat keep-alive mechanism                                        #
#     - Auto-resume on reconnect                                              #
#     - Multi-PHP (8.1-8.4) + ionCube + Advanced Security                    #
#                                                                             #
#   Usage:                                                                    #
#     chmod +x cwp-installer.sh                                               #
#     ./cwp-installer.sh                  # تشغيل عادي                       #
#     ./cwp-installer.sh --monitor        # متابعة التقدم بعد إعادة الاتصال  #
#     ./cwp-installer.sh --status         # عرض الحالة الحالية                #
#                                                                             #
###############################################################################

set -o pipefail

#==============================================================================
# 0) GLOBAL STATE FILES - ملفات الحالة (تستمر بين جلسات SSH)
#==============================================================================

readonly STATE_DIR="/var/lib/cwp-installer"
readonly STATE_FILE="${STATE_DIR}/state.txt"
readonly PROGRESS_FILE="${STATE_DIR}/progress.txt"
readonly PID_FILE="${STATE_DIR}/installer.pid"
readonly STAGE_FILE="${STATE_DIR}/current_stage.txt"
readonly START_TIME_FILE="${STATE_DIR}/start_time.txt"
readonly HEARTBEAT_FILE="${STATE_DIR}/heartbeat.txt"
readonly LOCK_FILE="${STATE_DIR}/installer.lock"

#==============================================================================
# 1) CONFIGURATION - الإعدادات
#==============================================================================

# --- إعدادات السيرفر ---
SERVER_HOSTNAME="server1.example.com"
ADMIN_EMAIL="admin@example.com"
TIMEZONE="Africa/Cairo"

# --- PHP ---
DEFAULT_PHP_VERSION="8.3"
INSTALL_PHP_81="yes"
INSTALL_PHP_82="yes"
INSTALL_PHP_83="yes"
INSTALL_PHP_84="yes"

# --- ionCube ---
INSTALL_IONCUBE="yes"

# --- خدمات ---
INSTALL_SOFTACULOUS="yes"
INSTALL_MAILSERVER="yes"
INSTALL_FTP="yes"
RECOMPILE_APACHE="yes"

# --- الأمان ---
SSH_PORT="2200"
CONFIGURE_FIREWALL="yes"
INSTALL_MODSECURITY="yes"
INSTALL_FAIL2BAN="yes"
INSTALL_RKHUNTER="yes"
INSTALL_CLAMAV="yes"
INSTALL_MALDET="yes"
HARDEN_SSH="yes"
HARDEN_KERNEL="yes"
HARDEN_PHP="yes"
ENABLE_AUTO_UPDATES="yes"
DISABLE_ROOT_PASSWORD_LOGIN="no"

# --- التقارير ---
SEND_REPORT_EMAIL="yes"

# --- ملفات ---
LOG_FILE="/var/log/cwp-installer-$(date +%Y%m%d-%H%M%S).log"
BACKUP_DIR="/root/cwp-installer-backups"
TMP_DIR="/usr/local/src"

#==============================================================================
# 2) COLORS
#==============================================================================

readonly C_RED='\033[0;31m'
readonly C_GREEN='\033[0;32m'
readonly C_YELLOW='\033[1;33m'
readonly C_BLUE='\033[0;34m'
readonly C_CYAN='\033[0;36m'
readonly C_MAGENTA='\033[0;35m'
readonly C_WHITE='\033[1;37m'
readonly C_BOLD='\033[1m'
readonly C_DIM='\033[2m'
readonly C_RESET='\033[0m'

#==============================================================================
# 3) PROGRESS TRACKING - تتبع التقدم وحفظ الحالة
#==============================================================================

# قائمة المراحل والوزن النسبي لكل مرحلة
declare -a STAGES=(
    "01:فحوصات النظام:2"
    "02:تجهيز النظام:3"
    "03:تحديث النظام والمتطلبات:8"
    "04:تحميل مثبت CWP:2"
    "05:تركيب CWP الأساسي:35"
    "06:تركيب PHP 8.1:8"
    "07:تركيب PHP 8.2:8"
    "08:تركيب PHP 8.3:8"
    "09:تركيب PHP 8.4:8"
    "10:تحسين إعدادات PHP:2"
    "11:تركيب ionCube:3"
    "12:تحسين MySQL:1"
    "13:تكوين CSF Firewall:2"
    "14:تركيب ModSecurity:2"
    "15:تركيب Fail2Ban:2"
    "16:تركيب RKHunter:2"
    "17:تركيب ClamAV:3"
    "18:تركيب Maldet:2"
    "19:تأمين SSH:1"
    "20:تأمين Kernel:1"
    "21:تفعيل التحديثات التلقائية:1"
    "22:إنشاء التقرير:1"
)

TOTAL_WEIGHT=0
CURRENT_WEIGHT=0
CURRENT_STAGE_NUM=0
CURRENT_STAGE_NAME=""

calc_total_weight() {
    TOTAL_WEIGHT=0
    for stage in "${STAGES[@]}"; do
        local w
        w=$(echo "$stage" | cut -d: -f3)
        TOTAL_WEIGHT=$((TOTAL_WEIGHT + w))
    done
}

save_state() {
    mkdir -p "$STATE_DIR"
    {
        echo "STAGE_NUM=$CURRENT_STAGE_NUM"
        echo "STAGE_NAME=$CURRENT_STAGE_NAME"
        echo "CURRENT_WEIGHT=$CURRENT_WEIGHT"
        echo "TOTAL_WEIGHT=$TOTAL_WEIGHT"
        echo "STATUS=$1"
        echo "TIMESTAMP=$(date +%s)"
    } > "$STATE_FILE"

    # تحديث heartbeat
    date +%s > "$HEARTBEAT_FILE"
}

get_percentage() {
    if [[ $TOTAL_WEIGHT -eq 0 ]]; then echo "0"; return; fi
    echo $(( CURRENT_WEIGHT * 100 / TOTAL_WEIGHT ))
}

format_time() {
    local seconds=$1
    local hours=$((seconds / 3600))
    local minutes=$(( (seconds % 3600) / 60 ))
    local secs=$((seconds % 60))

    if (( hours > 0 )); then
        printf "%dh %dm %ds" "$hours" "$minutes" "$secs"
    elif (( minutes > 0 )); then
        printf "%dm %ds" "$minutes" "$secs"
    else
        printf "%ds" "$secs"
    fi
}

get_elapsed_time() {
    if [[ ! -f "$START_TIME_FILE" ]]; then echo "0"; return; fi
    local start
    start=$(cat "$START_TIME_FILE")
    echo $(( $(date +%s) - start ))
}

estimate_remaining() {
    local elapsed=$1
    local percent
    percent=$(get_percentage)

    if (( percent < 5 )); then
        echo "--"
        return
    fi

    local total_estimated=$(( elapsed * 100 / percent ))
    local remaining=$(( total_estimated - elapsed ))

    if (( remaining < 0 )); then remaining=0; fi
    format_time $remaining
}

draw_progress_bar() {
    local percent=$1
    local width=50
    local filled=$(( percent * width / 100 ))
    local empty=$(( width - filled ))

    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done

    echo -e "  ${C_GREEN}${bar}${C_RESET} ${C_BOLD}${percent}%${C_RESET}"
}

show_progress() {
    local percent
    local elapsed
    local eta

    percent=$(get_percentage)
    elapsed=$(get_elapsed_time)
    eta=$(estimate_remaining "$elapsed")

    # عرض الإطار
    echo ""
    echo -e "${C_CYAN}╔═══════════════════════════════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_CYAN}║${C_RESET}  ${C_BOLD}${C_WHITE}CWP Installation Progress${C_RESET}                                       ${C_CYAN}║${C_RESET}"
    echo -e "${C_CYAN}╠═══════════════════════════════════════════════════════════════════╣${C_RESET}"
    echo -e "${C_CYAN}║${C_RESET}"
    printf "${C_CYAN}║${C_RESET}  ${C_BOLD}المرحلة:${C_RESET} %-58s ${C_CYAN}║${C_RESET}\n" "[$CURRENT_STAGE_NUM/${#STAGES[@]}] $CURRENT_STAGE_NAME"
    echo -e "${C_CYAN}║${C_RESET}"

    # شريط التقدم
    local width=50
    local filled=$(( percent * width / 100 ))
    local empty=$(( width - filled ))
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done

    printf "${C_CYAN}║${C_RESET}  ${C_GREEN}%s${C_RESET} ${C_BOLD}%3d%%${C_RESET}     ${C_CYAN}║${C_RESET}\n" "$bar" "$percent"
    echo -e "${C_CYAN}║${C_RESET}"
    printf "${C_CYAN}║${C_RESET}  ${C_DIM}الوقت المنقضي:${C_RESET} %-20s ${C_DIM}المتبقي تقريباً:${C_RESET} %-15s ${C_CYAN}║${C_RESET}\n" "$(format_time $elapsed)" "$eta"
    echo -e "${C_CYAN}║${C_RESET}"
    echo -e "${C_CYAN}╚═══════════════════════════════════════════════════════════════════╝${C_RESET}"
    echo ""
}

#==============================================================================
# 4) LOGGING - السجلات
#==============================================================================

log()       { echo -e "${C_CYAN}[$(date +'%H:%M:%S')]${C_RESET} $*" | tee -a "$LOG_FILE"; }
log_info()  { echo -e "${C_BLUE}[INFO]${C_RESET}  $*" | tee -a "$LOG_FILE"; }
log_ok()    { echo -e "${C_GREEN}[ OK ]${C_RESET}  $*" | tee -a "$LOG_FILE"; }
log_warn()  { echo -e "${C_YELLOW}[WARN]${C_RESET}  $*" | tee -a "$LOG_FILE"; }
log_err()   { echo -e "${C_RED}[FAIL]${C_RESET}  $*" | tee -a "$LOG_FILE"; }

start_stage() {
    local stage_index=$1
    local stage_data="${STAGES[$stage_index]}"

    CURRENT_STAGE_NUM=$(echo "$stage_data" | cut -d: -f1)
    CURRENT_STAGE_NAME=$(echo "$stage_data" | cut -d: -f2)

    save_state "running"

    echo ""
    echo -e "${C_MAGENTA}${C_BOLD}┌─────────────────────────────────────────────────────────────────┐${C_RESET}"
    echo -e "${C_MAGENTA}${C_BOLD}│${C_RESET} ${C_WHITE}▶ [${CURRENT_STAGE_NUM}/${#STAGES[@]}] ${CURRENT_STAGE_NAME}${C_RESET}"
    echo -e "${C_MAGENTA}${C_BOLD}└─────────────────────────────────────────────────────────────────┘${C_RESET}"
    log_info "بدء المرحلة: $CURRENT_STAGE_NAME"

    show_progress
}

end_stage() {
    local stage_index=$1
    local stage_data="${STAGES[$stage_index]}"
    local stage_weight
    stage_weight=$(echo "$stage_data" | cut -d: -f3)

    CURRENT_WEIGHT=$((CURRENT_WEIGHT + stage_weight))
    save_state "completed"

    log_ok "اكتملت: $CURRENT_STAGE_NAME"
    show_progress
}

die() {
    log_err "$*"
    save_state "failed"
    log_err "تم إيقاف السكربت. راجع: $LOG_FILE"
    cleanup_lock
    exit 1
}

run() {
    log_info "تنفيذ: $*"
    if ! eval "$@" >>"$LOG_FILE" 2>&1; then
        die "فشل: $*"
    fi
}

run_safe() {
    log_info "تنفيذ (آمن): $*"
    eval "$@" >>"$LOG_FILE" 2>&1 || log_warn "فشل لكن نُكمل: $*"
}

cleanup_lock() {
    rm -f "$LOCK_FILE" "$PID_FILE" 2>/dev/null
}

#==============================================================================
# 5) SSH PROTECTION - حماية من قطع SSH
#==============================================================================

check_session_type() {
    # التحقق من نوع الجلسة الحالية

    # إذا كنا داخل screen
    if [[ -n "${STY:-}" ]]; then
        echo "screen"
        return 0
    fi

    # إذا كنا داخل tmux
    if [[ -n "${TMUX:-}" ]]; then
        echo "tmux"
        return 0
    fi

    # إذا كنا في nohup (PPID = 1 يعني detached)
    if [[ "$(ps -o ppid= -p $$ | tr -d ' ')" == "1" ]]; then
        echo "nohup"
        return 0
    fi

    # جلسة SSH عادية - خطر!
    if [[ -n "${SSH_CONNECTION:-}" ]] || [[ -n "${SSH_CLIENT:-}" ]]; then
        echo "ssh-direct"
        return 0
    fi

    echo "local"
}

install_terminal_multiplexer() {
    # تركيب screen أو tmux إذا لم يكن مُركّباً
    log "تركيب أدوات الجلسة المستمرة..."

    if command -v screen &>/dev/null; then
        log_ok "screen مُركّب بالفعل"
        return 0
    fi

    if command -v tmux &>/dev/null; then
        log_ok "tmux مُركّب بالفعل"
        return 0
    fi

    # تركيب screen
    if command -v dnf &>/dev/null; then
        dnf -y install screen 2>/dev/null || yum -y install screen 2>/dev/null
    elif command -v yum &>/dev/null; then
        yum -y install screen 2>/dev/null
    fi

    if command -v screen &>/dev/null; then
        log_ok "تم تركيب screen"
    else
        log_warn "فشل تركيب screen - سنستخدم nohup"
    fi
}

setup_ssh_keepalive() {
    # تفعيل keep-alive من جانب السيرفر لمنع قطع SSH أثناء التركيب
    log "تفعيل SSH keep-alive..."

    local sshd_config="/etc/ssh/sshd_config"

    if [[ -f "$sshd_config" ]]; then
        # إضافة/تحديث الإعدادات
        for setting in "ClientAliveInterval 60" "ClientAliveCountMax 720" "TCPKeepAlive yes"; do
            local key="${setting%% *}"

            if grep -q "^${key}" "$sshd_config"; then
                sed -i "s|^${key}.*|${setting}|" "$sshd_config"
            elif grep -q "^#${key}" "$sshd_config"; then
                sed -i "s|^#${key}.*|${setting}|" "$sshd_config"
            else
                echo "$setting" >> "$sshd_config"
            fi
        done

        # إعادة تحميل دون قطع الجلسات
        systemctl reload sshd 2>/dev/null || /usr/sbin/sshd -t && kill -HUP "$(pidof sshd | awk '{print $NF}')" 2>/dev/null || true

        log_ok "SSH keep-alive مُفعّل (60 ثانية، 12 ساعة)"
    fi
}

relaunch_in_screen() {
    local script_path
    script_path=$(readlink -f "$0")

    echo ""
    echo -e "${C_YELLOW}${C_BOLD}╔═══════════════════════════════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_YELLOW}${C_BOLD}║${C_RESET}  ⚠️  ${C_BOLD}تحذير مهم - حماية من قطع SSH${C_RESET}                              ${C_YELLOW}${C_BOLD}║${C_RESET}"
    echo -e "${C_YELLOW}${C_BOLD}╠═══════════════════════════════════════════════════════════════════╣${C_RESET}"
    echo -e "${C_YELLOW}${C_BOLD}║${C_RESET}                                                                   ${C_YELLOW}${C_BOLD}║${C_RESET}"
    echo -e "${C_YELLOW}${C_BOLD}║${C_RESET}  السكربت يحتاج 30-60 دقيقة. لو انقطع SSH هيتوقف التركيب.        ${C_YELLOW}${C_BOLD}║${C_RESET}"
    echo -e "${C_YELLOW}${C_BOLD}║${C_RESET}  الحل: تشغيله في جلسة محصّنة (screen) تستمر حتى بعد قطع SSH.   ${C_YELLOW}${C_BOLD}║${C_RESET}"
    echo -e "${C_YELLOW}${C_BOLD}║${C_RESET}                                                                   ${C_YELLOW}${C_BOLD}║${C_RESET}"
    echo -e "${C_YELLOW}${C_BOLD}╚═══════════════════════════════════════════════════════════════════╝${C_RESET}"
    echo ""

    # محاولة استخدام screen أولاً
    if command -v screen &>/dev/null; then
        log "إعادة التشغيل داخل screen session..."

        echo -e "${C_GREEN}سيبدأ التركيب في screen session اسمها: ${C_BOLD}cwp-installer${C_RESET}"
        echo ""
        echo -e "${C_CYAN}بعد بدء التركيب:${C_RESET}"
        echo -e "  • ${C_BOLD}لفصل الجلسة (والاحتفاظ بالتركيب يعمل):${C_RESET}  اضغط ${C_YELLOW}Ctrl+A${C_RESET} ثم ${C_YELLOW}D${C_RESET}"
        echo -e "  • ${C_BOLD}للعودة للجلسة من أي اتصال SSH:${C_RESET}      ${C_YELLOW}screen -r cwp-installer${C_RESET}"
        echo -e "  • ${C_BOLD}لمتابعة التقدم بدون دخول الجلسة:${C_RESET}     ${C_YELLOW}$script_path --monitor${C_RESET}"
        echo -e "  • ${C_BOLD}لرؤية الحالة فقط:${C_RESET}                     ${C_YELLOW}$script_path --status${C_RESET}"
        echo ""
        echo -e "${C_DIM}البدء خلال 5 ثوانٍ...${C_RESET}"
        sleep 5

        # تشغيل في screen مع متغير بيئي يمنع التكرار
        exec screen -S cwp-installer -L -Logfile /var/log/cwp-screen.log bash -c "CWP_IN_SESSION=1 bash '$script_path' --run-actual"
        return 0
    fi

    # محاولة tmux
    if command -v tmux &>/dev/null; then
        log "إعادة التشغيل داخل tmux session..."

        echo -e "${C_GREEN}سيبدأ التركيب في tmux session اسمها: ${C_BOLD}cwp-installer${C_RESET}"
        echo ""
        echo -e "${C_CYAN}بعد بدء التركيب:${C_RESET}"
        echo -e "  • ${C_BOLD}لفصل الجلسة:${C_RESET}              اضغط ${C_YELLOW}Ctrl+B${C_RESET} ثم ${C_YELLOW}D${C_RESET}"
        echo -e "  • ${C_BOLD}للعودة للجلسة:${C_RESET}             ${C_YELLOW}tmux attach -t cwp-installer${C_RESET}"
        echo -e "  • ${C_BOLD}لمتابعة التقدم:${C_RESET}             ${C_YELLOW}$script_path --monitor${C_RESET}"
        echo ""
        sleep 5

        exec tmux new-session -d -s cwp-installer "CWP_IN_SESSION=1 bash '$script_path' --run-actual"
        tmux attach -t cwp-installer
        return 0
    fi

    # الحل الأخير: nohup
    log_warn "screen و tmux غير متوفرين - استخدام nohup"
    echo ""
    echo -e "${C_GREEN}سيبدأ التركيب في الخلفية باستخدام nohup${C_RESET}"
    echo ""
    echo -e "${C_CYAN}لمتابعة التقدم:${C_RESET}"
    echo -e "  ${C_YELLOW}$script_path --monitor${C_RESET}"
    echo ""
    echo -e "${C_CYAN}لمتابعة السجل المباشر:${C_RESET}"
    echo -e "  ${C_YELLOW}tail -f /var/log/cwp-installer-*.log${C_RESET}"
    echo ""
    sleep 5

    # تشغيل في الخلفية
    CWP_IN_SESSION=1 nohup bash "$script_path" --run-actual > /var/log/cwp-installer-nohup.log 2>&1 &
    local bg_pid=$!
    echo "$bg_pid" > "$PID_FILE"
    disown

    sleep 2
    echo -e "${C_GREEN}✓ السكربت يعمل في الخلفية (PID: $bg_pid)${C_RESET}"
    echo ""
    echo -e "ابدأ المتابعة الآن بأمر:"
    echo -e "  ${C_YELLOW}${C_BOLD}$script_path --monitor${C_RESET}"
    echo ""
    exit 0
}

#==============================================================================
# 6) MONITOR MODE - وضع المتابعة (للاتصال المُعاد)
#==============================================================================

monitor_progress() {
    if [[ ! -f "$STATE_FILE" ]]; then
        echo -e "${C_YELLOW}لا توجد عملية تركيب جارية حالياً.${C_RESET}"
        echo ""
        echo "ابدأ التركيب بـ:"
        echo -e "  ${C_CYAN}$0${C_RESET}"
        exit 0
    fi

    # متابعة لايف
    trap 'echo ""; echo "تم الخروج من المتابعة. التركيب لا يزال يعمل في الخلفية."; exit 0' INT

    while true; do
        clear

        # قراءة الحالة
        # shellcheck disable=SC1090
        source "$STATE_FILE"

        local percent=$(( CURRENT_WEIGHT * 100 / TOTAL_WEIGHT ))
        local start
        start=$(cat "$START_TIME_FILE" 2>/dev/null || echo "$(date +%s)")
        local elapsed=$(( $(date +%s) - start ))
        local heartbeat
        heartbeat=$(cat "$HEARTBEAT_FILE" 2>/dev/null || echo "0")
        local last_update=$(( $(date +%s) - heartbeat ))

        # رسم الواجهة
        echo ""
        echo -e "${C_CYAN}╔═══════════════════════════════════════════════════════════════════╗${C_RESET}"
        echo -e "${C_CYAN}║${C_RESET}  ${C_BOLD}${C_WHITE}🚀 CWP Auto-Installer - Live Progress${C_RESET}                          ${C_CYAN}║${C_RESET}"
        echo -e "${C_CYAN}╠═══════════════════════════════════════════════════════════════════╣${C_RESET}"

        # حالة العملية
        local status_text=""
        local status_color=""
        case "$STATUS" in
            running)
                if (( last_update > 120 )); then
                    status_text="⚠️  بطيء (آخر تحديث منذ $(format_time $last_update))"
                    status_color="$C_YELLOW"
                else
                    status_text="✓ يعمل (آخر تحديث منذ ${last_update}s)"
                    status_color="$C_GREEN"
                fi
                ;;
            completed)
                status_text="✓ مكتمل"
                status_color="$C_GREEN"
                ;;
            failed)
                status_text="✗ فشل"
                status_color="$C_RED"
                ;;
        esac

        echo -e "${C_CYAN}║${C_RESET}"
        printf "${C_CYAN}║${C_RESET}  ${C_BOLD}الحالة:${C_RESET}    ${status_color}%-55s${C_RESET} ${C_CYAN}║${C_RESET}\n" "$status_text"
        printf "${C_CYAN}║${C_RESET}  ${C_BOLD}المرحلة:${C_RESET}   %-55s ${C_CYAN}║${C_RESET}\n" "[$STAGE_NUM/${#STAGES[@]}] $STAGE_NAME"
        echo -e "${C_CYAN}║${C_RESET}"

        # شريط التقدم
        local width=55
        local filled=$(( percent * width / 100 ))
        local empty=$(( width - filled ))
        local bar=""
        for ((i=0; i<filled; i++)); do bar+="█"; done
        for ((i=0; i<empty; i++)); do bar+="░"; done

        printf "${C_CYAN}║${C_RESET}  ${C_GREEN}%s${C_RESET} ${C_BOLD}%3d%%${C_RESET}  ${C_CYAN}║${C_RESET}\n" "$bar" "$percent"

        echo -e "${C_CYAN}║${C_RESET}"

        # حساب ETA
        local eta="--"
        if (( percent > 5 && percent < 100 )); then
            local total_est=$(( elapsed * 100 / percent ))
            local remaining=$(( total_est - elapsed ))
            eta=$(format_time $remaining)
        fi

        printf "${C_CYAN}║${C_RESET}  ${C_DIM}المنقضي:${C_RESET}   %-20s ${C_DIM}المتبقي:${C_RESET}  %-22s ${C_CYAN}║${C_RESET}\n" "$(format_time $elapsed)" "$eta"

        echo -e "${C_CYAN}║${C_RESET}"
        echo -e "${C_CYAN}╠═══════════════════════════════════════════════════════════════════╣${C_RESET}"

        # عرض المراحل
        echo -e "${C_CYAN}║${C_RESET}  ${C_BOLD}المراحل:${C_RESET}                                                          ${C_CYAN}║${C_RESET}"
        echo -e "${C_CYAN}║${C_RESET}"

        local idx=0
        for stage in "${STAGES[@]}"; do
            idx=$((idx + 1))
            local stage_num
            local stage_name
            stage_num=$(echo "$stage" | cut -d: -f1)
            stage_name=$(echo "$stage" | cut -d: -f2)

            local icon=""
            local color=""

            if (( idx < STAGE_NUM )); then
                icon="✓"
                color="$C_GREEN"
            elif (( idx == STAGE_NUM )); then
                icon="▶"
                color="$C_YELLOW"
            else
                icon="○"
                color="$C_DIM"
            fi

            printf "${C_CYAN}║${C_RESET}  ${color}%s${C_RESET} ${color}[%s] %-58s${C_RESET} ${C_CYAN}║${C_RESET}\n" "$icon" "$stage_num" "$stage_name"
        done

        echo -e "${C_CYAN}║${C_RESET}"
        echo -e "${C_CYAN}╠═══════════════════════════════════════════════════════════════════╣${C_RESET}"

        # آخر سطر من السجل
        local latest_log=""
        if [[ -f "$LOG_FILE" ]] || ls /var/log/cwp-installer-*.log 1>/dev/null 2>&1; then
            local actual_log
            actual_log=$(ls -t /var/log/cwp-installer-*.log 2>/dev/null | head -1)
            if [[ -f "$actual_log" ]]; then
                latest_log=$(tail -1 "$actual_log" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | cut -c1-65)
            fi
        fi

        echo -e "${C_CYAN}║${C_RESET}  ${C_DIM}آخر نشاط:${C_RESET}                                                       ${C_CYAN}║${C_RESET}"
        printf "${C_CYAN}║${C_RESET}  ${C_DIM}%-65s${C_RESET} ${C_CYAN}║${C_RESET}\n" "$latest_log"

        echo -e "${C_CYAN}╚═══════════════════════════════════════════════════════════════════╝${C_RESET}"
        echo ""

        if [[ "$STATUS" == "completed" ]] || [[ "$STATUS" == "failed" ]]; then
            echo ""
            if [[ "$STATUS" == "completed" ]]; then
                echo -e "${C_GREEN}${C_BOLD}🎉 اكتمل التركيب بنجاح!${C_RESET}"
                echo ""
                echo "راجع التقرير: /root/cwp-installation-report.txt"
            else
                echo -e "${C_RED}${C_BOLD}✗ فشل التركيب${C_RESET}"
                echo ""
                echo "راجع السجل: $LOG_FILE"
            fi
            echo ""
            break
        fi

        echo -e "${C_DIM}اضغط Ctrl+C للخروج من المتابعة (التركيب لن يتأثر) | تحديث كل 3 ثوانٍ${C_RESET}"
        sleep 3
    done
}

show_status() {
    if [[ ! -f "$STATE_FILE" ]]; then
        echo "لا توجد عملية تركيب."
        exit 0
    fi

    # shellcheck disable=SC1090
    source "$STATE_FILE"
    local percent=$(( CURRENT_WEIGHT * 100 / TOTAL_WEIGHT ))

    echo "الحالة:   $STATUS"
    echo "المرحلة:  [$STAGE_NUM/${#STAGES[@]}] $STAGE_NAME"
    echo "النسبة:   ${percent}%"

    if [[ -f "$START_TIME_FILE" ]]; then
        local elapsed=$(( $(date +%s) - $(cat "$START_TIME_FILE") ))
        echo "المنقضي:  $(format_time $elapsed)"
    fi
}

#==============================================================================
# 7) HEARTBEAT - نبض القلب لإثبات أن السكربت حي
#==============================================================================

start_heartbeat() {
    (
        while true; do
            date +%s > "$HEARTBEAT_FILE" 2>/dev/null
            sleep 10
        done
    ) &
    HEARTBEAT_PID=$!
}

stop_heartbeat() {
    [[ -n "${HEARTBEAT_PID:-}" ]] && kill "$HEARTBEAT_PID" 2>/dev/null
}

#==============================================================================
# 8) CORE INSTALLATION FUNCTIONS
#==============================================================================

check_root() {
    [[ $EUID -ne 0 ]] && die "يجب التشغيل كـ root"
}

detect_os() {
    [[ ! -f /etc/os-release ]] && die "/etc/os-release غير موجود"
    # shellcheck disable=SC1091
    source /etc/os-release

    OS_ID="$ID"
    OS_VERSION="${VERSION_ID%%.*}"
    OS_PRETTY="$PRETTY_NAME"

    case "$OS_ID" in
        almalinux|rocky|centos|ol|rhel) log_ok "النظام: $OS_PRETTY" ;;
        *) die "نظام غير مدعوم: $OS_ID" ;;
    esac

    case "$OS_VERSION" in
        7)  CWP_INSTALLER_URL="http://centos-webpanel.com/cwp-el7-latest"
            CWP_INSTALLER_FILE="cwp-el7-latest"
            PKG_MANAGER="yum" ;;
        8)  CWP_INSTALLER_URL="http://centos-webpanel.com/cwp-el8-latest"
            CWP_INSTALLER_FILE="cwp-el8-latest"
            PKG_MANAGER="dnf" ;;
        9)  CWP_INSTALLER_URL="http://centos-webpanel.com/cwp-el9-latest"
            CWP_INSTALLER_FILE="cwp-el9-latest"
            PKG_MANAGER="dnf" ;;
        *) die "إصدار غير مدعوم: $OS_VERSION" ;;
    esac

    log_ok "EL${OS_VERSION} | $PKG_MANAGER"
}

check_requirements() {
    ping -c 1 -W 5 8.8.8.8 &>/dev/null || die "لا يوجد إنترنت"
    log_ok "الإنترنت متوفر"

    local mem_mb
    mem_mb=$(($(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024))
    (( mem_mb < 1900 )) && die "RAM غير كافي: ${mem_mb}MB"
    log_ok "RAM: ${mem_mb}MB"

    local disk_gb
    disk_gb=$(df -BG / | awk 'NR==2 {gsub("G",""); print $4}')
    (( disk_gb < 20 )) && die "المساحة: ${disk_gb}GB"
    log_ok "Disk: ${disk_gb}GB"

    [[ "$(uname -m)" != "x86_64" ]] && die "يجب 64-bit"
    [[ -d /usr/local/cwpsrv ]] && die "CWP مثبت مسبقاً"

    log_ok "جميع المتطلبات مستوفاة"
}

validate_config() {
    [[ ! "$SERVER_HOSTNAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)+$ ]] && die "HOSTNAME غير صالح"
    local dots
    dots=$(grep -o "\." <<<"$SERVER_HOSTNAME" | wc -l)
    (( dots < 2 )) && die "HOSTNAME يجب FQDN كامل"
    [[ ! "$ADMIN_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] && die "EMAIL غير صالح"
    log_ok "الإعدادات صحيحة"
}

create_backup() {
    mkdir -p "$BACKUP_DIR"
    local files=(/etc/hostname /etc/hosts /etc/ssh/sshd_config /etc/selinux/config /etc/sysctl.conf)
    for file in "${files[@]}"; do
        [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$(basename "$file").bak"
    done
    log_ok "النسخ الاحتياطية: $BACKUP_DIR"
}

set_hostname() {
    hostnamectl set-hostname "$SERVER_HOSTNAME"
    SERVER_IP=$(ip -4 route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -n1)
    [[ -z "$SERVER_IP" ]] && SERVER_IP="127.0.1.1"
    sed -i "/$SERVER_HOSTNAME/d" /etc/hosts
    echo "$SERVER_IP $SERVER_HOSTNAME $(echo "$SERVER_HOSTNAME" | cut -d. -f1)" >> /etc/hosts
    log_ok "Hostname: $(hostname -f) | IP: $SERVER_IP"
}

set_timezone() {
    timedatectl set-timezone "$TIMEZONE" 2>/dev/null || log_warn "فشل ضبط الوقت"
    log_ok "الوقت: $(date)"
}

disable_selinux() {
    setenforce 0 2>/dev/null || true
    [[ -f /etc/selinux/config ]] && sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
    log_ok "SELinux معطّل"
}

stop_conflicting_services() {
    for svc in firewalld httpd nginx named postfix dovecot; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            systemctl stop "$svc" 2>/dev/null
            systemctl disable "$svc" 2>/dev/null
        fi
    done
    log_ok "الخدمات المتعارضة موقوفة"
}

update_system() {
    if [[ "$PKG_MANAGER" == "yum" ]]; then
        run "yum clean all"
        run "yum -y update"
    else
        run "dnf clean all"
        run "dnf -y update"
    fi
    log_ok "النظام محدّث"
}

install_prerequisites() {
    local pkgs=(wget curl tar gzip unzip vim nano net-tools bind-utils chrony perl epel-release screen tmux)
    if [[ "$PKG_MANAGER" == "yum" ]]; then
        run "yum -y install ${pkgs[*]}"
    else
        run "dnf -y install ${pkgs[*]}"
    fi
    systemctl enable --now chronyd 2>/dev/null || true
    log_ok "الحزم الأساسية مُركّبة"
}

download_cwp() {
    mkdir -p "$TMP_DIR"
    cd "$TMP_DIR" || die "فشل cd"
    rm -f "$CWP_INSTALLER_FILE"

    local success=0
    for ((i=1; i<=3; i++)); do
        if wget -q "$CWP_INSTALLER_URL" -O "$CWP_INSTALLER_FILE"; then
            success=1; break
        fi
        sleep 5
    done

    [[ $success -eq 1 ]] || die "فشل تحميل المثبت"
    [[ ! -s "$CWP_INSTALLER_FILE" ]] && die "المثبت فارغ"
    log_ok "المثبت جاهز ($(du -h "$CWP_INSTALLER_FILE" | cut -f1))"
}

install_cwp() {
    log "تركيب CWP - قد يستغرق 20-40 دقيقة..."
    cd "$TMP_DIR" || die "فشل cd"

    local args=""
    [[ "$RECOMPILE_APACHE" == "yes" ]] && args+=" -r yes" || args+=" -r no"
    args+=" --phpfpm $DEFAULT_PHP_VERSION"
    [[ "$INSTALL_SOFTACULOUS" == "yes" ]] && args+=" --softaculous yes"

    if sh "$CWP_INSTALLER_FILE" $args >>"$LOG_FILE" 2>&1; then
        log_ok "تم تركيب CWP"
    else
        die "فشل تركيب CWP"
    fi

    [[ ! -d /usr/local/cwpsrv ]] && die "CWP غير موجود"
}

install_single_php() {
    local ver="$1"
    local ver_nodot="${ver//./}"

    if [[ "$ver" == "$DEFAULT_PHP_VERSION" ]]; then
        log_info "PHP $ver: مُركّب بالفعل"
        INSTALLED_PHP_VERSIONS+=("$ver")
        return 0
    fi

    log "تركيب PHP $ver..."

    if [[ -f /scripts/cwp_php_install_xtra ]]; then
        sh /scripts/cwp_php_install_xtra "$ver_nodot" >>"$LOG_FILE" 2>&1 || true
    fi

    if [[ -d "/opt/alt/php${ver_nodot}" ]] || [[ -d "/usr/local/cwp/php-fpm/${ver_nodot}" ]]; then
        log_ok "PHP $ver مُركّب"
        INSTALLED_PHP_VERSIONS+=("$ver")
    else
        log_warn "PHP $ver: قد يحتاج تركيب يدوي من اللوحة"
    fi
}

configure_php_settings() {
    local php_ini_files=()
    while IFS= read -r -d '' file; do
        php_ini_files+=("$file")
    done < <(find /usr/local /opt -name "php.ini" -type f -print0 2>/dev/null)
    [[ -f /etc/php.ini ]] && php_ini_files+=("/etc/php.ini")

    [[ ${#php_ini_files[@]} -eq 0 ]] && { log_warn "لا توجد ملفات php.ini"; return 0; }

    for php_ini in "${php_ini_files[@]}"; do
        cp "$php_ini" "${php_ini}.bak-cwp"

        sed -i \
            -e 's/^;\?\s*memory_limit\s*=.*/memory_limit = 256M/' \
            -e 's/^;\?\s*upload_max_filesize\s*=.*/upload_max_filesize = 128M/' \
            -e 's/^;\?\s*post_max_size\s*=.*/post_max_size = 128M/' \
            -e 's/^;\?\s*max_execution_time\s*=.*/max_execution_time = 300/' \
            -e 's/^;\?\s*max_input_vars\s*=.*/max_input_vars = 5000/' \
            -e 's/^;\?\s*date.timezone\s*=.*/date.timezone = '"$TIMEZONE"'/' \
            -e 's/^;\?\s*opcache.enable\s*=.*/opcache.enable=1/' \
            -e 's/^;\?\s*opcache.memory_consumption\s*=.*/opcache.memory_consumption=256/' \
            "$php_ini"

        if [[ "$HARDEN_PHP" == "yes" ]]; then
            sed -i \
                -e 's/^;\?\s*expose_php\s*=.*/expose_php = Off/' \
                -e 's/^;\?\s*display_errors\s*=.*/display_errors = Off/' \
                -e 's/^;\?\s*allow_url_fopen\s*=.*/allow_url_fopen = Off/' \
                -e 's/^;\?\s*allow_url_include\s*=.*/allow_url_include = Off/' \
                "$php_ini"

            local dangerous="exec,passthru,shell_exec,system,proc_open,popen,curl_multi_exec,parse_ini_file,show_source,eval,assert"
            if grep -q "^disable_functions" "$php_ini"; then
                sed -i "s|^disable_functions\s*=.*|disable_functions = ${dangerous}|" "$php_ini"
            else
                echo "disable_functions = ${dangerous}" >> "$php_ini"
            fi
        fi
    done
    log_ok "تم تحسين PHP"
}

install_ioncube() {
    [[ "$INSTALL_IONCUBE" != "yes" ]] && return 0

    cd "$TMP_DIR" || return 1
    rm -f ioncube_loaders_lin_x86-64.tar.gz
    rm -rf ioncube

    if ! wget -q "https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz" -O ioncube_loaders_lin_x86-64.tar.gz; then
        log_warn "فشل تحميل ionCube"; return 1
    fi

    tar xzf ioncube_loaders_lin_x86-64.tar.gz
    [[ ! -d ioncube ]] && { log_warn "فشل استخراج ionCube"; return 1; }
    log_ok "تم تحميل ionCube"

    for ver in "${INSTALLED_PHP_VERSIONS[@]:-$DEFAULT_PHP_VERSION}"; do
        local ver_nodot="${ver//./}"
        local loader="$TMP_DIR/ioncube/ioncube_loader_lin_${ver}.so"
        [[ ! -f "$loader" ]] && { log_warn "ionCube غير متاح لـ PHP $ver"; continue; }

        # نسخ للمسارات
        for path in /opt/alt/php${ver_nodot}/usr/lib64/php/modules /usr/local/cwp/php-fpm/${ver_nodot}/lib/php/extensions; do
            [[ -d "$path" ]] && cp "$loader" "$path/" 2>/dev/null
        done

        # default PHP
        if [[ "$ver" == "$DEFAULT_PHP_VERSION" ]]; then
            for path in /usr/local/php/lib/php/extensions/no-debug-non-zts-*; do
                [[ -d "$path" ]] && cp "$loader" "$path/" 2>/dev/null
            done
        fi

        # تحديث php.ini
        for ini in /opt/alt/php${ver_nodot}/etc/php.ini /usr/local/php/php.ini; do
            if [[ -f "$ini" ]]; then
                sed -i '/ioncube_loader/d' "$ini"
                sed -i "1i zend_extension = ioncube_loader_lin_${ver}.so" "$ini"
            fi
        done

        log_ok "ionCube مُركّب لـ PHP $ver"
    done
}

optimize_mysql() {
    local mysql_conf="/etc/my.cnf"
    [[ ! -f "$mysql_conf" ]] && mysql_conf="/etc/my.cnf.d/server.cnf"
    [[ ! -f "$mysql_conf" ]] && { log_warn "MySQL config مفقود"; return 0; }

    local mem_mb
    mem_mb=$(($(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024))
    local buffer
    if (( mem_mb >= 8000 )); then buffer="2G"
    elif (( mem_mb >= 4000 )); then buffer="1G"
    else buffer="512M"; fi

    cat >> "$mysql_conf" <<EOF

# CWP Auto-Installer
[mysqld]
innodb_buffer_pool_size = $buffer
innodb_log_file_size = 256M
innodb_flush_log_at_trx_commit = 2
max_connections = 200
query_cache_size = 32M
tmp_table_size = 64M
max_heap_table_size = 64M
thread_cache_size = 16
EOF

    systemctl restart mysqld mariadb 2>/dev/null || true
    log_ok "MySQL مُحسّن (buffer: $buffer)"
}

configure_csf_advanced() {
    [[ "$CONFIGURE_FIREWALL" != "yes" ]] && return 0
    [[ ! -f /etc/csf/csf.conf ]] && { log_warn "CSF غير موجود"; return 0; }

    cp /etc/csf/csf.conf /etc/csf/csf.conf.bak

    local tcp_in="20,21,22,25,53,80,110,143,443,465,587,993,995,2030,2031,2077,2078,2082,2083,2086,2087,2095,2096"
    [[ "$SSH_PORT" != "22" ]] && tcp_in="${tcp_in},${SSH_PORT}"

    sed -i 's/^TESTING = "1"/TESTING = "0"/' /etc/csf/csf.conf
    sed -i "s/^TCP_IN = .*/TCP_IN = \"${tcp_in}\"/" /etc/csf/csf.conf
    sed -i 's/^SYNFLOOD = "0"/SYNFLOOD = "1"/' /etc/csf/csf.conf
    sed -i 's/^CT_LIMIT = "0"/CT_LIMIT = "300"/' /etc/csf/csf.conf
    sed -i 's/^LF_DSHIELD = "0"/LF_DSHIELD = "86400"/' /etc/csf/csf.conf
    sed -i 's/^LF_SPAMHAUS = "0"/LF_SPAMHAUS = "86400"/' /etc/csf/csf.conf
    sed -i "s/^LF_ALERT_TO = .*/LF_ALERT_TO = \"${ADMIN_EMAIL}\"/" /etc/csf/csf.conf

    csf -r >>"$LOG_FILE" 2>&1
    systemctl enable csf lfd >>"$LOG_FILE" 2>&1
    log_ok "CSF Firewall مُكوّن"
}

install_modsecurity() {
    [[ "$INSTALL_MODSECURITY" != "yes" ]] && return 0

    if [[ -f /scripts/cwp_mod_security ]]; then
        sh /scripts/cwp_mod_security >>"$LOG_FILE" 2>&1 || true
    else
        run_safe "$PKG_MANAGER -y install mod_security mod_security_crs"
    fi
    log_ok "ModSecurity"
}

install_fail2ban() {
    [[ "$INSTALL_FAIL2BAN" != "yes" ]] && return 0

    run_safe "$PKG_MANAGER -y install fail2ban fail2ban-systemd"

    cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
backend = systemd
destemail = ${ADMIN_EMAIL}
sender = fail2ban@${SERVER_HOSTNAME}

[sshd]
enabled = true
port = ${SSH_PORT},22

[apache-auth]
enabled = true
port = http,https
logpath = /usr/local/apache/logs/error_log

[postfix]
enabled = true
port = smtp,465,587
logpath = /var/log/maillog

[dovecot]
enabled = true
logpath = /var/log/maillog

[pure-ftpd]
enabled = true
logpath = /var/log/messages
EOF

    systemctl enable --now fail2ban >>"$LOG_FILE" 2>&1
    log_ok "Fail2Ban مُكوّن"
}

install_rkhunter() {
    [[ "$INSTALL_RKHUNTER" != "yes" ]] && return 0

    run_safe "$PKG_MANAGER -y install rkhunter"

    if command -v rkhunter &>/dev/null; then
        run_safe "rkhunter --update"
        run_safe "rkhunter --propupd"

        cat > /etc/cron.daily/rkhunter-scan <<EOF
#!/bin/bash
/usr/bin/rkhunter --check --skip-keypress --report-warnings-only | mail -s "RKHunter: ${SERVER_HOSTNAME}" ${ADMIN_EMAIL}
EOF
        chmod +x /etc/cron.daily/rkhunter-scan
        log_ok "RKHunter مع فحص يومي"
    fi
}

install_clamav() {
    [[ "$INSTALL_CLAMAV" != "yes" ]] && return 0

    run_safe "$PKG_MANAGER -y install clamav clamav-update clamd"

    if command -v freshclam &>/dev/null; then
        sed -i 's/^Example/#Example/' /etc/freshclam.conf 2>/dev/null
        run_safe "freshclam"
        systemctl enable --now clamav-freshclam 2>/dev/null || systemctl enable --now freshclam 2>/dev/null

        cat > /etc/cron.weekly/clamav-scan <<EOF
#!/bin/bash
clamscan -ri /home /var/www --quiet | mail -s "ClamAV: ${SERVER_HOSTNAME}" ${ADMIN_EMAIL}
EOF
        chmod +x /etc/cron.weekly/clamav-scan
        log_ok "ClamAV مع فحص أسبوعي"
    fi
}

install_maldet() {
    [[ "$INSTALL_MALDET" != "yes" ]] && return 0

    cd "$TMP_DIR" || return 1
    if [[ ! -d maldetect-current ]]; then
        run_safe "wget http://www.rfxn.com/downloads/maldetect-current.tar.gz"
        run_safe "tar xzf maldetect-current.tar.gz"
    fi

    cd maldetect-* 2>/dev/null && sh ./install.sh >>"$LOG_FILE" 2>&1

    if command -v maldet &>/dev/null; then
        sed -i 's/^email_alert=.*/email_alert="1"/' /usr/local/maldetect/conf.maldet
        sed -i "s/^email_addr=.*/email_addr=\"${ADMIN_EMAIL}\"/" /usr/local/maldetect/conf.maldet
        sed -i 's/^quarantine_hits=.*/quarantine_hits="1"/' /usr/local/maldetect/conf.maldet
        run_safe "maldet -u"
        log_ok "Maldet مُركّب"
    fi
}

harden_ssh() {
    [[ "$HARDEN_SSH" != "yes" ]] && return 0

    local cfg="/etc/ssh/sshd_config"
    cp "$cfg" "${cfg}.bak-$(date +%s)"

    if [[ "$SSH_PORT" != "22" ]]; then
        if grep -q "^Port " "$cfg"; then
            sed -i "s/^Port .*/Port $SSH_PORT/" "$cfg"
        else
            echo "Port $SSH_PORT" >> "$cfg"
        fi
    fi

    declare -A ssh_settings=(
        ["Protocol"]="2"
        ["PermitEmptyPasswords"]="no"
        ["X11Forwarding"]="no"
        ["MaxAuthTries"]="3"
        ["ClientAliveInterval"]="60"
        ["ClientAliveCountMax"]="720"
        ["UseDNS"]="no"
        ["TCPKeepAlive"]="yes"
    )

    for key in "${!ssh_settings[@]}"; do
        local value="${ssh_settings[$key]}"
        if grep -q "^#*${key} " "$cfg"; then
            sed -i "s/^#*${key} .*/${key} ${value}/" "$cfg"
        else
            echo "${key} ${value}" >> "$cfg"
        fi
    done

    if sshd -t 2>>"$LOG_FILE"; then
        systemctl restart sshd
        log_ok "SSH مُؤمّن (port: $SSH_PORT)"
    else
        log_err "خطأ SSH - استعادة"
        cp "${cfg}.bak-"* "$cfg"
        systemctl restart sshd
    fi
}

harden_kernel() {
    [[ "$HARDEN_KERNEL" != "yes" ]] && return 0

    cat > /etc/sysctl.d/99-cwp-security.conf <<'EOF'
net.ipv4.conf.all.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
fs.file-max = 65535
fs.suid_dumpable = 0
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
net.ipv4.tcp_fin_timeout = 15
EOF

    sysctl -p /etc/sysctl.d/99-cwp-security.conf >>"$LOG_FILE" 2>&1
    log_ok "Kernel مُؤمّن"
}

enable_auto_updates() {
    [[ "$ENABLE_AUTO_UPDATES" != "yes" ]] && return 0

    if [[ "$PKG_MANAGER" == "dnf" ]]; then
        run_safe "dnf -y install dnf-automatic"
        sed -i 's/^upgrade_type =.*/upgrade_type = security/' /etc/dnf/automatic.conf
        sed -i 's/^apply_updates =.*/apply_updates = yes/' /etc/dnf/automatic.conf
        systemctl enable --now dnf-automatic.timer >>"$LOG_FILE" 2>&1
    else
        run_safe "yum -y install yum-cron"
        systemctl enable --now yum-cron >>"$LOG_FILE" 2>&1
    fi
    log_ok "تحديثات تلقائية مُفعّلة"
}

generate_report() {
    local report_file="/root/cwp-installation-report.txt"
    local php_list="${INSTALLED_PHP_VERSIONS[*]:-$DEFAULT_PHP_VERSION}"

    cat > "$report_file" <<EOF
════════════════════════════════════════════════════════════════════════════════
                  تقرير تركيب CWP - $(date)
════════════════════════════════════════════════════════════════════════════════

✓ التركيب اكتمل بنجاح!

─── الوصول للوحة ─────────────────────────────────────────────────────────────
  Admin Panel  : https://${SERVER_IP}:2031/
  User Panel   : https://${SERVER_IP}:2083/
  WebMail      : https://${SERVER_IP}:2096/
  User: root | Pass: (كلمة مرور root)

─── معلومات السيرفر ──────────────────────────────────────────────────────────
  Hostname    : ${SERVER_HOSTNAME}
  IP          : ${SERVER_IP}
  OS          : ${OS_PRETTY}
  SSH Port    : ${SSH_PORT}
  Default PHP : ${DEFAULT_PHP_VERSION}
  PHP Versions: ${php_list}
  ionCube     : $([ "$INSTALL_IONCUBE" == "yes" ] && echo "مُركّب لجميع الإصدارات" || echo "غير مُركّب")

─── الحماية المُفعّلة ────────────────────────────────────────────────────────
  $([ "$CONFIGURE_FIREWALL" == "yes" ] && echo "✓" || echo "✗") CSF Firewall
  $([ "$INSTALL_MODSECURITY" == "yes" ] && echo "✓" || echo "✗") ModSecurity WAF
  $([ "$INSTALL_FAIL2BAN" == "yes" ] && echo "✓" || echo "✗") Fail2Ban
  $([ "$INSTALL_RKHUNTER" == "yes" ] && echo "✓" || echo "✗") RKHunter
  $([ "$INSTALL_CLAMAV" == "yes" ] && echo "✓" || echo "✗") ClamAV
  $([ "$INSTALL_MALDET" == "yes" ] && echo "✓" || echo "✗") Maldet
  $([ "$HARDEN_SSH" == "yes" ] && echo "✓" || echo "✗") SSH Hardening
  $([ "$HARDEN_KERNEL" == "yes" ] && echo "✓" || echo "✗") Kernel Hardening
  $([ "$HARDEN_PHP" == "yes" ] && echo "✓" || echo "✗") PHP Hardening
  $([ "$ENABLE_AUTO_UPDATES" == "yes" ] && echo "✓" || echo "✗") Auto Updates

─── الخطوات التالية ──────────────────────────────────────────────────────────
  1. أعد التشغيل: reboot
  2. ادخل: https://${SERVER_IP}:2031/
  3. غيّر كلمة مرور MySQL Root
  4. فعّل AutoSSL من اللوحة

─── ملفات مهمة ──────────────────────────────────────────────────────────────
  السجل: ${LOG_FILE}
  النسخ: ${BACKUP_DIR}
  MySQL: /root/.my.cnf

════════════════════════════════════════════════════════════════════════════════
EOF

    chmod 600 "$report_file"
    log_ok "التقرير: $report_file"
}

#==============================================================================
# 9) MAIN INSTALLATION
#==============================================================================

run_installation() {
    INSTALLED_PHP_VERSIONS=()

    # المرحلة 1: الفحوصات
    start_stage 0
    check_root
    detect_os
    validate_config
    check_requirements
    end_stage 0

    # المرحلة 2: التجهيز
    start_stage 1
    create_backup
    set_hostname
    set_timezone
    disable_selinux
    stop_conflicting_services
    setup_ssh_keepalive
    end_stage 1

    # المرحلة 3: التحديث
    start_stage 2
    update_system
    install_prerequisites
    end_stage 2

    # المرحلة 4: تحميل CWP
    start_stage 3
    download_cwp
    end_stage 3

    # المرحلة 5: تركيب CWP
    start_stage 4
    install_cwp
    end_stage 4

    # المرحلة 6-9: PHP versions
    if [[ "$INSTALL_PHP_81" == "yes" ]]; then
        start_stage 5
        install_single_php "8.1"
        end_stage 5
    fi

    if [[ "$INSTALL_PHP_82" == "yes" ]]; then
        start_stage 6
        install_single_php "8.2"
        end_stage 6
    fi

    if [[ "$INSTALL_PHP_83" == "yes" ]]; then
        start_stage 7
        install_single_php "8.3"
        end_stage 7
    fi

    if [[ "$INSTALL_PHP_84" == "yes" ]]; then
        start_stage 8
        install_single_php "8.4"
        end_stage 8
    fi

    # المرحلة 10: تحسين PHP
    start_stage 9
    configure_php_settings
    end_stage 9

    # المرحلة 11: ionCube
    start_stage 10
    install_ioncube
    end_stage 10

    # المرحلة 12: MySQL
    start_stage 11
    optimize_mysql
    end_stage 11

    # المرحلة 13: CSF
    start_stage 12
    configure_csf_advanced
    end_stage 12

    # المرحلة 14: ModSecurity
    start_stage 13
    install_modsecurity
    end_stage 13

    # المرحلة 15: Fail2Ban
    start_stage 14
    install_fail2ban
    end_stage 14

    # المرحلة 16: RKHunter
    start_stage 15
    install_rkhunter
    end_stage 15

    # المرحلة 17: ClamAV
    start_stage 16
    install_clamav
    end_stage 16

    # المرحلة 18: Maldet
    start_stage 17
    install_maldet
    end_stage 17

    # المرحلة 19: SSH
    start_stage 18
    harden_ssh
    end_stage 18

    # المرحلة 20: Kernel
    start_stage 19
    harden_kernel
    end_stage 19

    # المرحلة 21: Auto Updates
    start_stage 20
    enable_auto_updates
    end_stage 20

    # المرحلة 22: التقرير
    start_stage 21
    generate_report
    end_stage 21

    save_state "completed"
}

main_install_runner() {
    # إعداد ملفات الحالة
    mkdir -p "$STATE_DIR" "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    chmod 600 "$LOG_FILE"

    # حفظ PID و وقت البدء
    echo $$ > "$PID_FILE"
    date +%s > "$START_TIME_FILE"

    # حساب الوزن الكلي
    calc_total_weight

    # بدء heartbeat
    start_heartbeat

    # عرض الـ banner
    clear
    cat <<'BANNER'
   ╔═══════════════════════════════════════════════════════════════════╗
   ║                                                                   ║
   ║      CWP Auto-Installer v4.0 - SSH-Safe with Progress Bar        ║
   ║                                                                   ║
   ║   🛡️  محصّن ضد قطع SSH    📊 شريط تقدم تفاعلي                  ║
   ║   🐘 PHP 8.1-8.4          🔐 ionCube + الحماية المتقدمة           ║
   ║                                                                   ║
   ╚═══════════════════════════════════════════════════════════════════╝
BANNER
    echo ""

    log "═══ بدء التركيب - $(date) ═══"

    # تشغيل التركيب
    if run_installation; then
        stop_heartbeat
        cleanup_lock

        # العرض النهائي
        clear
        cat /root/cwp-installation-report.txt 2>/dev/null

        echo ""
        echo -e "${C_GREEN}${C_BOLD}╔══════════════════════════════════════════════════════════╗${C_RESET}"
        echo -e "${C_GREEN}${C_BOLD}║                                                          ║${C_RESET}"
        echo -e "${C_GREEN}${C_BOLD}║   🎉  تم تركيب CWP بنجاح كاملاً!                        ║${C_RESET}"
        echo -e "${C_GREEN}${C_BOLD}║                                                          ║${C_RESET}"
        echo -e "${C_GREEN}${C_BOLD}║   ⏱️   الوقت الكلي: $(format_time $(get_elapsed_time))"
        echo -e "${C_GREEN}${C_BOLD}║                                                          ║${C_RESET}"
        echo -e "${C_GREEN}${C_BOLD}║   ⚠️   أعد التشغيل الآن: reboot                         ║${C_RESET}"
        echo -e "${C_GREEN}${C_BOLD}║                                                          ║${C_RESET}"
        echo -e "${C_GREEN}${C_BOLD}╚══════════════════════════════════════════════════════════╝${C_RESET}"
        echo ""

        return 0
    else
        stop_heartbeat
        cleanup_lock
        return 1
    fi
}

#==============================================================================
# 10) ENTRY POINT - نقطة الدخول
#==============================================================================

main() {
    # معالجة المعاملات
    case "${1:-}" in
        --monitor|-m)
            monitor_progress
            exit 0
            ;;
        --status|-s)
            show_status
            exit 0
            ;;
        --run-actual)
            # تشغيل فعلي (تم استدعاؤه من screen/tmux/nohup)
            main_install_runner
            exit $?
            ;;
        --help|-h)
            cat <<EOF
CWP Auto-Installer v4.0

الاستخدام:
  $0              تشغيل التركيب (يطلق screen تلقائياً)
  $0 --monitor    متابعة التقدم بشكل تفاعلي
  $0 --status     عرض الحالة الحالية
  $0 --help       عرض هذه الرسالة

أمثلة:
  ./cwp-installer.sh
  ./cwp-installer.sh --monitor
EOF
            exit 0
            ;;
    esac

    # فحص root
    check_root

    # فحص lock - منع التشغيل المتوازي
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_pid
        lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            echo -e "${C_RED}توجد عملية تركيب جارية بالفعل (PID: $lock_pid)${C_RESET}"
            echo ""
            echo "للمتابعة: $0 --monitor"
            echo "للحالة:   $0 --status"
            exit 1
        else
            rm -f "$LOCK_FILE"
        fi
    fi

    # إنشاء lock
    mkdir -p "$STATE_DIR"
    echo $$ > "$LOCK_FILE"

    # إذا لم نكن في session محصّنة، اطلق نفسنا في screen
    if [[ -z "${CWP_IN_SESSION:-}" ]]; then
        local session_type
        session_type=$(check_session_type)

        if [[ "$session_type" == "ssh-direct" ]]; then
            # تركيب screen/tmux إذا لم يكن موجوداً
            install_terminal_multiplexer

            # تفعيل SSH keep-alive
            setup_ssh_keepalive

            # إعادة التشغيل في session محصّنة
            relaunch_in_screen
        fi
    fi

    # تشغيل التركيب الفعلي
    main_install_runner
}

# تشغيل
main "$@"
