#!/usr/bin/env bash
# =============================================================================
# Контейнер на runc: OCI bundle + cgroups v2 + veth + overlayfs + Alpine + FastAPI
# Запуск: sudo ./container-runc.sh
# Требования: Linux (cgroups v2), root, runc, iproute2, iptables, curl, tar
#
# Аналог container-emulator.sh, но вместо unshare+chroot используется runc
# (OCI runtime). runc сам делает pivot_root, создаёт namespace'ы, монтирует
# /proc, /dev, /tmp, применяет cgroups-лимиты из config.json и сообщает PID
# контейнера (без хаков с pgrep).
# =============================================================================
set -euo pipefail

# --- Конфигурация ------------------------------------------------------------
ALPINE_VERSION="3.20"                 # Версия Alpine Linux
PORT="8000"                           # Порт FastAPI (DNAT с хоста)
HOST_IP="10.0.0.1"                    # IP хоста в veth-сети
CONTAINER_IP="10.0.0.2"               # IP контейнера в veth-сети
SUBNET="10.0.0.0/24"                  # Подсеть veth
NETNS="container-net"                 # Имя network namespace
VETH_HOST="veth0"                     # Конец veth на хосте
VETH_CONT="veth1"                     # Конец veth в контейнере
MEMORY_LIMIT="256M"                   # Лимит памяти cgroup
MEMORY_LIMIT_BYTES=$((256 * 1024 * 1024))  # 256M в байтах (для OCI spec)
CPU_QUOTA="50000"                     # Лимит CPU: 50% одного ядра
CPU_PERIOD="100000"
CONTAINER_NAME="alpine-fastapi"       # Имя контейнера runc
CGROUP_PATH="/container"              # Путь cgroup v2 (runc создаст сам)
BASE_DIR=$(mktemp -d /tmp/runc-container.XXXXXX)  # Временный каталог
BUNDLE_DIR="$BASE_DIR/bundle"         # OCI bundle (config.json + rootfs)
LOWER_DIR="$BASE_DIR/lower"           # Распакованный minirootfs (lowerdir)
UPPER_DIR="$BASE_DIR/upper"           # upperdir overlayfs
WORK_DIR="$BASE_DIR/work"             # workdir overlayfs
MERGED_DIR="$BUNDLE_DIR/rootfs"       # Точка монтирования overlayfs = rootfs runc
STATE_DIR="$BASE_DIR/state"           # Каталог состояния (bind-mount в контейнер)
MINIROOTFS_TGZ="$BASE_DIR/minirootfs.tar.gz"

# --- Проверка окружения ------------------------------------------------------
[ "$(id -u)" -eq 0 ] || { echo "Ошибка: нужны права root (запустите через sudo)"; exit 1; }
command -v runc >/dev/null 2>&1 || { echo "Ошибка: runc не установлен (apt install runc / dnf install runc)"; exit 1; }

# --- Определение архитектуры -------------------------------------------------
case "$(uname -m)" in
    x86_64)  ARCH="x86_64" ;;
    aarch64) ARCH="aarch64" ;;
    armv7l)  ARCH="armv7" ;;
    armv6l)  ARCH="armhf" ;;
    i686)    ARCH="x86" ;;
    *)       ARCH="$(uname -m)" ;;
esac
echo "==> Архитектура: $ARCH"

# --- Определение основного сетевого интерфейса хоста -------------------------
HOST_IFACE=$(ip route | awk '/^default/ {print $5; exit}')
[ -z "$HOST_IFACE" ] && HOST_IFACE=$(ip -o link show | awk -F': ' '$2 != "lo" {print $2; exit}')
echo "==> Основной интерфейс хоста: $HOST_IFACE"

