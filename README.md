# 🚀 CWP Auto Installer v3.0 - النسخة المحسّنة

سكربت احترافي شامل لتركيب لوحة **CWP** تلقائياً مع **PHP متعدد الإصدارات** + **ionCube** + **حماية متقدمة** بدون أي تدخل من المستخدم.

---

## ✨ الجديد في v3.0

### 🐘 إصدارات PHP متعددة
يقوم السكربت بتركيب جميع الإصدارات الحالية المدعومة:
- ✅ **PHP 8.1** (مدعوم أمنياً)
- ✅ **PHP 8.2** (مدعوم - EOL ديسمبر 2026)
- ✅ **PHP 8.3** (مدعوم نشطاً)
- ✅ **PHP 8.4** (الأحدث - موصى به للإنتاج)

> ملاحظة: **PHP 8.5** متاح كأحدث إصدار لكن **ionCube لا يدعمه رسمياً بعد** (تجريبي فقط). لذلك تم استثناؤه.

### 🔐 ionCube Loader
- تركيب تلقائي **ionCube 15.0** لجميع إصدارات PHP
- نسخ ملفات `.so` للمسارات الصحيحة
- إضافة `zend_extension` في `php.ini` تلقائياً
- يدعم الإضافات التجارية مثل WHMCS، Blesta، إلخ

### 🛡️ الحماية المتقدمة الكاملة

| الأداة | الوظيفة |
|--------|---------|
| **CSF Firewall** | جدار حماية متقدم مع SYN flood، Port flood، LF brute-force |
| **ModSecurity** | جدار حماية لتطبيقات الويب (WAF) مع OWASP CRS |
| **Fail2Ban** | حماية من هجمات brute-force (SSH, FTP, Mail, HTTP) |
| **RKHunter** | كاشف Rootkit بفحص يومي تلقائي |
| **ClamAV** | مضاد فيروسات مع فحص أسبوعي |
| **Maldet** | كاشف برمجيات خبيثة Linux Malware Detect |
| **Kernel Hardening** | تأمين Kernel عبر `sysctl` |
| **PHP Hardening** | تعطيل دوال خطرة + إعدادات أمان |
| **SSH Hardening** | تغيير المنفذ + تأمين كامل |
| **Auto Updates** | تحديثات أمنية تلقائية يومية |

### ⚡ تحسين الأداء
- إعدادات PHP-FPM مُحسّنة لكل إصدار
- OPCache مُفعّل تلقائياً
- MySQL مُحسّن ديناميكياً حسب RAM
- realpath_cache مُحسّن

---

## 📋 المتطلبات

| المتطلب | الحد الأدنى | الموصى به |
|---------|------------|-----------|
| CPU | 1 vCPU | 2 vCPU+ |
| RAM | 2 GB | **4 GB+** |
| Disk | 20 GB | 40 GB+ |
| OS | EL7/8/9 (64-bit) | **AlmaLinux 9** |

**الأنظمة المدعومة:** AlmaLinux 8/9 ⭐، Rocky Linux 8/9، CentOS 7، Oracle Linux 8/9

---

## 🚀 الاستخدام

### 1) رفع السكربت للسيرفر

```bash
scp cwp-auto-installer-v3.sh root@SERVER_IP:/root/
```

### 2) تعديل الإعدادات (مهم!)

```bash
nano cwp-auto-installer-v3.sh
```

**القيم الأساسية اللي لازم تعدلها في القسم `1) CONFIGURATION`:**

```bash
SERVER_HOSTNAME="server1.example.com"   # FQDN حقيقي
ADMIN_EMAIL="admin@example.com"         # بريدك
TIMEZONE="Africa/Cairo"                 # المنطقة الزمنية
DEFAULT_PHP_VERSION="8.3"               # 8.1 / 8.2 / 8.3 / 8.4
SSH_PORT="2200"                         # منفذ SSH (مش 22)
```

**التحكم في إصدارات PHP:**
```bash
INSTALL_PHP_81="yes"   # خلي "no" لو مش محتاجه
INSTALL_PHP_82="yes"
INSTALL_PHP_83="yes"
INSTALL_PHP_84="yes"
```

