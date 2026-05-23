#!/bin/bash
###############################################################################
#                                                                             #
#   CWP (Control Web Panel) Professional Auto-Installer - ENHANCED v3.0      #
#   مُثبِّت CWP الاحترافي مع PHP متعدد + ionCube + حماية متقدمة                #
#                                                                             #
#   Author      : Sherif - Dylanu                                             #
#   Version     : 3.0.0                                                       #
#   Compatible  : AlmaLinux 8/9, Rocky Linux 8/9, CentOS 7, Oracle Linux 8/9 #
#   Last Update : 2026                                                        #
#                                                                             #
#   Features:                                                                 #
#     - Multi-PHP installation (8.1, 8.2, 8.3, 8.4)                          #
#     - ionCube Loader auto-install for all PHP versions                     #
#     - Advanced server hardening (CSF, ModSecurity, Fail2Ban, RKHunter)     #
#     - Optimized PHP & MySQL configurations                                 #
#                                                                             #
###############################################################################

set -o pipefail

#==============================================================================
# 1) CONFIGURATION - الإعدادات الأساسية
#==============================================================================

# --- إعدادات السيرفر ---
SERVER_HOSTNAME="serv.sharkcodex.com"      # FQDN للسيرفر
ADMIN_EMAIL="sherifelkhouly78@gmail.com"            # بريد إدارة CWP
TIMEZONE="Africa/Cairo"                    # المنطقة الزمنية

# --- إصدار PHP الافتراضي (CLI) ---
DEFAULT_PHP_VERSION="8.3"                  # الإصدار الافتراضي للنظام

# --- إصدارات PHP المتعددة المراد تركيبها ---
# سيتم تركيبها عبر PHP-FPM Selector في CWP
INSTALL_PHP_81="yes"
INSTALL_PHP_82="yes"
INSTALL_PHP_83="yes"
INSTALL_PHP_84="yes"

# --- ionCube Loader ---
INSTALL_IONCUBE="yes"                      # تركيب ionCube لجميع إصدارات PHP
IONCUBE_VERSION="15.0"                     # أحدث إصدار

# --- خدمات إضافية ---
INSTALL_SOFTACULOUS="yes"
INSTALL_MAILSERVER="yes"
INSTALL_FTP="yes"
RECOMPILE_APACHE="yes"

# --- الأمان المتقدم ---
SSH_PORT="2200"
CONFIGURE_FIREWALL="yes"                   # CSF Firewall متقدم
INSTALL_MODSECURITY="yes"                  # ModSecurity WAF
INSTALL_FAIL2BAN="yes"                     # Fail2Ban
INSTALL_RKHUNTER="yes"                     # Rootkit Hunter
INSTALL_CLAMAV="yes"                       # ClamAV antivirus
INSTALL_MALDET="yes"                       # Linux Malware Detect
HARDEN_SSH="yes"
HARDEN_KERNEL="yes"                        # تأمين Kernel عبر sysctl
HARDEN_PHP="yes"                           # تأمين PHP (disable_functions)
ENABLE_AUTO_UPDATES="yes"                  # تحديثات أمنية تلقائية
DISABLE_ROOT_PASSWORD_LOGIN="no"           # احذر! يتطلب SSH key

# --- التقارير ---
SEND_REPORT_EMAIL="yes"
REPORT_EMAIL="${ADMIN_EMAIL}"

# --- متقدم ---
LOG_FILE="/var/log/cwp-installer-$(date +%Y%m%d-%H%M%S).log"
BACKUP_DIR="/root/cwp-installer-backups"
TMP_DIR="/usr/local/src"

#==============================================================================
# 2) COLORS & HELPERS
#==============================================================================

readonly C_RED='\033[0;31m'
readonly C_GREEN='\033[0;32m'
readonly C_YELLOW='\033[1;33m'
readonly C_BLUE='\033[0;34m'
readonly C_CYAN='\033[0;36m'
readonly C_MAGENTA='\033[0;35m'
readonly C_BOLD='\033[1m'
readonly C_RESET='\033[0m'

log()       { echo -e "${C_CYAN}[$(date +'%H:%M:%S')]${C_RESET} $*" | tee -a "$LOG_FILE"; }
log_info()  { echo -e "${C_BLUE}[INFO]${C_RESET}  $*" | tee -a "$LOG_FILE"; }
log_ok()    { echo -e "${C_GREEN}[ OK ]${C_RESET}  $*" | tee -a "$LOG_FILE"; }
log_warn()  { echo -e "${C_YELLOW}[WARN]${C_RESET}  $*" | tee -a "$LOG_FILE"; }
log_err()   { echo -e "${C_RED}[FAIL]${C_RESET}  $*" | tee -a "$LOG_FILE"; }
log_step()  { echo -e "\n${C_MAGENTA}${C_BOLD}═══ $* ═══${C_RESET}\n" | tee -a "$LOG_FILE"; }

print_banner() {
    clear
    echo -e "${C_CYAN}${C_BOLD}"
    cat <<'EOF'
   ╔═══════════════════════════════════════════════════════════════════╗
   ║                                                                   ║
   ║      CWP Auto Installer v3.0 - Enhanced Professional Edition     ║
   ║                                                                   ║
   ║   ✓ Multi-PHP (8.1 → 8.4)   ✓ ionCube Loader                     ║
   ║   ✓ CSF Firewall            ✓ ModSecurity WAF                    ║
   ║   ✓ Fail2Ban + RKHunter     ✓ ClamAV + Maldet                    ║
   ║   ✓ Kernel Hardening        ✓ PHP Hardening                      ║
   ║                                                                   ║
   ╚═══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${C_RESET}"
}

die() {
    log_err "$*"
    log_err "تم إيقاف السكربت. راجع: $LOG_FILE"
    exit 1
}

run() {
    log_info "تنفيذ: $*"
    if ! eval "$@" >>"$LOG_FILE" 2>&1; then
        die "فشل تنفيذ الأمر: $*"
    fi
}

run_safe() {
    # تشغيل بدون توقف عند الفشل
    log_info "تنفيذ (آمن): $*"
    eval "$@" >>"$LOG_FILE" 2>&1 || log_warn "الأمر فشل لكن نُكمل: $*"
}

#==============================================================================
# 3) PRE-FLIGHT CHECKS
#==============================================================================

check_root() {
    [[ $EUID -ne 0 ]] && die "يجب التشغيل كـ root. استخدم: sudo $0"
}

detect_os() {
    log "اكتشاف نظام التشغيل..."

    [[ ! -f /etc/os-release ]] && die "ملف /etc/os-release غير موجود"

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
        7)
            CWP_INSTALLER_URL="http://centos-webpanel.com/cwp-el7-latest"
            CWP_INSTALLER_FILE="cwp-el7-latest"
            PKG_MANAGER="yum"
            ;;
        8)
            CWP_INSTALLER_URL="http://centos-webpanel.com/cwp-el8-latest"
            CWP_INSTALLER_FILE="cwp-el8-latest"
            PKG_MANAGER="dnf"
            ;;
        9)
            CWP_INSTALLER_URL="http://centos-webpanel.com/cwp-el9-latest"
            CWP_INSTALLER_FILE="cwp-el9-latest"
            PKG_MANAGER="dnf"
            ;;
        *) die "إصدار غير مدعوم: $OS_VERSION" ;;
    esac

    log_ok "إصدار: EL${OS_VERSION} - مدير الحزم: $PKG_MANAGER"
}