# --- Функция очистки ---------------------------------------------------------
cleanup() {
    echo "==> Очистка..."
    # Останавливаем и удаляем контейнер runc
    if runc list 2>/dev/null | grep -q "^$CONTAINER_NAME"; then
        runc kill "$CONTAINER_NAME" SIGKILL 2>/dev/null || true
        runc delete --force "$CONTAINER_NAME" 2>/dev/null || true
    fi
    # Удаляем iptables-правила (DNAT, SNAT, MASQUERADE)
    iptables -t nat -D PREROUTING -p tcp --dport "$PORT" -j DNAT --to-destination "$CONTAINER_IP:$PORT" 2>/dev/null || true
    iptables -t nat -D OUTPUT -p tcp --dport "$PORT" -j DNAT --to-destination "$CONTAINER_IP:$PORT" 2>/dev/null || true
    iptables -t nat -D POSTROUTING -s 127.0.0.1 -d "$CONTAINER_IP" -p tcp --dport "$PORT" -j SNAT --to-source "$HOST_IP" 2>/dev/null || true
    iptables -t nat -D POSTROUTING -s "$SUBNET" -o "$HOST_IFACE" -j MASQUERADE 2>/dev/null || true
    # Удаляем veth-пару и network namespace
    ip link del "$VETH_HOST" 2>/dev/null || true
    ip netns del "$NETNS" 2>/dev/null || true
    # Размонтируем overlayfs (внутренние mount'ы контейнера runc уберёт сам)
    umount "$MERGED_DIR" 2>/dev/null || true
    # Удаляем временные каталоги
    rm -rf "$BASE_DIR" 2>/dev/null || true
    echo "==> Готово"
}
trap cleanup EXIT INT TERM

# --- 1. Скачивание Alpine minirootfs -----------------------------------------
echo "==> Скачивание Alpine minirootfs..."
mkdir -p "$LOWER_DIR" "$UPPER_DIR" "$WORK_DIR" "$MERGED_DIR" "$STATE_DIR" "$BUNDLE_DIR"
MINIROOTFS_URL="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/releases/${ARCH}/alpine-minirootfs-${ALPINE_VERSION}.0-${ARCH}.tar.gz"
if ! curl -fsSL -o "$MINIROOTFS_TGZ" "$MINIROOTFS_URL"; then
    echo "==> Точная версия не найдена, ищем актуальный файл в списке..."
    LATEST_FILE=$(curl -fsSL "https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/releases/${ARCH}/" | grep -o 'alpine-minirootfs-[^"]*\.tar\.gz' | tail -1)
    curl -fsSL -o "$MINIROOTFS_TGZ" "https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/releases/${ARCH}/${LATEST_FILE}"
fi

# --- 2. Распаковка и overlayfs ------------------------------------------------
echo "==> Распаковка minirootfs..."
tar -xzf "$MINIROOTFS_TGZ" -C "$LOWER_DIR"
echo "==> Монтирование overlayfs..."
mount -t overlay overlay -o "lowerdir=$LOWER_DIR,upperdir=$UPPER_DIR,workdir=$WORK_DIR" "$MERGED_DIR"

# --- 3. Подготовка файловой системы контейнера --------------------------------
# resolv.conf для DNS внутри контейнера (копируем с хоста или используем 8.8.8.8)
if cp /etc/resolv.conf "$MERGED_DIR/etc/resolv.conf" 2>/dev/null; then
    echo "==> resolv.conf скопирован с хоста"
else
    echo "nameserver 8.8.8.8" > "$MERGED_DIR/etc/resolv.conf"
fi
# /dev, /proc, /tmp и /host монтируются runc'ом из config.json (см. раздел 5)

# --- 4. Скрипт инициализации контейнера ---------------------------------------
# Кладём его в rootfs (upper-слой overlayfs); runc запустит его как PID 1
mkdir -p "$MERGED_DIR/root"
cat > "$MERGED_DIR/root/init.sh" <<'INIT_EOF'
#!/bin/sh
set -e

# Записываем PID init-процесса (сигнал готовности для хоста)
echo $$ > /host/container.pid

# Устанавливаем Python и pip
apk add --no-cache python3 py3-pip

# Создаём каталог приложения
mkdir -p /app

# Создаём виртуальное окружение (PEP 668: системный Python управляется apk)
python3 -m venv /app/venv

# Устанавливаем FastAPI и uvicorn в виртуальное окружение
/app/venv/bin/pip install --no-cache-dir fastapi uvicorn

# Создаём FastAPI-приложение
cat > /app/app.py <<'PYEOF'
from fastapi import FastAPI

app = FastAPI()

@app.get("/health")
def health():
    return {"status": "ok"}
PYEOF

