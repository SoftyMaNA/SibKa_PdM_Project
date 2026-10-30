#!/bin/bash
set -e
cd "$(dirname "$0")"
if ! command -v python3 >/dev/null; then
  echo 'Установите Python 3.11 или новее с python.org.'
  read -r -p 'Нажмите Enter для выхода'
  exit 1
fi
python3 -c 'import sys; assert sys.version_info >= (3,11), "Требуется Python 3.11 или новее"'
if [ ! -x .venv/bin/python ]; then python3 -m venv .venv; fi
.venv/bin/python -m pip install -r requirements.txt
if [ ! -f config.local.json ]; then cp config.example.json config.local.json; fi
echo 'Запустите MySQL в XAMPP. Откройте http://127.0.0.1:5001'
.venv/bin/python run_web.py
