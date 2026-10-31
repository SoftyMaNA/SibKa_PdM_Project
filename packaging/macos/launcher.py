"""Запуск установленного SibKa PdM с пользовательской конфигурацией."""
import argparse
import json
import os
from pathlib import Path
import socket
import sys
import threading
import webbrowser

VERSION = '0.8.0'


def user_config():
    directory = Path.home() / 'Library' / 'Application Support' / 'SibKa PdM'
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    path = directory / 'config.local.json'
    defaults = dict(host='127.0.0.1', port=3306, user='root', password='', database='sibka_pdm_v2')
    if not path.exists():
        # Создание исключительно нового файла сохраняет настройки при обновлении.
        try:
            with path.open('x', encoding='utf-8') as handle:
                os.chmod(path, 0o600)
                json.dump(defaults, handle, ensure_ascii=False, indent=2)
        except FileExistsError:
            pass
    config = json.loads(path.read_text(encoding='utf-8'))
    if set(config) != set(defaults):
        raise ValueError('Поля настройки: host, port, user, password, database')
    config['port'] = int(config['port'])
    return config, path


def self_test():
    from pdm.app import create_app
    from pdm.services import sensor_condition
    app = create_app({'TESTING': True})
    assert sensor_condition(105, 'valid', 90, 105) == 'critical'
    assert sensor_condition(85, 'valid', 90, 105) == 'normal'
    # Ошибка параметров не требует обращения к БД и проверяет HTML-шаблоны.
    with app.test_client() as client:
        response = client.get('/not-found')
        assert response.status_code == 404
        assert 'text/html' in response.content_type
        response = client.get('/static/style.css')
        assert response.status_code == 200 and len(response.data) > 100
    print(f'SibKa PdM {VERSION}: frozen runtime, Flask, templates, CSS and thresholds OK')


def main():
    parser = argparse.ArgumentParser(description='SibKa PdM')
    parser.add_argument('--version', action='version', version=VERSION)
    parser.add_argument('--self-test', action='store_true')
    parser.add_argument('--no-browser', action='store_true')
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    config, path = user_config()
    from pdm.app import create_app
    app = create_app({'DB_SETTINGS': config})
    port = int(os.environ.get('PDM_PORT', '5001'))
    with socket.socket() as probe:
        try:
            probe.bind(('127.0.0.1', port))
        except OSError:
            print(f'Порт {port} занят. Остановите ранее запущенный сервер или задайте PDM_PORT.')
            return 1
    print(f'Настройки подключения: {path}')
    print(f'Открыть: http://127.0.0.1:{port}; остановить: Ctrl+C')
    if not args.no_browser:
        timer = threading.Timer(1.5, webbrowser.open, args=(f'http://127.0.0.1:{port}',))
        timer.daemon = True
        timer.start()
    app.run(host='127.0.0.1', port=port, debug=False, use_reloader=False)
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, OSError) as error:
        print(f'Не удалось запустить SibKa PdM: {error}', file=sys.stderr)
        sys.exit(1)
