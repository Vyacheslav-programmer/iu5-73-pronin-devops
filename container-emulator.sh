#!/usr/bin/env bash
# =============================================================================
# Эмулятор контейнера на bash: cgroups v2 + veth + overlayfs + Alpine + FastAPI
# Запуск: sudo ./container-emulator.sh
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
CPU_MAX="50000 100000"                # Лимит CPU cgroup (50% одного ядра)
CGROUP_DIR="/sys/fs/cgroup/container" # Каталог cgroup v2
BASE_DIR=$(mktemp -d /tmp/container.XXXXXX)  # Временный каталог
ROOTFS_DIR="$BASE_DIR/rootfs"         # Распакованный minirootfs (lowerdir)
UPPER_DIR="$BASE_DIR/upper"           # upperdir overlayfs
WORK_DIR="$BASE_DIR/work"             # workdir overlayfs
MERGED_DIR="$BASE_DIR/merged"         # Точка монтирования overlayfs
STATE_DIR="$BASE_DIR/state"           # Каталог состояния (bind-mount в контейнер)
MINIROOTFS_TGZ="$BASE_DIR/minirootfs.tar.gz"

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
    # Убиваем init-процесс контейнера
    if [ -n "${CONTAINER_PID:-}" ]; then
        kill "$CONTAINER_PID" 2>/dev/null || true
        sleep 1
        kill -9 "$CONTAINER_PID" 2>/dev/null || true
    fi
    # Удаляем iptables-правила (DNAT, SNAT, MASQUERADE)
    iptables -t nat -D PREROUTING -p tcp --dport "$PORT" -j DNAT --to-destination "$CONTAINER_IP:$PORT" 2>/dev/null || true
    iptables -t nat -D OUTPUT -p tcp --dport "$PORT" -j DNAT --to-destination "$CONTAINER_IP:$PORT" 2>/dev/null || true
    iptables -t nat -D POSTROUTING -s 127.0.0.1 -d "$CONTAINER_IP" -p tcp --dport "$PORT" -j SNAT --to-source "$HOST_IP" 2>/dev/null || true
    iptables -t nat -D POSTROUTING -s "$SUBNET" -o "$HOST_IFACE" -j MASQUERADE 2>/dev/null || true
    # Удаляем veth-пару
    ip link del "$VETH_HOST" 2>/dev/null || true
    # Удаляем network namespace
    ip netns del "$NETNS" 2>/dev/null || true
    # Размонтируем bind-mounts и overlayfs
    umount "$MERGED_DIR/host" 2>/dev/null || true
    umount "$MERGED_DIR/dev" 2>/dev/null || true
    umount "$MERGED_DIR" 2>/dev/null || true
    # Удаляем временные каталоги
    rm -rf "$BASE_DIR" 2>/dev/null || true
    echo "==> Готово"
}
trap cleanup EXIT INT TERM

# --- 1. Скачивание Alpine minirootfs -----------------------------------------
echo "==> Скачивание Alpine minirootfs..."
mkdir -p "$ROOTFS_DIR" "$UPPER_DIR" "$WORK_DIR" "$MERGED_DIR" "$STATE_DIR"
MINIROOTFS_URL="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/releases/${ARCH}/alpine-minirootfs-${ALPINE_VERSION}.0-${ARCH}.tar.gz"
if ! curl -fsSL -o "$MINIROOTFS_TGZ" "$MINIROOTFS_URL"; then
    echo "==> Точная версия не найдена, ищем актуальный файл в списке..."
    LATEST_FILE=$(curl -fsSL "https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/releases/${ARCH}/" | grep -o 'alpine-minirootfs-[^"]*\.tar\.gz' | tail -1)
    curl -fsSL -o "$MINIROOTFS_TGZ" "https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/releases/${ARCH}/${LATEST_FILE}"
fi

# --- 2. Распаковка и overlayfs ------------------------------------------------
echo "==> Распаковка minirootfs..."
tar -xzf "$MINIROOTFS_TGZ" -C "$ROOTFS_DIR"
echo "==> Монтирование overlayfs..."
mount -t overlay overlay -o "lowerdir=$ROOTFS_DIR,upperdir=$UPPER_DIR,workdir=$WORK_DIR" "$MERGED_DIR"