check_requirements() {
    log "فحص متطلبات النظام..."

    if ! ping -c 1 -W 5 8.8.8.8 &>/dev/null; then
        die "لا يوجد اتصال بالإنترنت"
    fi
    log_ok "الإنترنت: متوفر"

    local mem_mb
    mem_mb=$(($(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024))

    if (( mem_mb < 1900 )); then
        die "RAM غير كافي: ${mem_mb}MB (المطلوب: 2GB+)"
    elif (( mem_mb < 3800 )); then
        log_warn "RAM: ${mem_mb}MB (الموصى به: 4GB+ للأداء الأفضل)"
    else
        log_ok "RAM: ${mem_mb}MB"
    fi

    local disk_gb
    disk_gb=$(df -BG / | awk 'NR==2 {gsub("G",""); print $4}')
    (( disk_gb < 20 )) && die "المساحة غير كافية: ${disk_gb}GB"
    log_ok "المساحة الفارغة: ${disk_gb}GB"

    [[ "$(uname -m)" != "x86_64" ]] && die "يجب أن يكون النظام 64-bit"
    log_ok "المعمارية: 64-bit"

    [[ -d /usr/local/cwpsrv ]] && die "CWP مثبت مسبقاً"

    for panel in /usr/local/cpanel /usr/local/directadmin /usr/local/plesk; do
        [[ -d "$panel" ]] && die "توجد لوحة أخرى: $panel"
    done

    log_ok "جميع المتطلبات مستوفاة"
}

validate_config() {
    log "التحقق من الإعدادات..."

    if [[ ! "$SERVER_HOSTNAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)+$ ]]; then
        die "HOSTNAME غير صالح: '$SERVER_HOSTNAME'"
    fi

    local dots
    dots=$(grep -o "\." <<<"$SERVER_HOSTNAME" | wc -l)
    (( dots < 2 )) && die "HOSTNAME يجب أن يكون FQDN كامل"

    [[ ! "$ADMIN_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] && die "EMAIL غير صالح"

    [[ ! "$DEFAULT_PHP_VERSION" =~ ^(8\.1|8\.2|8\.3|8\.4)$ ]] && die "PHP version غير مدعوم: $DEFAULT_PHP_VERSION"

    [[ ! "$SSH_PORT" =~ ^[0-9]+$ ]] || (( SSH_PORT < 1 || SSH_PORT > 65535 )) && die "SSH_PORT غير صالح"

    log_ok "الإعدادات صحيحة"
}

#==============================================================================
# 4) SYSTEM PREPARATION
#==============================================================================

create_backup() {
    log "إنشاء نسخ احتياطية..."
    mkdir -p "$BACKUP_DIR"

    local files=(
        /etc/hostname /etc/hosts /etc/ssh/sshd_config
        /etc/selinux/config /etc/sysconfig/network /etc/sysctl.conf
    )

    for file in "${files[@]}"; do
        [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$(basename "$file").bak"
    done

    log_ok "النسخ في: $BACKUP_DIR"
}

set_hostname() {
    log "ضبط Hostname: $SERVER_HOSTNAME"

    hostnamectl set-hostname "$SERVER_HOSTNAME"

    SERVER_IP=$(ip -4 route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -n1)
    [[ -z "$SERVER_IP" ]] && SERVER_IP="127.0.1.1"

    sed -i "/$SERVER_HOSTNAME/d" /etc/hosts
    echo "$SERVER_IP $SERVER_HOSTNAME $(echo "$SERVER_HOSTNAME" | cut -d. -f1)" >> /etc/hosts

    log_ok "Hostname: $(hostname -f) | IP: $SERVER_IP"
}

set_timezone() {
    log "ضبط المنطقة الزمنية: $TIMEZONE"
    timedatectl set-timezone "$TIMEZONE" 2>/dev/null || log_warn "فشل ضبط الوقت"
    log_ok "الوقت: $(date)"
}

disable_selinux() {
    log "تعطيل SELinux..."
    setenforce 0 2>/dev/null || true
    [[ -f /etc/selinux/config ]] && sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
    log_ok "SELinux معطّل"
}

stop_conflicting_services() {
    log "إيقاف الخدمات المتعارضة..."
    for svc in firewalld httpd nginx named postfix dovecot; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            systemctl stop "$svc" 2>/dev/null
            systemctl disable "$svc" 2>/dev/null
            log_info "أُوقف: $svc"
        fi
    done
    log_ok "تم"
}

update_system() {
    log "تحديث النظام..."
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
    log "تركيب الحزم الأساسية..."

    local pkgs=(wget curl tar gzip unzip vim nano net-tools bind-utils chrony perl epel-release)

    if [[ "$PKG_MANAGER" == "yum" ]]; then
        run "yum -y install ${pkgs[*]}"
    else
        run "dnf -y install ${pkgs[*]}"
    fi

    systemctl enable --now chronyd 2>/dev/null || true
    log_ok "الحزم الأساسية مُركّبة"
}

#==============================================================================
# 5) CWP INSTALLATION
#==============================================================================

download_cwp() {
    log "تحميل مثبت CWP..."
    mkdir -p "$TMP_DIR"
    cd "$TMP_DIR" || die "فشل cd"
    rm -f "$CWP_INSTALLER_FILE"

    local success=0
    for ((i=1; i<=3; i++)); do
        if wget -q --show-progress "$CWP_INSTALLER_URL" -O "$CWP_INSTALLER_FILE"; then
            success=1; break
        fi
        log_warn "محاولة $i فشلت..."
        sleep 5
    done

    [[ $success -eq 1 ]] || die "فشل تحميل المثبت"
    [[ ! -s "$CWP_INSTALLER_FILE" ]] && die "المثبت فارغ"

    log_ok "المثبت جاهز ($(du -h "$CWP_INSTALLER_FILE" | cut -f1))"
}

install_cwp() {
    log "تركيب CWP (20-40 دقيقة)..."
    log_warn "لا تقاطع العملية!"

    cd "$TMP_DIR" || die "فشل cd"

    local args=""
    [[ "$RECOMPILE_APACHE" == "yes" ]] && args+=" -r yes" || args+=" -r no"
    args+=" --phpfpm $DEFAULT_PHP_VERSION"
    [[ "$INSTALL_SOFTACULOUS" == "yes" ]] && args+=" --softaculous yes"

    log_info "أوامر: sh $CWP_INSTALLER_FILE $args"

    if sh "$CWP_INSTALLER_FILE" $args 2>&1 | tee -a "$LOG_FILE"; then
        log_ok "تم تركيب CWP"
    else
        die "فشل تركيب CWP"
    fi

    [[ ! -d /usr/local/cwpsrv ]] && die "/usr/local/cwpsrv غير موجود"
}

#==============================================================================
# 6) MULTI-PHP INSTALLATION - تركيب إصدارات PHP المتعددة
#==============================================================================

install_multi_php() {
    log_step "تركيب إصدارات PHP المتعددة"

    # CWP يستخدم PHP-FPM Selector
    # المسار: /usr/local/cwp/php71 ... /usr/local/cwp/php-fpmXX
    local php_script="/scripts/cwp_php_install_xtra"

    # التأكد من وجود سكربت CWP لتركيب PHP-FPM
    if [[ ! -f "$php_script" ]]; then
        # المحاولة البديلة - مسار آخر
        php_script="/usr/local/cwp/php/scripts/install_php"
    fi

    # تجميع قائمة الإصدارات المطلوبة
    declare -A PHP_VERSIONS=(
        ["INSTALL_PHP_81"]="8.1"
        ["INSTALL_PHP_82"]="8.2"
        ["INSTALL_PHP_83"]="8.3"
        ["INSTALL_PHP_84"]="8.4"
    )

    INSTALLED_PHP_VERSIONS=()

    for var in "${!PHP_VERSIONS[@]}"; do
        if [[ "${!var}" == "yes" ]]; then
            local ver="${PHP_VERSIONS[$var]}"
            local ver_nodot="${ver//./}"  # 8.1 → 81

            # تخطي الإصدار الافتراضي (مُركّب بالفعل)
            if [[ "$ver" == "$DEFAULT_PHP_VERSION" ]]; then
                log_info "PHP $ver: مُركّب بالفعل كإصدار افتراضي"
                INSTALLED_PHP_VERSIONS+=("$ver")
                continue
            fi

            log "تركيب PHP $ver عبر PHP-FPM Selector..."

            # CWP يستخدم سكربت داخلي لتركيب إصدارات PHP-FPM
            # ينشئ مسار /opt/alt/php{XX}/ أو /usr/local/cwp/php{XX}/
            if [[ -f /scripts/cwp_php_install_xtra ]]; then
                sh /scripts/cwp_php_install_xtra "$ver_nodot" >>"$LOG_FILE" 2>&1
            elif [[ -f /usr/local/cwp/php-fpm.sh ]]; then
                sh /usr/local/cwp/php-fpm.sh "$ver" >>"$LOG_FILE" 2>&1
            else
                # طريقة بديلة - عبر CWP API
                log_info "استخدام طريقة CWP-FPM المباشرة..."
                install_php_fpm_direct "$ver"
            fi

            if [[ -d "/opt/alt/php${ver_nodot}" ]] || \
               [[ -d "/usr/local/cwp/php-fpm/${ver_nodot}" ]] || \
               [[ -d "/usr/local/php-${ver}" ]]; then
                log_ok "تم تركيب PHP $ver"
                INSTALLED_PHP_VERSIONS+=("$ver")
            else
                log_warn "PHP $ver: قد يحتاج تركيب يدوي من لوحة CWP لاحقاً"
            fi
        fi
    done

    log_ok "إصدارات PHP المُركّبة: ${INSTALLED_PHP_VERSIONS[*]:-$DEFAULT_PHP_VERSION}"
}

install_php_fpm_direct() {
    local version="$1"
    local ver_nodot="${version//./}"

    log_info "تركيب PHP $version مباشرةً..."

    # استخدام Remi repository (الأفضل للإصدارات المتعددة)
    if [[ "$OS_VERSION" == "9" ]]; then
        run_safe "dnf -y install https://rpms.remirepo.net/enterprise/remi-release-9.rpm"
    elif [[ "$OS_VERSION" == "8" ]]; then
        run_safe "dnf -y install https://rpms.remirepo.net/enterprise/remi-release-8.rpm"
    fi

    # تركيب الإصدار المطلوب
    if [[ "$PKG_MANAGER" == "dnf" ]]; then
        run_safe "dnf -y module reset php"
        run_safe "dnf -y module enable php:remi-${version}"
        run_safe "dnf -y install php${ver_nodot}-php-fpm php${ver_nodot}-php-cli php${ver_nodot}-php-mysqlnd php${ver_nodot}-php-zip php${ver_nodot}-php-gd php${ver_nodot}-php-mbstring php${ver_nodot}-php-curl php${ver_nodot}-php-xml php${ver_nodot}-php-bcmath php${ver_nodot}-php-intl php${ver_nodot}-php-soap php${ver_nodot}-php-opcache"
    fi
}

configure_php_settings() {
    log_step "تحسين إعدادات PHP لجميع الإصدارات"

    # البحث عن جميع ملفات php.ini المُركّبة
    local php_ini_files=()

    # CWP locations
    while IFS= read -r -d '' file; do
        php_ini_files+=("$file")
    done < <(find /usr/local /opt -name "php.ini" -type f -print0 2>/dev/null)

    # إضافة الإصدار الافتراضي
    [[ -f /usr/local/php/php.ini ]] && php_ini_files+=("/usr/local/php/php.ini")
    [[ -f /etc/php.ini ]] && php_ini_files+=("/etc/php.ini")

    if [[ ${#php_ini_files[@]} -eq 0 ]]; then
        log_warn "لم يتم العثور على ملفات php.ini"
        return 0
    fi

    log_info "تحسين ${#php_ini_files[@]} ملف php.ini"

    for php_ini in "${php_ini_files[@]}"; do
        log_info "تحسين: $php_ini"

        # نسخة احتياطية
        cp "$php_ini" "${php_ini}.bak-cwp-installer"

        # تطبيق الإعدادات المُحسّنة
        sed -i \
            -e 's/^;\?\s*memory_limit\s*=.*/memory_limit = 256M/' \
            -e 's/^;\?\s*upload_max_filesize\s*=.*/upload_max_filesize = 128M/' \
            -e 's/^;\?\s*post_max_size\s*=.*/post_max_size = 128M/' \
            -e 's/^;\?\s*max_execution_time\s*=.*/max_execution_time = 300/' \
            -e 's/^;\?\s*max_input_time\s*=.*/max_input_time = 300/' \
            -e 's/^;\?\s*max_input_vars\s*=.*/max_input_vars = 5000/' \
            -e 's/^;\?\s*default_socket_timeout\s*=.*/default_socket_timeout = 300/' \
            -e 's/^;\?\s*date.timezone\s*=.*/date.timezone = '"$TIMEZONE"'/' \
            -e 's/^;\?\s*opcache.enable\s*=.*/opcache.enable=1/' \
            -e 's/^;\?\s*opcache.memory_consumption\s*=.*/opcache.memory_consumption=256/' \
            -e 's/^;\?\s*opcache.max_accelerated_files\s*=.*/opcache.max_accelerated_files=20000/' \
            -e 's/^;\?\s*opcache.revalidate_freq\s*=.*/opcache.revalidate_freq=60/' \
            -e 's/^;\?\s*opcache.fast_shutdown\s*=.*/opcache.fast_shutdown=1/' \
            -e 's/^;\?\s*realpath_cache_size\s*=.*/realpath_cache_size = 4096K/' \
            -e 's/^;\?\s*realpath_cache_ttl\s*=.*/realpath_cache_ttl = 600/' \
            "$php_ini"

        # PHP Hardening - تأمين PHP
        if [[ "$HARDEN_PHP" == "yes" ]]; then
            sed -i \
                -e 's/^;\?\s*expose_php\s*=.*/expose_php = Off/' \
                -e 's/^;\?\s*display_errors\s*=.*/display_errors = Off/' \
                -e 's/^;\?\s*display_startup_errors\s*=.*/display_startup_errors = Off/' \
                -e 's/^;\?\s*log_errors\s*=.*/log_errors = On/' \
                -e 's/^;\?\s*allow_url_fopen\s*=.*/allow_url_fopen = Off/' \
                -e 's/^;\?\s*allow_url_include\s*=.*/allow_url_include = Off/' \
                -e 's/^;\?\s*file_uploads\s*=.*/file_uploads = On/' \
                -e 's/^;\?\s*session.cookie_httponly\s*=.*/session.cookie_httponly = 1/' \
                -e 's/^;\?\s*session.cookie_secure\s*=.*/session.cookie_secure = 1/' \
                -e 's/^;\?\s*session.use_strict_mode\s*=.*/session.use_strict_mode = 1/' \
                "$php_ini"

            # إضافة disable_functions للأمان
            local dangerous="exec,passthru,shell_exec,system,proc_open,popen,curl_multi_exec,parse_ini_file,show_source,eval,assert,phpinfo"
            if grep -q "^disable_functions" "$php_ini"; then
                sed -i "s|^disable_functions\s*=.*|disable_functions = ${dangerous}|" "$php_ini"
            else
                echo "disable_functions = ${dangerous}" >> "$php_ini"
            fi
        fi
    done

    log_ok "تم تحسين وتأمين إعدادات PHP"
}

#==============================================================================
# 7) IONCUBE LOADER INSTALLATION
#==============================================================================

install_ioncube() {
    [[ "$INSTALL_IONCUBE" != "yes" ]] && return 0

    log_step "تركيب ionCube Loader لجميع إصدارات PHP"

    cd "$TMP_DIR" || die "فشل cd"

    # تحميل ionCube Loaders
    log "تحميل ionCube Loaders..."
    rm -f ioncube_loaders_lin_x86-64.tar.gz
    rm -rf ioncube

    local ioncube_url="https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz"
    if ! wget -q "$ioncube_url" -O ioncube_loaders_lin_x86-64.tar.gz; then
        log_err "فشل تحميل ionCube"
        return 1
    fi

    tar xzf ioncube_loaders_lin_x86-64.tar.gz
    [[ ! -d ioncube ]] && { log_err "فشل استخراج ionCube"; return 1; }

    log_ok "تم تحميل ionCube"

    # تركيب ionCube لكل إصدار PHP مُركّب
    local versions=("${INSTALLED_PHP_VERSIONS[@]:-$DEFAULT_PHP_VERSION}")

    for ver in "${versions[@]}"; do
        install_ioncube_for_php "$ver"
    done

    log_ok "اكتمل تركيب ionCube لجميع الإصدارات"
}

install_ioncube_for_php() {
    local php_ver="$1"
    local ver_nodot="${php_ver//./}"
    local loader_file="$TMP_DIR/ioncube/ioncube_loader_lin_${php_ver}.so"

    log "تركيب ionCube لـ PHP $php_ver..."

    if [[ ! -f "$loader_file" ]]; then
        log_warn "ionCube غير متاح لـ PHP $php_ver"
        return 1
    fi

    # المسارات المحتملة لـ extension_dir
    local ext_dirs=()
    local ini_files=()

    # CWP-FPM paths
    if [[ -d "/opt/alt/php${ver_nodot}" ]]; then
        ext_dirs+=(/opt/alt/php${ver_nodot}/usr/lib64/php/modules)
        ini_files+=(/opt/alt/php${ver_nodot}/etc/php.ini)
    fi

    if [[ -d "/usr/local/cwp/php-fpm/${ver_nodot}" ]]; then
        ext_dirs+=(/usr/local/cwp/php-fpm/${ver_nodot}/lib/php/extensions)
        ini_files+=(/usr/local/cwp/php-fpm/${ver_nodot}/etc/php.ini)
    fi

    # Default CWP PHP
    if [[ "$php_ver" == "$DEFAULT_PHP_VERSION" ]]; then
        ext_dirs+=(/usr/local/php/lib/php/extensions/no-debug-non-zts-*)
        ini_files+=(/usr/local/php/php.ini)
    fi

    # Remi PHP
    if [[ -d "/opt/remi/php${ver_nodot}" ]]; then
        ext_dirs+=(/opt/remi/php${ver_nodot}/root/usr/lib64/php/modules)
        ini_files+=(/etc/opt/remi/php${ver_nodot}/php.ini)
    fi

    local installed=0

    # نسخ ملف الـ loader للمسارات المناسبة
    for ext_dir_pattern in "${ext_dirs[@]}"; do
        for ext_dir in $ext_dir_pattern; do
            if [[ -d "$ext_dir" ]]; then
                cp "$loader_file" "$ext_dir/" && {
                    log_info "نُسخ إلى: $ext_dir"
                    installed=1
                }
            fi
        done
    done

    # تحديث ملفات php.ini
    for ini in "${ini_files[@]}"; do
        if [[ -f "$ini" ]]; then
            # حذف أي إدخالات قديمة لـ ionCube
            sed -i '/ioncube_loader/d' "$ini"

            # إضافة في بداية الملف (يجب أن يكون أول zend_extension)
            local tmp_ini=$(mktemp)
            echo "; ionCube Loader (added by CWP Auto-Installer)" > "$tmp_ini"
            echo "zend_extension = ioncube_loader_lin_${php_ver}.so" >> "$tmp_ini"
            echo "" >> "$tmp_ini"
            cat "$ini" >> "$tmp_ini"
            mv "$tmp_ini" "$ini"

            log_info "تحديث: $ini"
            installed=1
        fi
    done

    if [[ $installed -eq 1 ]]; then
        log_ok "ionCube مُركّب لـ PHP $php_ver"
    else
        log_warn "لم يتم العثور على مسار PHP $php_ver لتركيب ionCube"
    fi
}

#==============================================================================
# 8) ADVANCED SECURITY - الحماية المتقدمة
#==============================================================================

configure_csf_advanced() {
    [[ "$CONFIGURE_FIREWALL" != "yes" ]] && return 0

    log_step "تكوين CSF Firewall (متقدم)"

    if [[ ! -f /etc/csf/csf.conf ]]; then
        log_warn "CSF غير موجود - تخطي"
        return 0
    fi

    cp /etc/csf/csf.conf /etc/csf/csf.conf.bak-cwp

    # تحويل لوضع الإنتاج
    sed -i 's/^TESTING = "1"/TESTING = "0"/' /etc/csf/csf.conf

    # منافذ TCP الواردة
    local tcp_in="20,21,22,25,53,80,110,143,443,465,587,993,995,2030,2031,2077,2078,2082,2083,2086,2087,2095,2096"
    [[ "$SSH_PORT" != "22" ]] && tcp_in="${tcp_in},${SSH_PORT}"

    sed -i "s/^TCP_IN = .*/TCP_IN = \"${tcp_in}\"/" /etc/csf/csf.conf
    sed -i 's/^TCP_OUT = .*/TCP_OUT = "20,21,22,25,53,80,110,113,443,465,587,873,993,995,2030,2031,2086,2087"/' /etc/csf/csf.conf
    sed -i 's/^UDP_IN = .*/UDP_IN = "20,21,53,80,443"/' /etc/csf/csf.conf
    sed -i 's/^UDP_OUT = .*/UDP_OUT = "20,21,53,113,123,873,6277"/' /etc/csf/csf.conf

    # حماية متقدمة - SYN Flood Protection
    sed -i 's/^SYNFLOOD = "0"/SYNFLOOD = "1"/' /etc/csf/csf.conf
    sed -i 's/^SYNFLOOD_RATE = .*/SYNFLOOD_RATE = "100\/s"/' /etc/csf/csf.conf
    sed -i 's/^SYNFLOOD_BURST = .*/SYNFLOOD_BURST = "150"/' /etc/csf/csf.conf

    # Connection limit per IP
    sed -i 's/^CT_LIMIT = "0"/CT_LIMIT = "300"/' /etc/csf/csf.conf
    sed -i 's/^CT_INTERVAL = .*/CT_INTERVAL = "30"/' /etc/csf/csf.conf
    sed -i 's/^CT_BLOCK_TIME = .*/CT_BLOCK_TIME = "1800"/' /etc/csf/csf.conf

    # Port Flood Protection
    sed -i 's/^PORTFLOOD = .*/PORTFLOOD = "22;tcp;5;300,80;tcp;20;5,443;tcp;20;5"/' /etc/csf/csf.conf

    # Login Failure Daemon (LFD) settings
    sed -i 's/^LF_DAEMON = "0"/LF_DAEMON = "1"/' /etc/csf/csf.conf
    sed -i 's/^LF_SSHD = .*/LF_SSHD = "3"/' /etc/csf/csf.conf
    sed -i 's/^LF_FTPD = .*/LF_FTPD = "5"/' /etc/csf/csf.conf
    sed -i 's/^LF_SMTPAUTH = .*/LF_SMTPAUTH = "5"/' /etc/csf/csf.conf
    sed -i 's/^LF_POP3D = .*/LF_POP3D = "5"/' /etc/csf/csf.conf
    sed -i 's/^LF_IMAPD = .*/LF_IMAPD = "5"/' /etc/csf/csf.conf
    sed -i 's/^LF_HTACCESS = .*/LF_HTACCESS = "5"/' /etc/csf/csf.conf
    sed -i 's/^LF_MODSEC = .*/LF_MODSEC = "5"/' /etc/csf/csf.conf

    # Blocklists - استخدام قوائم سوداء جاهزة
    sed -i 's/^LF_DSHIELD = "0"/LF_DSHIELD = "86400"/' /etc/csf/csf.conf
    sed -i 's/^LF_SPAMHAUS = "0"/LF_SPAMHAUS = "86400"/' /etc/csf/csf.conf
    sed -i 's/^LF_TOR = "0"/LF_TOR = "86400"/' /etc/csf/csf.conf

    # Permanent ban بعد محاولات فاشلة متكررة
    sed -i 's/^LF_TRIGGER = .*/LF_TRIGGER = "10"/' /etc/csf/csf.conf
    sed -i 's/^LF_PERMBLOCK = .*/LF_PERMBLOCK = "1"/' /etc/csf/csf.conf
    sed -i 's/^LF_PERMBLOCK_COUNT = .*/LF_PERMBLOCK_COUNT = "4"/' /etc/csf/csf.conf

    # Notifications
    sed -i "s/^LF_ALERT_TO = .*/LF_ALERT_TO = \"${ADMIN_EMAIL}\"/" /etc/csf/csf.conf

    # تشغيل CSF
    csf -r >>"$LOG_FILE" 2>&1
    systemctl enable csf lfd >>"$LOG_FILE" 2>&1
    systemctl restart csf lfd >>"$LOG_FILE" 2>&1

    log_ok "تم تكوين CSF بإعدادات الحماية المتقدمة"
}

install_modsecurity() {
    [[ "$INSTALL_MODSECURITY" != "yes" ]] && return 0

    log_step "تركيب ModSecurity WAF"

    # CWP عادة يحتوي على سكربت ModSec
    if [[ -f /scripts/cwp_mod_security ]]; then
        sh /scripts/cwp_mod_security >>"$LOG_FILE" 2>&1 && \
            log_ok "تم تركيب ModSecurity عبر CWP" || \
            log_warn "فشل تركيب ModSecurity من CWP"
    else
        # تركيب يدوي
        if [[ "$PKG_MANAGER" == "dnf" ]]; then
            run_safe "dnf -y install mod_security mod_security_crs"
        else
            run_safe "yum -y install mod_security mod_security_crs"
        fi
        log_ok "تم تركيب ModSecurity"
    fi

    # تفعيل OWASP Core Rule Set
    local modsec_conf="/etc/httpd/conf.d/mod_security.conf"
    if [[ -f "$modsec_conf" ]]; then
        sed -i 's/^SecRuleEngine.*/SecRuleEngine On/' "$modsec_conf"
        log_ok "تم تفعيل ModSecurity"
    fi
}

install_fail2ban() {
    [[ "$INSTALL_FAIL2BAN" != "yes" ]] && return 0

    log_step "تركيب Fail2Ban"

    if [[ "$PKG_MANAGER" == "dnf" ]]; then
        run_safe "dnf -y install fail2ban fail2ban-systemd"
    else
        run_safe "yum -y install fail2ban fail2ban-systemd"
    fi

    # إعداد Jail محلي
    cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
backend = systemd
destemail = ${ADMIN_EMAIL}
sender = fail2ban@${SERVER_HOSTNAME}
action = %(action_mwl)s

[sshd]
enabled = true
port = ${SSH_PORT},22
logpath = %(sshd_log)s
backend = %(sshd_backend)s

[apache-auth]
enabled = true
port = http,https
logpath = /usr/local/apache/logs/error_log

[apache-badbots]
enabled = true
port = http,https
logpath = /usr/local/apache/logs/access_log

[apache-noscript]
enabled = true
port = http,https
logpath = /usr/local/apache/logs/error_log

[apache-overflows]
enabled = true
port = http,https
logpath = /usr/local/apache/logs/error_log

[postfix]
enabled = true
port = smtp,465,587
logpath = /var/log/maillog

[dovecot]
enabled = true
port = pop3,pop3s,imap,imaps,submission,465,sieve
logpath = /var/log/maillog

[pure-ftpd]
enabled = true
port = ftp,ftp-data,ftps,ftps-data
logpath = /var/log/messages
maxretry = 6
EOF

    systemctl enable fail2ban >>"$LOG_FILE" 2>&1
    systemctl restart fail2ban >>"$LOG_FILE" 2>&1

    log_ok "تم تركيب وتكوين Fail2Ban"
}

install_rkhunter() {
    [[ "$INSTALL_RKHUNTER" != "yes" ]] && return 0

    log_step "تركيب RKHunter (Rootkit Detector)"

    if [[ "$PKG_MANAGER" == "dnf" ]]; then
        run_safe "dnf -y install rkhunter"
    else
        run_safe "yum -y install rkhunter"
    fi

    if command -v rkhunter &>/dev/null; then
        # تحديث قاعدة البيانات
        run_safe "rkhunter --update"
        run_safe "rkhunter --propupd"

        # إعداد فحص يومي تلقائي
        cat > /etc/cron.daily/rkhunter-scan <<EOF
#!/bin/bash
/usr/bin/rkhunter --check --skip-keypress --report-warnings-only | mail -s "RKHunter Scan: ${SERVER_HOSTNAME}" ${ADMIN_EMAIL}
EOF
        chmod +x /etc/cron.daily/rkhunter-scan

        log_ok "تم تركيب RKHunter مع فحص يومي"
    else
        log_warn "فشل تركيب RKHunter"
    fi
}

install_clamav() {
    [[ "$INSTALL_CLAMAV" != "yes" ]] && return 0

    log_step "تركيب ClamAV Antivirus"

    if [[ "$PKG_MANAGER" == "dnf" ]]; then
        run_safe "dnf -y install clamav clamav-update clamd"
    else
        run_safe "yum -y install clamav clamav-update clamd"
    fi

    if command -v freshclam &>/dev/null; then
        # تفعيل التحديث التلقائي
        sed -i 's/^Example/#Example/' /etc/freshclam.conf 2>/dev/null || true

        # تحديث قاعدة البيانات
        run_safe "freshclam"

        # تفعيل الخدمة
        systemctl enable clamav-freshclam 2>/dev/null || systemctl enable freshclam 2>/dev/null
        systemctl start clamav-freshclam 2>/dev/null || systemctl start freshclam 2>/dev/null

        # فحص أسبوعي
        cat > /etc/cron.weekly/clamav-scan <<EOF
#!/bin/bash
clamscan -ri /home /var/www /usr/local/cwpsrv --quiet | mail -s "ClamAV Weekly Scan: ${SERVER_HOSTNAME}" ${ADMIN_EMAIL}
EOF
        chmod +x /etc/cron.weekly/clamav-scan

        log_ok "تم تركيب ClamAV مع فحص أسبوعي"
    else
        log_warn "فشل تركيب ClamAV"
    fi
}

install_maldet() {
    [[ "$INSTALL_MALDET" != "yes" ]] && return 0

    log_step "تركيب Linux Malware Detect (Maldet)"

    cd "$TMP_DIR" || return 1

    if [[ ! -d maldetect-current ]]; then
        run_safe "wget http://www.rfxn.com/downloads/maldetect-current.tar.gz"
        run_safe "tar xzf maldetect-current.tar.gz"
    fi

    cd maldetect-* 2>/dev/null || { log_warn "لم يتم العثور على maldet"; return 1; }
    sh ./install.sh >>"$LOG_FILE" 2>&1

    if command -v maldet &>/dev/null; then
        # تكوين Maldet
        sed -i 's/^email_alert=.*/email_alert="1"/' /usr/local/maldetect/conf.maldet
        sed -i "s/^email_addr=.*/email_addr=\"${ADMIN_EMAIL}\"/" /usr/local/maldetect/conf.maldet
        sed -i 's/^quarantine_hits=.*/quarantine_hits="1"/' /usr/local/maldetect/conf.maldet
        sed -i 's/^quarantine_clean=.*/quarantine_clean="1"/' /usr/local/maldetect/conf.maldet

        # دمج مع ClamAV لو موجود
        sed -i 's/^scan_clamscan=.*/scan_clamscan="1"/' /usr/local/maldetect/conf.maldet

        # تحديث التوقيعات
        run_safe "maldet -u"

        log_ok "تم تركيب Maldet"
    else
        log_warn "فشل تركيب Maldet"
    fi
}

harden_ssh() {
    [[ "$HARDEN_SSH" != "yes" ]] && return 0

    log_step "تأمين SSH"

    local cfg="/etc/ssh/sshd_config"
    cp "$cfg" "${cfg}.bak-$(date +%s)"

    if [[ "$SSH_PORT" != "22" ]]; then
        if grep -q "^Port " "$cfg"; then
            sed -i "s/^Port .*/Port $SSH_PORT/" "$cfg"
        else
            echo "Port $SSH_PORT" >> "$cfg"
        fi
    fi

    # تطبيق الإعدادات الآمنة
    declare -A ssh_settings=(
        ["Protocol"]="2"
        ["PermitEmptyPasswords"]="no"
        ["X11Forwarding"]="no"
        ["MaxAuthTries"]="3"
        ["MaxSessions"]="10"
        ["ClientAliveInterval"]="300"
        ["ClientAliveCountMax"]="2"
        ["LoginGraceTime"]="30"
        ["IgnoreRhosts"]="yes"
        ["HostbasedAuthentication"]="no"
        ["PermitUserEnvironment"]="no"
        ["AllowAgentForwarding"]="no"
        ["AllowTcpForwarding"]="no"
        ["UseDNS"]="no"
    )

    for key in "${!ssh_settings[@]}"; do
        local value="${ssh_settings[$key]}"
        if grep -q "^#*${key} " "$cfg"; then
            sed -i "s/^#*${key} .*/${key} ${value}/" "$cfg"
        else
            echo "${key} ${value}" >> "$cfg"
        fi
    done

    if [[ "$DISABLE_ROOT_PASSWORD_LOGIN" == "yes" ]]; then
        sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' "$cfg"
        log_warn "تم تعطيل root password login - استخدم SSH key"
    fi

    # اختبار قبل إعادة التشغيل
    if sshd -t 2>>"$LOG_FILE"; then
        systemctl restart sshd
        log_ok "تم تأمين SSH (المنفذ: $SSH_PORT)"
    else
        log_err "خطأ في إعدادات SSH - استعادة"
        cp "${cfg}.bak-"* "$cfg"
        systemctl restart sshd
    fi
}

harden_kernel() {
    [[ "$HARDEN_KERNEL" != "yes" ]] && return 0

    log_step "تأمين Kernel عبر sysctl"

    cat > /etc/sysctl.d/99-cwp-security.conf <<'EOF'
# CWP Auto-Installer - Kernel Hardening

# IP Spoofing Protection
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Ignore ICMP broadcast requests
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Disable source packet routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# Ignore send redirects
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Block SYN attacks
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5

# Log Martians
net.ipv4.conf.all.log_martians = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Ignore ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Ignore Directed pings
net.ipv4.icmp_echo_ignore_all = 0

# Enable bad error message protection
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Increase system file descriptor limit
fs.file-max = 65535

# Restrict core dumps
fs.suid_dumpable = 0

# Hide kernel pointers
kernel.kptr_restrict = 2

# Restrict dmesg
kernel.dmesg_restrict = 1

# Protect against SACK exploits
net.ipv4.tcp_sack = 0

# Decrease the time default value for tcp_fin_timeout
net.ipv4.tcp_fin_timeout = 15

# Decrease keepalive
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15
EOF

    sysctl -p /etc/sysctl.d/99-cwp-security.conf >>"$LOG_FILE" 2>&1
    log_ok "تم تأمين Kernel"
}

enable_auto_updates() {
    [[ "$ENABLE_AUTO_UPDATES" != "yes" ]] && return 0

    log_step "تفعيل التحديثات الأمنية التلقائية"

    if [[ "$PKG_MANAGER" == "dnf" ]]; then
        run_safe "dnf -y install dnf-automatic"
        sed -i 's/^upgrade_type =.*/upgrade_type = security/' /etc/dnf/automatic.conf
        sed -i 's/^apply_updates =.*/apply_updates = yes/' /etc/dnf/automatic.conf
        sed -i "s/^emit_via =.*/emit_via = email/" /etc/dnf/automatic.conf
        sed -i "s/^email_to =.*/email_to = ${ADMIN_EMAIL}/" /etc/dnf/automatic.conf
        systemctl enable --now dnf-automatic.timer >>"$LOG_FILE" 2>&1
    else
        run_safe "yum -y install yum-cron"
        sed -i 's/^update_cmd =.*/update_cmd = security/' /etc/yum/yum-cron.conf 2>/dev/null
        sed -i 's/^apply_updates =.*/apply_updates = yes/' /etc/yum/yum-cron.conf 2>/dev/null
        systemctl enable --now yum-cron >>"$LOG_FILE" 2>&1
    fi

    log_ok "التحديثات الأمنية التلقائية مُفعّلة"
}

optimize_mysql() {
    log_step "تحسين MySQL/MariaDB"

    local mysql_conf="/etc/my.cnf"
    [[ ! -f "$mysql_conf" ]] && mysql_conf="/etc/my.cnf.d/server.cnf"
    [[ ! -f "$mysql_conf" ]] && { log_warn "ملف MySQL config غير موجود"; return 0; }

    local mem_mb
    mem_mb=$(($(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024))

    local innodb_buffer
    if (( mem_mb >= 8000 )); then
        innodb_buffer="2G"
    elif (( mem_mb >= 4000 )); then
        innodb_buffer="1G"
    else
        innodb_buffer="512M"
    fi

    cat >> "$mysql_conf" <<EOF

# CWP Auto-Installer Optimizations
[mysqld]
innodb_buffer_pool_size = $innodb_buffer
innodb_log_file_size = 256M
innodb_flush_log_at_trx_commit = 2
innodb_flush_method = O_DIRECT
max_connections = 200
query_cache_size = 32M
query_cache_limit = 2M
tmp_table_size = 64M
max_heap_table_size = 64M
thread_cache_size = 16
table_open_cache = 2000
key_buffer_size = 32M
EOF

    systemctl restart mysqld mariadb 2>/dev/null || true
    log_ok "تم تحسين MySQL (buffer: $innodb_buffer)"
}

#==============================================================================
# 9) REPORTING
#==============================================================================

generate_report() {
    log_step "إنشاء التقرير النهائي"

    local report_file="/root/cwp-installation-report.txt"
    local php_list="${INSTALLED_PHP_VERSIONS[*]:-$DEFAULT_PHP_VERSION}"

    cat > "$report_file" <<EOF
════════════════════════════════════════════════════════════════════════════════
                  تقرير تركيب CWP المتقدم - $(date)
════════════════════════════════════════════════════════════════════════════════

✓ التركيب اكتمل بنجاح!

────────────────────────────────────────────────────────────────────────────────
معلومات الوصول للوحة:
────────────────────────────────────────────────────────────────────────────────

  لوحة الإدارة:
    HTTP  : http://${SERVER_IP}:2030/
    HTTPS : https://${SERVER_IP}:2031/
    User  : root
    Pass  : (كلمة مرور root)

  لوحة المستخدم:
    HTTP  : http://${SERVER_IP}:2082/
    HTTPS : https://${SERVER_IP}:2083/

  WebMail:
    HTTPS : https://${SERVER_IP}:2096/

────────────────────────────────────────────────────────────────────────────────
معلومات السيرفر:
────────────────────────────────────────────────────────────────────────────────

  Hostname       : ${SERVER_HOSTNAME}
  IP Address     : ${SERVER_IP}
  OS             : ${OS_PRETTY}
  SSH Port       : ${SSH_PORT}
  Default PHP    : ${DEFAULT_PHP_VERSION}
  PHP Versions   : ${php_list}
  Timezone       : ${TIMEZONE}
  Admin Email    : ${ADMIN_EMAIL}

────────────────────────────────────────────────────────────────────────────────
إصدارات PHP المُركّبة:
────────────────────────────────────────────────────────────────────────────────

EOF

    for ver in "${INSTALLED_PHP_VERSIONS[@]:-$DEFAULT_PHP_VERSION}"; do
        echo "  ✓ PHP ${ver}" >> "$report_file"
    done

    cat >> "$report_file" <<EOF

  📌 لتغيير PHP-FPM للنطاقات:
     CWP Admin → PHP Settings → PHP-FPM Selector

────────────────────────────────────────────────────────────────────────────────
ionCube Loader:
────────────────────────────────────────────────────────────────────────────────

EOF

    if [[ "$INSTALL_IONCUBE" == "yes" ]]; then
        echo "  ✓ ionCube مُركّب لجميع إصدارات PHP" >> "$report_file"
        echo "  📌 للتحقق: php -v" >> "$report_file"
    else
        echo "  ✗ غير مُركّب" >> "$report_file"
    fi

    cat >> "$report_file" <<EOF

────────────────────────────────────────────────────────────────────────────────
الحماية المتقدمة:
────────────────────────────────────────────────────────────────────────────────

  $([ "$CONFIGURE_FIREWALL" == "yes" ] && echo "✓" || echo "✗") CSF Firewall (Advanced)
  $([ "$INSTALL_MODSECURITY" == "yes" ] && echo "✓" || echo "✗") ModSecurity WAF
  $([ "$INSTALL_FAIL2BAN" == "yes" ] && echo "✓" || echo "✗") Fail2Ban (Brute-force protection)
  $([ "$INSTALL_RKHUNTER" == "yes" ] && echo "✓" || echo "✗") RKHunter (Rootkit Detector) - فحص يومي
  $([ "$INSTALL_CLAMAV" == "yes" ] && echo "✓" || echo "✗") ClamAV Antivirus - فحص أسبوعي
  $([ "$INSTALL_MALDET" == "yes" ] && echo "✓" || echo "✗") Linux Malware Detect (Maldet)
  $([ "$HARDEN_SSH" == "yes" ] && echo "✓" || echo "✗") SSH Hardening
  $([ "$HARDEN_KERNEL" == "yes" ] && echo "✓" || echo "✗") Kernel Hardening (sysctl)
  $([ "$HARDEN_PHP" == "yes" ] && echo "✓" || echo "✗") PHP Hardening (disable_functions)
  $([ "$ENABLE_AUTO_UPDATES" == "yes" ] && echo "✓" || echo "✗") Auto Security Updates

────────────────────────────────────────────────────────────────────────────────
الأوامر المفيدة:
────────────────────────────────────────────────────────────────────────────────

  حالة الخدمات:
    systemctl status httpd mariadb csf lfd fail2ban

  CSF Firewall:
    csf -l              # عرض القواعد
    csf -d IP           # حظر IP
    csf -dr IP          # رفع الحظر
    csf -tf             # القائمة المؤقتة
    csf -r              # إعادة تحميل

  Fail2Ban:
    fail2ban-client status
    fail2ban-client status sshd
    fail2ban-client set sshd unbanip IP

  ClamAV:
    clamscan -r /home   # فحص يدوي
    freshclam           # تحديث التوقيعات

  RKHunter:
    rkhunter --check    # فحص يدوي
    rkhunter --update   # تحديث

  Maldet:
    maldet -a /home     # فحص
    maldet -u           # تحديث التوقيعات

  PHP:
    php -v              # الإصدار الافتراضي
    /opt/alt/php81/usr/bin/php -v   # إصدار محدد

────────────────────────────────────────────────────────────────────────────────
الخطوات التالية:
────────────────────────────────────────────────────────────────────────────────

  1. ⚠️  أعد تشغيل السيرفر: reboot
  2. ادخل اللوحة: https://${SERVER_IP}:2031/
  3. غيّر كلمة مرور MySQL Root (cat /root/.my.cnf)
  4. فعّل AutoSSL للـ Hostname من: SSL → AutoSSL
  5. اضبط Backup Manager للنسخ الاحتياطي
  6. تحقق من PHP-FPM Selector لاختيار الإصدار لكل نطاق
  7. اضبط Name Servers لو هتستخدمه DNS Server

────────────────────────────────────────────────────────────────────────────────
ملفات مهمة:
────────────────────────────────────────────────────────────────────────────────

  سجل التركيب     : ${LOG_FILE}
  النسخ الاحتياطية : ${BACKUP_DIR}
  بيانات MySQL    : /root/.my.cnf
  هذا التقرير      : ${report_file}

════════════════════════════════════════════════════════════════════════════════
EOF

    chmod 600 "$report_file"
    log_ok "التقرير: $report_file"
    cat "$report_file"
}

send_report_email() {
    [[ "$SEND_REPORT_EMAIL" != "yes" ]] && return 0

    log "إرسال التقرير: $REPORT_EMAIL"

    if command -v mail &>/dev/null; then
        mail -s "تم تركيب CWP على $SERVER_HOSTNAME" "$REPORT_EMAIL" < /root/cwp-installation-report.txt 2>>"$LOG_FILE" \
            && log_ok "تم الإرسال" || log_warn "فشل الإرسال"
    fi
}

#==============================================================================
# 10) MAIN
#==============================================================================

main() {
    print_banner

    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    chmod 600 "$LOG_FILE"

    log_step "بدء التركيب - $(date)"

    # المرحلة 1: الفحوصات
    log_step "المرحلة 1/8: الفحوصات الأولية"
    check_root
    detect_os
    validate_config
    check_requirements

    # عرض الملخص
    echo -e "\n${C_YELLOW}${C_BOLD}ملخص الإعدادات:${C_RESET}"
    echo "  Hostname        : $SERVER_HOSTNAME"
    echo "  Email           : $ADMIN_EMAIL"
    echo "  Default PHP     : $DEFAULT_PHP_VERSION"
    echo "  Multi-PHP       : 8.1=$INSTALL_PHP_81 | 8.2=$INSTALL_PHP_82 | 8.3=$INSTALL_PHP_83 | 8.4=$INSTALL_PHP_84"
    echo "  ionCube         : $INSTALL_IONCUBE"
    echo "  SSH Port        : $SSH_PORT"
    echo "  Firewall        : $CONFIGURE_FIREWALL"
    echo "  ModSecurity     : $INSTALL_MODSECURITY"
    echo "  Fail2Ban        : $INSTALL_FAIL2BAN"
    echo "  RKHunter        : $INSTALL_RKHUNTER"
    echo "  ClamAV          : $INSTALL_CLAMAV"
    echo "  Maldet          : $INSTALL_MALDET"
    echo ""
    log "بدء التركيب خلال 5 ثوانٍ... (Ctrl+C للإلغاء)"
    sleep 5

    # المرحلة 2: التجهيز
    log_step "المرحلة 2/8: تجهيز النظام"
    create_backup
    set_hostname
    set_timezone
    disable_selinux
    stop_conflicting_services

    # المرحلة 3: التحديث
    log_step "المرحلة 3/8: تحديث النظام"
    update_system
    install_prerequisites

    # المرحلة 4: تركيب CWP
    log_step "المرحلة 4/8: تركيب CWP"
    download_cwp
    install_cwp

    # المرحلة 5: PHP متعدد و ionCube
    log_step "المرحلة 5/8: PHP متعدد و ionCube"
    install_multi_php
    configure_php_settings
    install_ioncube

    # المرحلة 6: تحسين MySQL
    log_step "المرحلة 6/8: تحسين قاعدة البيانات"
    optimize_mysql

    # المرحلة 7: الحماية المتقدمة
    log_step "المرحلة 7/8: الحماية المتقدمة"
    configure_csf_advanced
    install_modsecurity
    install_fail2ban
    install_rkhunter
    install_clamav
    install_maldet
    harden_ssh
    harden_kernel
    enable_auto_updates

    # المرحلة 8: التقرير
    log_step "المرحلة 8/8: التقرير النهائي"
    generate_report
    send_report_email

    log_step "اكتمل بنجاح في $(date)"

    echo -e "\n${C_GREEN}${C_BOLD}"
    echo "  ╔══════════════════════════════════════════════════════════╗"
    echo "  ║                                                          ║"
    echo "  ║   🎉  تم تركيب CWP بنجاح مع جميع الإعدادات المتقدمة!    ║"
    echo "  ║                                                          ║"
    echo "  ║   📊  PHP: ${INSTALLED_PHP_VERSIONS[*]:-$DEFAULT_PHP_VERSION}"
    echo "  ║   🔒  Security: All enabled                              ║"
    echo "  ║                                                          ║"
    echo "  ║   ⚠️   أعد تشغيل السيرفر الآن: reboot                  ║"
    echo "  ║                                                          ║"
    echo "  ║   📄  راجع: /root/cwp-installation-report.txt            ║"
    echo "  ║                                                          ║"
    echo "  ╚══════════════════════════════════════════════════════════╝"
    echo -e "${C_RESET}\n"

    if [[ -t 0 ]]; then
        read -r -t 30 -p "إعادة تشغيل السيرفر الآن؟ (yes/no) [no]: " reboot_now || reboot_now="no"
        if [[ "$reboot_now" == "yes" ]]; then
            log "إعادة التشغيل خلال 10 ثوانٍ..."
            sleep 10
            reboot
        fi
    fi
}

main "$@"