**التحكم في الحماية:**
```bash
INSTALL_IONCUBE="yes"
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
```

### 3) منح الصلاحية والتشغيل

```bash
chmod +x cwp-auto-installer-v3.sh
sudo ./cwp-auto-installer-v3.sh
```

⏱️ **المدة المتوقعة:** 30-60 دقيقة (يبني Apache + PHP من المصدر + يحمل كل أدوات الحماية)

---

## 📊 مراحل التركيب (8 مراحل)

```
[1/8] الفحوصات الأولية      → OS, RAM, Disk, Network
[2/8] تجهيز النظام          → Hostname, Timezone, SELinux
[3/8] تحديث النظام          → System update + الحزم الأساسية
[4/8] تركيب CWP             → Apache + Default PHP + خدمات
[5/8] PHP متعدد + ionCube   → PHP 8.1/8.2/8.3/8.4 + ionCube
[6/8] تحسين MySQL           → ضبط ديناميكي حسب RAM
[7/8] الحماية المتقدمة      → CSF + ModSec + Fail2Ban + ...
[8/8] التقرير النهائي       → /root/cwp-installation-report.txt
```

---

## 🔧 إعدادات PHP المُطبّقة

**Performance:**
```ini
memory_limit = 256M
upload_max_filesize = 128M
post_max_size = 128M
max_execution_time = 300
max_input_vars = 5000
opcache.enable = 1
opcache.memory_consumption = 256
realpath_cache_size = 4096K
```

**Security:**
```ini
expose_php = Off
display_errors = Off
allow_url_fopen = Off
allow_url_include = Off
session.cookie_httponly = 1
session.cookie_secure = 1
disable_functions = exec,passthru,shell_exec,system,proc_open,popen,...
```

---

## 🛡️ تفاصيل الحماية

### CSF Firewall - الإعدادات المُطبّقة
- ✅ TESTING mode → Off (Production)
- ✅ SYN Flood protection (100/s, burst 150)
- ✅ Connection limit per IP (CT_LIMIT=300)
- ✅ Port flood (SSH=5/300s, HTTP=20/5s)
- ✅ Login Failure (SSH=3, FTP=5, SMTP=5, IMAP=5)
- ✅ Blocklists (DShield, Spamhaus, TOR)
- ✅ Permanent ban بعد 4 محاولات حظر متكررة
- ✅ تنبيهات بالبريد

### Fail2Ban - Jails المُفعّلة
- `sshd` - حماية SSH
- `apache-auth` - حماية لوحات Apache
- `apache-badbots` - حظر البوتات الضارة
- `apache-noscript` - حظر محاولات اختراق scripts
- `apache-overflows` - حماية overflow attacks
- `postfix` - حماية البريد الصادر
- `dovecot` - حماية IMAP/POP3
- `pure-ftpd` - حماية FTP

### Kernel Hardening (sysctl)
- IP Spoofing Protection
- SYN Cookies + TCP backlog
- Disable ICMP redirects
- Source route protection
- Log Martians
- Restrict dmesg + Hide kernel pointers
- Increased file descriptors

---

## 📁 المسارات المهمة بعد التركيب

```bash
# لوحة CWP
/usr/local/cwpsrv/

# PHP الافتراضي
/usr/local/php/bin/php
/usr/local/php/php.ini

# PHP-FPM المتعدد
/opt/alt/php81/usr/bin/php   # PHP 8.1
/opt/alt/php82/usr/bin/php   # PHP 8.2
/opt/alt/php83/usr/bin/php   # PHP 8.3
/opt/alt/php84/usr/bin/php   # PHP 8.4

# Apache
/usr/local/apache/

# MySQL
/var/lib/mysql/
/root/.my.cnf                 # بيانات root

# الأمان
/etc/csf/csf.conf            # CSF config
/etc/fail2ban/jail.local     # Fail2Ban
/etc/sysctl.d/99-cwp-security.conf  # Kernel
/usr/local/maldetect/        # Maldet

# السجلات
/var/log/cwp-installer-*.log
/var/log/messages
/usr/local/apache/logs/

# النسخ الاحتياطية
/root/cwp-installer-backups/
/root/cwp-installation-report.txt
```