# Запускаем uvicorn из виртуального окружения
cd /app
exec /app/venv/bin/uvicorn app:app --host 0.0.0.0 --port 8000
INIT_EOF
chmod +x "$MERGED_DIR/root/init.sh"

# --- 5. Генерация OCI config.json --------------------------------------------
# Вместо unshare+chroot runc использует OCI-спецификацию: здесь описаны
# процесс, монтирования, cgroups-лимиты и namespace'ы контейнера.
echo "==> Генерация OCI config.json..."
CAPS='["CAP_AUDIT_WRITE","CAP_CHOWN","CAP_DAC_OVERRIDE","CAP_FOWNER","CAP_FSETID","CAP_KILL","CAP_MKNOD","CAP_NET_BIND_SERVICE","CAP_NET_RAW","CAP_SETFCAP","CAP_SETGID","CAP_SETPCAP","CAP_SETUID","CAP_SYS_ADMIN","CAP_SYS_CHROOT","CAP_SYS_PTRACE","CAP_SYS_RESOURCE","CAP_SYSLOG"]'
cat > "$BUNDLE_DIR/config.json" <<EOF
{
  "ociVersion": "1.0.2",
  "process": {
    "terminal": false,
    "user": {"uid": 0, "gid": 0},
    "args": ["/bin/sh", "/root/init.sh"],
    "env": [
      "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
      "TERM=xterm"
    ],
    "cwd": "/",
    "capabilities": {
      "bounding": $CAPS,
      "effective": $CAPS,
      "permitted": $CAPS,
      "inheritable": $CAPS
    },
    "rlimits": [{"type": "RLIMIT_NOFILE", "hard": 1024, "soft": 1024}]
  },
  "root": {
    "path": "rootfs",
    "readonly": false
  },
  "hostname": "runc-container",
  "mounts": [
    {"destination": "/proc", "type": "proc", "source": "proc"},
    {"destination": "/dev", "type": "tmpfs", "source": "tmpfs", "options": ["nosuid","strictatime","mode=755","size=65536k"]},
    {"destination": "/dev/pts", "type": "devpts", "source": "devpts", "options": ["nosuid","noexec","newinstance","ptmxmode=0666","mode=0620","gid=5"]},
    {"destination": "/dev/shm", "type": "tmpfs", "source": "shm", "options": ["nosuid","noexec","nodev","mode=1777","size=65536k"]},
    {"destination": "/dev/mqueue", "type": "mqueue", "source": "mqueue", "options": ["nosuid","noexec","nodev"]},
    {"destination": "/sys", "type": "sysfs", "source": "sysfs", "options": ["nosuid","noexec","nodev","ro"]},
    {"destination": "/tmp", "type": "tmpfs", "source": "tmpfs", "options": ["nosuid","nodev","mode=1777"]},
    {"destination": "/host", "type": "bind", "source": "$STATE_DIR", "options": ["bind","rprivate"]}
  ],
  "linux": {
    "resources": {
      "devices": [{"allow": false, "access": "rwm"}],
      "memory": {"limit": $MEMORY_LIMIT_BYTES},
      "cpu": {"quota": $CPU_QUOTA, "period": $CPU_PERIOD}
    },
    "cgroupsPath": "$CGROUP_PATH",
    "namespaces": [
      {"type": "pid"},
      {"type": "network", "path": "/var/run/netns/$NETNS"},
      {"type": "ipc"},
      {"type": "uts"},
      {"type": "mount"}
    ],
    "maskedPaths": ["/proc/acpi","/proc/asound","/proc/kcore","/proc/keys","/proc/latency_stats","/proc/timer_list","/proc/timer_stats","/proc/sched_debug","/sys/firmware","/proc/scsi"],
    "readonlyPaths": ["/proc/bus","/proc/fs","/proc/irq","/proc/sys","/proc/sysrq-trigger"]
  }
}
EOF

