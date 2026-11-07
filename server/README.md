# Сервер игры по сети

Это маленький сервер-«почтальон». Он не считает игру: заводит комнаты по коду из 4 букв,
собирает игроков и раздаёт всем ходы в одном порядке. Игру считает каждый клиент
(ПК и телефон) сам, поэтому у всех получается одно и то же.

## Установка на VPS (Ubuntu / Debian)

```bash
# 1. скопируйте на VPS файлы oskolki_server.py и install_server.sh (например через scp или WinSCP)
scp oskolki_server.py install_server.sh root@ВАШ_IP:/root/

# 2. зайдите на VPS и запустите установку
ssh root@ВАШ_IP
sudo bash install_server.sh 7777
```

Скрипт ставит Python, создаёт службу `oskolki` (запускается сам после перезагрузки) и открывает порт.
Если у хостинга есть свой firewall (панель провайдера), откройте там TCP-порт 7777.

## Полезные команды

```bash
systemctl status oskolki          # работает ли
journalctl -u oskolki -f          # кто заходит и что происходит
systemctl restart oskolki         # перезапуск
```

## Проверка без игры

```bash
python3 -m pip install websockets
python3 oskolki_server.py --port 7777
```