---

## 🎯 الأوامر السريعة بعد التركيب

### تحقق من الخدمات
```bash
systemctl status httpd mariadb csf lfd fail2ban
```

### تحقق من PHP
```bash
php -v                              # الإصدار الافتراضي
/opt/alt/php81/usr/bin/php -v       # PHP 8.1
/opt/alt/php84/usr/bin/php -v       # PHP 8.4
```

### تحقق من ionCube
```bash
php -v
# يجب أن تظهر سطر مثل:
# with the ionCube PHP Loader v15.0...
```

### إدارة CSF
```bash
csf -l                # القواعد الحالية
csf -d 1.2.3.4        # حظر IP
csf -dr 1.2.3.4       # رفع الحظر
csf -r                # إعادة تحميل
csf -tf               # القائمة المؤقتة
csf -ta 1.2.3.4 3600  # حظر مؤقت ساعة
```

### Fail2Ban
```bash
fail2ban-client status
fail2ban-client status sshd
fail2ban-client set sshd unbanip 1.2.3.4
```

### فحوصات أمنية
```bash
rkhunter --check        # فحص Rootkit
clamscan -r /home       # فحص فيروسات
maldet -a /home         # فحص malware
maldet -u               # تحديث توقيعات Maldet
```

---

## ⚠️ ملاحظات مهمة

### قبل التشغيل
1. ✅ **نظام نظيف** فقط - لا تشغّله على سيرفر يحتوي على لوحات أخرى
2. ✅ **اضبط Hostname FQDN صحيح** قبل التشغيل
3. ✅ **حضّر A Record** للـ hostname على IP السيرفر
4. ✅ **ادفع للسيرفر** عبر console (مش SSH) في حالة تغيير منفذ SSH

### بعد التشغيل
1. 🔄 **أعد التشغيل** - `reboot` ضروري
2. 🔑 **ادخل من المنفذ الجديد:** `ssh -p 2200 root@SERVER_IP`
3. 🔐 **غيّر كلمة مرور MySQL Root** من اللوحة
4. 🔒 **فعّل AutoSSL** للـ hostname من SSL → AutoSSL
5. 📦 **اضبط النسخ الاحتياطي** من Backup Manager
6. 🐘 **اختر PHP الإصدار** المناسب لكل نطاق من PHP-FPM Selector

### تحذير الأمان
- إذا فعّلت `DISABLE_ROOT_PASSWORD_LOGIN="yes"` تأكد من رفع SSH key قبل ذلك!
- إذا تم حظرك من CSF: ادخل من console السيرفر ونفذ `csf -dr YOUR_IP`

---

## 🛠️ استكشاف الأخطاء

### خطأ في PHP-FPM
```bash
# إعادة تشغيل PHP-FPM
systemctl restart cwp-phpfpm

# تحقق من السجل
tail -100 /usr/local/cwp/logs/php-fpm.log
```

### ionCube لم يظهر
```bash
# تحقق من php.ini
grep ioncube /usr/local/php/php.ini

# تحقق من المسار
ls -la /usr/local/php/lib/php/extensions/

# إعادة التركيب يدوياً
cd /usr/local/src/ioncube
cp ioncube_loader_lin_8.3.so /usr/local/php/lib/php/extensions/
```

### استرجاع نسخة احتياطية
```bash
ls -la /root/cwp-installer-backups/
cp /root/cwp-installer-backups/sshd_config.bak /etc/ssh/sshd_config
systemctl restart sshd
```

---

## 📞 المؤلف

**Sherif - Dylanu** | 2026

📚 موارد:
- [Control Web Panel](https://control-webpanel.com)
- [ionCube Downloads](https://www.ioncube.com/loaders.php)
- [CSF Documentation](https://www.configserver.com/cp/csf.html)
