"""Локальный запуск: python run_web.py. Сервер доступен только на этом компьютере."""
import os
from pdm.app import create_app

app = create_app()
if __name__ == '__main__':
    app.run(host='127.0.0.1',port=int(os.environ.get('PDM_PORT','5001')),debug=False)
