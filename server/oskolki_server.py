#!/usr/bin/env python3
"""Сервер-комната «Осколков Долины».

Игру он НЕ считает. Он только:
  * заводит комнаты по коду из 4 букв;
  * собирает игроков в лобби;
  * при старте выдаёт всем одно «зерно» карты;
  * принимает действия игроков и раздаёт их всем в одном и том же порядке.
Каждый клиент (ПК или телефон) сам считает партию, и у всех получается одно и то же.
Запуск:  python3 oskolki_server.py --port 7777
"""
import argparse
import asyncio
import json
import logging
import random
import secrets
import string
import time

import websockets

VERSION = 1
MAX_PLAYERS = 10
MAX_ROOMS = 100
MAX_PER_IP = 8               # одновременных соединений с одного адреса (семья дома — это один адрес)
MAX_MSG_PER_SEC = 40         # быстрее живой игры в разы; чаще — отключаем
FIRST_MSG_TIMEOUT = 10       # столько секунд даём новому соединению назвать комнату
bans: dict = {}              # адрес -> до какого времени не пускаем
per_ip: dict = {}
ROOM_TTL = 6 * 3600          # пустую комнату держим 6 часов (на случай переподключения)
ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ"   # без I и O, чтобы не путать с 1 и 0
log = logging.getLogger("oskolki")


class Client:
    def __init__(self, ws, cid):
        self.ws = ws
        self.cid = cid
        self.token = secrets.token_hex(8)
        self.name = "Игрок"
        self.hero = 0
        self.ability = 0
        self.pet = False
        self.team = 0
        self.online = True

    def lobby_info(self):
        return {"cid": self.cid, "name": self.name, "hero": self.hero, "ability": self.ability,
                "pet": self.pet, "team": self.team, "online": self.online}


class Room:
    def __init__(self, code):
        self.code = code
        self.clients = {}       # cid -> Client (в порядке входа)
        self.host = None
        self.cfg = {}
        self.started = False
        self.seed = 0
        self.seats = []
        self.log = []           # все действия партии по порядку
        self.next_cid = 1
        self.touched = time.time()

    def alive(self):
        return [c for c in self.clients.values() if c.online]

    def lobby(self):
        return {"t": "lobby", "room": self.code, "host": self.host, "cfg": self.cfg,
                "players": [c.lobby_info() for c in self.clients.values()]}


rooms = {}


async def send(c, msg):
    try:
        await c.ws.send(json.dumps(msg, ensure_ascii=False))
    except Exception:
        pass


async def broadcast(room, msg):
    await asyncio.gather(*[send(c, msg) for c in room.clients.values() if c.online])


def new_code():
    for _ in range(200):
        code = "".join(random.choice(ALPHABET) for _ in range(4))
        if code not in rooms:
            return code
    raise RuntimeError("нет свободных кодов")


def clean_name(s):
    s = str(s or "").strip()[:14]
    return s or "Игрок"


def apply_profile(c, m):
    if "name" in m:
        c.name = clean_name(m["name"])
    for key, hi in (("hero", 9), ("ability", 7), ("team", 1)):
        if key in m:
            try:
                setattr(c, key, max(0, min(hi, int(m[key]))))
            except (TypeError, ValueError):
                pass
    if "pet" in m:
        c.pet = bool(m["pet"])


