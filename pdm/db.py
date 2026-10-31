"""Подключение к существующей схеме MariaDB лабораторной 4."""
import json
import os
from pathlib import Path
import pymysql
from flask import current_app, g

ROOT = Path(__file__).resolve().parents[1]


def settings():
    config = {'host': '127.0.0.1', 'port': 3306, 'user': 'root',
              'password': '', 'database': 'sibka_pdm_v2'}
    file = ROOT / 'config.local.json'
    if file.exists():
        config.update(json.loads(file.read_text(encoding='utf-8')))
    for key in config:
        if 'PDM_DB_' + key.upper() in os.environ:
            config[key] = os.environ['PDM_DB_' + key.upper()]
    config['port'] = int(config['port'])
    return config


def connect(config=None):
    return pymysql.connect(**(config or settings()), charset='utf8mb4',
        cursorclass=pymysql.cursors.DictCursor, autocommit=False,
        connect_timeout=5, read_timeout=10, write_timeout=10,
        init_command="SET time_zone = '+00:00'")


def get_db():
    if 'db' not in g:
        g.db = connect(current_app.config.get('DB_SETTINGS'))
    return g.db


def query(sql, params=()):
    with get_db().cursor() as cursor:
        cursor.execute(sql, params)
        return cursor.fetchall()


def one(sql, params=()):
    rows = query(sql, params)
    return rows[0] if rows else None


def close_db(_=None):
    db = g.pop('db', None)
    if db is not None:
        db.close()
