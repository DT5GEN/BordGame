#!/usr/bin/env bash
# Установка сервера-комнаты «Осколков Долины» на VPS (Ubuntu / Debian).
# Запуск:  sudo bash install_server.sh [порт]      (по умолчанию порт 7777)
set -e
PORT="${1:-7777}"
DIR=/opt/oskolki
if [ "$(id -u)" != "0" ]; then echo "Запусти от root: sudo bash install_server.sh"; exit 1; fi
apt-get update -y
apt-get install -y python3 python3-venv
mkdir -p "$DIR"
cp "$(dirname "$0")/oskolki_server.py" "$DIR/oskolki_server.py"
python3 -m venv "$DIR/venv"
"$DIR/venv/bin/pip" install --quiet websockets
cat > /etc/systemd/system/oskolki.service <<UNIT
[Unit]
Description=Oskolki Doliny game server
After=network.target

[Service]
ExecStart=$DIR/venv/bin/python $DIR/oskolki_server.py --port $PORT
Restart=always
RestartSec=3
User=nobody
Group=nogroup

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now oskolki.service
if command -v ufw >/dev/null 2>&1; then ufw allow "$PORT"/tcp || true; fi
sleep 1
systemctl --no-pager status oskolki.service | head -8
echo
echo "Готово. Сервер слушает порт $PORT."
echo "Адрес для игры:  $(curl -s https://api.ipify.org 2>/dev/null || echo ВАШ_IP):$PORT"
echo "Если игра не подключается — откройте порт $PORT/tcp в панели вашего хостинга (firewall / security group)."