async def handle(ws):
    c = None
    room = None
    ip = ws.remote_address[0] if ws.remote_address else "?"
    now = time.time()
    if bans.get(ip, 0) > now or per_ip.get(ip, 0) >= MAX_PER_IP:
        await ws.close(1008, "too many connections")
        return
    per_ip[ip] = per_ip.get(ip, 0) + 1
    stamps: list = []

    async def _kick_if_silent():
        await asyncio.sleep(FIRST_MSG_TIMEOUT)
        if c is None:
            await ws.close(1008, "no hello")
    guard = asyncio.create_task(_kick_if_silent())
    try:
        async for raw in ws:
            t_now = time.time()
            stamps.append(t_now)
            while stamps and stamps[0] < t_now - 1.0:
                stamps.pop(0)
            if len(stamps) > MAX_MSG_PER_SEC:
                bans[ip] = t_now + 60
                log.info("flood от %s: отключаем на минуту", ip)
                await ws.close(1008, "flood")
                return
            if len(raw) > 200_000:
                continue
            try:
                m = json.loads(raw)
            except ValueError:
                continue
            t = m.get("t")
            if t == "ping":
                await ws.send('{"t":"pong"}')
                continue
            if c is None:
                # первое осмысленное сообщение: create / join / rejoin
                if t == "create":
                    if len(rooms) >= MAX_ROOMS:
                        await ws.send(json.dumps({"t": "err", "msg": "Сервер занят, попробуйте позже"}))
                        continue
                    room = Room(new_code())
                    rooms[room.code] = room
                    c = Client(ws, room.next_cid)
                    room.next_cid += 1
                    apply_profile(c, m)
                    room.clients[c.cid] = c
                    room.host = c.cid
                    room.cfg = m.get("cfg") or {}
                    await send(c, {"t": "joined", "room": room.code, "cid": c.cid, "token": c.token, "ver": VERSION})
                    await broadcast(room, room.lobby())
                    log.info("комната %s создана (%s)", room.code, c.name)
                elif t in ("join", "rejoin"):
                    code = str(m.get("room", "")).upper().strip()
                    room = rooms.get(code)
                    if room is None:
                        await ws.send(json.dumps({"t": "err", "msg": "Такой комнаты нет. Проверь код"}))
                        continue
                    if t == "rejoin":
                        old = next((x for x in room.clients.values() if x.token == m.get("token")), None)
                        if old is None:
                            await ws.send(json.dumps({"t": "err", "msg": "Не удалось вернуться в игру"}))
                            room = None
                            continue
                        c = old
                        c.ws = ws
                        c.online = True
                        await send(c, {"t": "joined", "room": room.code, "cid": c.cid, "token": c.token, "ver": VERSION})
                        if room.started:
                            await send(c, {"t": "start", "seed": room.seed, "cfg": room.cfg, "seats": room.seats, "replay": True})
                            for i in range(0, len(room.log), 50):
                                await send(c, {"t": "batch", "acts": room.log[i:i + 50]})
                            await send(c, {"t": "caught_up"})
                            await broadcast_act(room, {"k": "presence", "cid": c.cid, "online": True}, 0)
                        else:
                            await broadcast(room, room.lobby())
                    else:
                        if room.started:
                            await ws.send(json.dumps({"t": "err", "msg": "Игра уже идёт"}))
                            room = None
                            continue
                        if len(room.clients) >= MAX_PLAYERS:
                            await ws.send(json.dumps({"t": "err", "msg": "В комнате уже 10 игроков"}))
                            room = None
                            continue
                        c = Client(ws, room.next_cid)
                        room.next_cid += 1
                        apply_profile(c, m)
                        room.clients[c.cid] = c
                        await send(c, {"t": "joined", "room": room.code, "cid": c.cid, "token": c.token, "ver": VERSION})
                        await broadcast(room, room.lobby())
                        log.info("%s вошёл в комнату %s", c.name, room.code)
                else:
                    await ws.send(json.dumps({"t": "err", "msg": "Сначала создай комнату или войди по коду"}))
                continue
            room.touched = time.time()
            if t == "profile" and not room.started:
                apply_profile(c, m)
                await broadcast(room, room.lobby())
            elif t == "cfg" and c.cid == room.host and not room.started:
                room.cfg = m.get("cfg") or {}
                await broadcast(room, room.lobby())
            elif t == "start" and c.cid == room.host and not room.started:
                if len(room.clients) < 2:
                    await send(c, {"t": "err", "msg": "Для игры по сети нужно хотя бы 2 игрока"})
                    continue
                room.started = True
                room.seed = random.randint(10000, 99999)
                room.seats = []
                for i, x in enumerate(room.clients.values()):
                    s = x.lobby_info()
                    s["slot"] = i
                    room.seats.append(s)
                await broadcast(room, {"t": "start", "seed": room.seed, "cfg": room.cfg, "seats": room.seats})
                log.info("комната %s: старт, %d игроков, зерно %d", room.code, len(room.seats), room.seed)
            elif t == "act" and room.started:
                a = m.get("a")
                if isinstance(a, dict):
                    await broadcast_act(room, a, c.cid)
            elif t == "emote" and room.started:
                # быстрая реплика («Я тут!», «Быстрее!»): не часть игры, просто раздаём всем в комнате
                if time.time() - getattr(c, "last_emote", 0) >= 0.7:
                    c.last_emote = time.time()
                    try:
                        e = int(m.get("e", 0))
                    except (TypeError, ValueError):
                        e = 0
                    await broadcast(room, {"t": "emote", "cid": c.cid, "e": max(0, min(31, e))})
            elif t == "leave":
                break
    except websockets.ConnectionClosed:
        pass
    finally:
        guard.cancel()
        per_ip[ip] = max(0, per_ip.get(ip, 1) - 1)
        if c is not None and room is not None and c.ws is ws:
            c.online = False
            if not room.started:
                room.clients.pop(c.cid, None)
                if room.host == c.cid and room.clients:
                    room.host = next(iter(room.clients))
                if room.clients:
                    await broadcast(room, room.lobby())
            else:
                await broadcast_act(room, {"k": "presence", "cid": c.cid, "online": False}, 0)
            log.info("%s отключился от %s", c.name, room.code)


async def broadcast_act(room, a, cid):
    entry = {"seq": len(room.log) + 1, "cid": cid, "a": a}
    room.log.append(entry)
    await broadcast(room, {"t": "act", **entry})


async def janitor():
    while True:
        await asyncio.sleep(300)
        now = time.time()
        for code in list(rooms):
            r = rooms[code]
            if not r.alive() and now - r.touched > ROOM_TTL:
                del rooms[code]
                log.info("комната %s удалена", code)


async def main(port):
    asyncio.create_task(janitor())
    async with websockets.serve(handle, "0.0.0.0", port, max_size=300_000, ping_interval=20, ping_timeout=30, open_timeout=5):
        log.info("Сервер «Осколков Долины» слушает порт %d", port)
        await asyncio.Future()


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=7777)
    args = ap.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
    asyncio.run(main(args.port))