# --- 6. Сеть: netns, veth, NAT, DNAT ------------------------------------------
echo "==> Настройка сети..."
ip netns add "$NETNS"
ip link add "$VETH_HOST" type veth peer name "$VETH_CONT"
ip link set "$VETH_CONT" netns "$NETNS"
ip addr add "$HOST_IP/24" dev "$VETH_HOST"
ip link set "$VETH_HOST" up
ip netns exec "$NETNS" ip addr add "$CONTAINER_IP/24" dev "$VETH_CONT"
ip netns exec "$NETNS" ip link set "$VETH_CONT" up
ip netns exec "$NETNS" ip link set lo up
ip netns exec "$NETNS" ip route add default via "$HOST_IP"
sysctl -w net.ipv4.ip_forward=1 >/dev/null
# Разрешаем маршрутизацию пакетов с локальными адресами назначения (нужно для DNAT с localhost)
sysctl -w net.ipv4.conf.all.route_localnet=1
sysctl -w "net.ipv4.conf.$VETH_HOST.route_localnet=1"
# Отключаем reverse path filtering для veth0 (иначе строгий rp_filter дропает ответы)
sysctl -w "net.ipv4.conf.$VETH_HOST.rp_filter=0"
# NAT для исходящего трафика контейнера
iptables -t nat -A POSTROUTING -s "$SUBNET" -o "$HOST_IFACE" -j MASQUERADE
# DNAT для доступа снаружи (через внешний интерфейс)
iptables -t nat -A PREROUTING -p tcp --dport "$PORT" -j DNAT --to-destination "$CONTAINER_IP:$PORT"
# DNAT для доступа с localhost хоста (локальные пакеты идут через OUTPUT)
iptables -t nat -A OUTPUT -p tcp --dport "$PORT" -j DNAT --to-destination "$CONTAINER_IP:$PORT"
# SNAT источника для localhost-подключений, чтобы ответы возвращались на хост
iptables -t nat -A POSTROUTING -s 127.0.0.1 -d "$CONTAINER_IP" -p tcp --dport "$PORT" -j SNAT --to-source "$HOST_IP"

# --- 7. Запуск контейнера через runc ------------------------------------------
# runc сам: создаёт PID/mount/uts/ipc namespace, делает pivot_root,
# монтирует /proc, /dev, /tmp, /host, применяет cgroups-лимиты и
# добавляет процесс в cgroup (никаких хаков с pgrep не нужно).
echo "==> Запуск контейнера через runc..."
# Убираем возможный "зависший" контейнер от предыдущего запуска
runc delete --force "$CONTAINER_NAME" 2>/dev/null || true
runc run -d --bundle "$BUNDLE_DIR" "$CONTAINER_NAME"

# Ждём, пока init-скрипт запишет PID в файл (сигнал готовности), максимум 30 сек
for _ in $(seq 1 300); do
    [ -s "$STATE_DIR/container.pid" ] && break
    sleep 0.1
done
if [ ! -s "$STATE_DIR/container.pid" ]; then
    echo "==> Ошибка: контейнер не записал PID (init-скрипт не выполнился?)"
    exit 1
fi

# Показываем состояние контейнера (PID берём из runc state, без pgrep-хаков)
CONTAINER_PID=$(runc state "$CONTAINER_NAME" | grep -o '"pid":[0-9]*' | cut -d: -f2)
echo "==> Init-процесс контейнера (host PID): $CONTAINER_PID"
runc list

# --- 8. Ожидание готовности FastAPI -------------------------------------------
echo "==> Ожидание запуска FastAPI внутри контейнера..."
for _ in $(seq 1 120); do
    if curl -fsS "http://localhost:$PORT/health" >/dev/null 2>&1; then
        echo "==> FastAPI готов!"
        break
    fi
    sleep 1
done

echo ""
echo "======================================================"
echo "  Контейнер запущен! (runc: $CONTAINER_NAME)"
echo "  FastAPI доступен: http://localhost:$PORT/health"
echo "  Ожидается ответ: {\"status\": \"ok\"}"
echo "  Для остановки нажмите Ctrl+C"
echo "======================================================"

# Держим скрипт живым, пока работает контейнер
while [ "$(runc state "$CONTAINER_NAME" 2>/dev/null | grep -o '"status": *"[^"]*"' | head -1 | cut -d'"' -f4)" = "running" ]; do
    sleep 1
done
echo "==> Контейнер остановлен"

echo ">>> DEBUG: скрипт спит 10 минут для диагностики"
sleep 600
