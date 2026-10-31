"""Скриншоты работающего приложения для отчёта. Только отдельная база CI."""
from pathlib import Path
import os
import sys
from datetime import datetime,timedelta
from threading import Thread
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from werkzeug.serving import make_server
from playwright.sync_api import sync_playwright
from pdm.app import create_app
from pdm.db import settings

if settings()['database']!='sibka_pdm_ci':
    raise SystemExit('Скриншоты со сквозной записью создаются только на базе sibka_pdm_ci')
output=Path('docs/lab7/screenshots');output.mkdir(parents=True,exist_ok=True)
server=make_server('127.0.0.1',5001,create_app())
thread=Thread(target=server.serve_forever,daemon=True);thread.start()
try:
    with sync_playwright() as p:
        browser=p.chromium.launch()
        page=browser.new_page(viewport={'width':1440,'height':1100},device_scale_factor=1,locale='ru-RU')
        errors=[]
        page.on('pageerror',lambda error:errors.append(str(error)))
        for path,name in [('/','01_dashboard'),('/equipment/1','02_equipment'),('/diagnostics?equipment=1&node=1','03_diagnostics'),('/orders','04_orders')]:
            response=page.goto('http://127.0.0.1:5001'+path)
            assert response.status==200,(path,response.status)
            page.screenshot(path=str(output/(name+'.png')),full_page=True)
        page.goto('http://127.0.0.1:5001/orders/new?node=1')
        page.get_by_label('Название',exact=True).fill('Осмотр системы охлаждения двигателя SK-001')
        page.get_by_label('Описание неисправности',exact=True).fill('Проверить систему охлаждения и крепления двигателя. По последним измерениям температура и вибрация превысили предупредительные пороги.')
        page.get_by_label('Плановый срок UTC',exact=True).fill((datetime.utcnow()+timedelta(days=1)).strftime('%Y-%m-%dT%H:%M'))
        page.screenshot(path=str(output/'05_new_order.png'),full_page=True)
        page.get_by_role('button',name='Сохранить заявку',exact=True).click()
        page.wait_for_url('**/orders/*')
        assert page.get_by_role('status').inner_text().startswith('Заявка сохранена')
        number=page.locator('h1').inner_text()
        page.screenshot(path=str(output/'06_saved_order.png'),full_page=True)
        page.goto('http://127.0.0.1:5001/orders?q='+number)
        assert page.get_by_role('link',name=number,exact=True).count()==1
        page.screenshot(path=str(output/'07_search_result.png'),full_page=True)
        assert not errors,errors
        (output/'capture_result.txt').write_text('Сквозной браузерный сценарий выполнен.\nЗаявка: '+number+'\nJavaScript errors: 0\n',encoding='utf-8')
        browser.close()
finally:
    server.shutdown()