# --- 3. Подготовка файловой системы контейнера --------------------------------
# resolv.conf для DNS внутри контейнера (копируем с хоста или используем 8.8.8.8)
if cp /etc/resolv.conf "$MERGED_DIR/etc/resolv.conf" 2>/dev/null; then
    echo "==> resolv.conf скопирован с хоста"
else
    echo "nameserver 8.8.8.8" > "$MERGED_DIR/etc/resolv.conf"
fi
# Bind-mount /dev хоста (нужен /dev/null, /dev/urandom и т.д.)
mount --bind /dev "$MERGED_DIR/dev"
# Bind-mount каталога состояния (для записи PID из контейнера)
mkdir -p "$MERGED_DIR/host"
mount --bind "$STATE_DIR" "$MERGED_DIR/host"

# --- 4. Cgroups v2 ------------------------------------------------------------
echo "==> Настройка cgroups v2..."
mkdir -p "$CGROUP_DIR"
echo "$MEMORY_LIMIT" > "$CGROUP_DIR/memory.max"
echo "$CPU_MAX" > "$CGROUP_DIR/cpu.max"

# --- 5. Сеть: netns, veth, NAT, DNAT ------------------------------------------
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
# Разрешаем маршрутизацию пакетов с локальными адресами назначения (нужно для DNAT с localhost: ответ контейнера приходит на veth0 с dst=127.0.0.1 после un-NAT)
sysctl -w net.ipv4.conf.all.route_localnet=1
sysctl -w "net.ipv4.conf.$VETH_HOST.route_localnet=1"
# Отключаем reverse path filtering для veth0 (иначе строгий rp_filter дропает ответы с src=127.0.0.1 после un-NAT)
sysctl -w "net.ipv4.conf.$VETH_HOST.rp_filter=0"
# NAT для исходящего трафика контейнера
iptables -t nat -A POSTROUTING -s "$SUBNET" -o "$HOST_IFACE" -j MASQUERADE
# DNAT для доступа снаружи (через внешний интерфейс)
iptables -t nat -A PREROUTING -p tcp --dport "$PORT" -j DNAT --to-destination "$CONTAINER_IP:$PORT"
# DNAT для доступа с localhost хоста (локальные пакеты идут через OUTPUT)
iptables -t nat -A OUTPUT -p tcp --dport "$PORT" -j DNAT --to-destination "$CONTAINER_IP:$PORT"
# SNAT источника для localhost-подключений, чтобы ответы возвращались на хост
iptables -t nat -A POSTROUTING -s 127.0.0.1 -d "$CONTAINER_IP" -p tcp --dport "$PORT" -j SNAT --to-source "$HOST_IP"

# --- 6. Скрипт инициализации контейнера ---------------------------------------
CONTAINER_INIT=$(cat <<'INIT_EOF'
#!/bin/sh
set -e

# Записываем PID init-процесса (для cgroups)
echo $$ > /host/container.pid

# Монтируем proc
mount -t proc proc /proc

# Монтируем tmpfs на /tmp
mount -t tmpfs tmpfs /tmp

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
)

# --- 7. Запуск контейнера ------------------------------------------------------
echo "==> Запуск контейнера..."
ip netns exec "$NETNS" unshare --mount --pid --uts --ipc --fork chroot "$MERGED_DIR" /bin/sh -c "$CONTAINER_INIT" &
BG_PID=$!

# Ждём, пока контейнер запишет PID в файл (сигнал готовности)
while [ ! -s "$STATE_DIR/container.pid" ]; do sleep 0.1; done

# Внутри контейнера $$ — это PID внутри его namespace (обычно 1),
# поэтому на хосте определяем реальный host PID init-процесса по дереву процессов:
# ip netns exec -> unshare -> init-процесс контейнера
UNSHARE_PID=$(pgrep -P "$BG_PID" | head -1)
CONTAINER_PID=$(pgrep -P "$UNSHARE_PID" | head -1)

# Добавляем init-процесс контейнера в cgroup
echo "$CONTAINER_PID" > "$CGROUP_DIR/cgroup.procs"
echo "==> Init-процесс контейнера (host PID): $CONTAINER_PID"

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
echo "  Контейнер запущен!"
echo "  FastAPI доступен: http://localhost:$PORT/health"
echo "  Ожидается ответ: {\"status\": \"ok\"}"
echo "  Для остановки нажмите Ctrl+C"
echo "======================================================"

# Держим скрипт живым, пока работает контейнер
wait "$BG_PID"