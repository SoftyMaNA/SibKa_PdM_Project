"""Сквозные проверки только на отдельной тестовой MariaDB."""
import os
from datetime import datetime,timedelta
from uuid import uuid4
import pytest
from pdm.app import create_app
from pdm.db import connect, settings

pytestmark=pytest.mark.skipif(os.environ.get('PDM_INTEGRATION')!='1',reason='Требуется отдельная тестовая MariaDB')


@pytest.fixture
def app():
    # Запрещено запускать изменяющие проверки на рабочей базе пользователя.
    config=settings()
    if config['database']!='sibka_pdm_ci':
        pytest.fail('Интеграционные тесты требуют базу sibka_pdm_ci')
    return create_app({'TESTING':True,'SECRET_KEY':'integration-test-key','DB_SETTINGS':config})


def csrf(client,node=1):
    assert client.get(f'/orders/new?node={node}').status_code==200
    with client.session_transaction() as session: return session['csrf']


def payload(token):
    return dict(csrf=token,node='1',author='1',title='Проверка охлаждения двигателя',
                description='Температура двигателя достигла критической границы. Требуется осмотр.',
                priority='high',planned_at=(datetime.utcnow()+timedelta(days=1)).strftime('%Y-%m-%dT%H:%M'))


def test_order_is_persisted_with_diagnostic_and_trigger_history(app):
    client=app.test_client();data=payload(csrf(client));data['title']+=' '+uuid4().hex[:8]
    response=client.post('/orders/new',data=data)
    assert response.status_code==303
    location=response.headers['Location'];id_order=int(location.rsplit('/',1)[1])
    # Новое соединение подтверждает commit, а не только состояние HTTP-сессии.
    db=connect(app.config['DB_SETTINGS'])
    try:
        with db.cursor() as c:
            c.execute('SELECT * FROM repair_orders WHERE id_order=%s',(id_order,));row=c.fetchone()
            assert row['title']==data['title'] and row['status']=='created'
            c.execute('''SELECT n.id_node FROM diagnostics d JOIN telemetry t ON t.id_reading=d.id_reading
                JOIN sensors s ON s.id_sensor=t.id_sensor JOIN equipment_nodes n ON n.id_node=s.id_node
                WHERE d.id_diagnostic=%s''',(row['id_diagnostic'],))
            assert c.fetchone()['id_node']==row['id_node']
            c.execute('SELECT * FROM order_status_history WHERE id_order=%s',(id_order,));history=c.fetchall()
            assert len(history)==1 and history[0]['new_status']=='created'
        fresh_client=app.test_client()
        assert data['title'] in fresh_client.get(location).get_data(as_text=True)
        assert row['order_number'] in fresh_client.get('/orders?status=created').get_data(as_text=True)
    finally:
        with db.cursor() as c:
            c.execute('DELETE FROM order_status_history WHERE id_order=%s',(id_order,))
            c.execute('DELETE FROM repair_orders WHERE id_order=%s',(id_order,))
        db.commit();db.close()


def test_pages_validation_and_csrf(app):
    client=app.test_client()
    for url in ['/','/equipment','/equipment/1','/diagnostics','/diagnostics?equipment=2&node=3','/orders','/orders/1']:
        assert client.get(url).status_code==200,url
    assert client.get('/equipment/999999').status_code==404
    assert client.get('/diagnostics?equipment=1&node=3').status_code==404
    assert client.get('/orders?status=anything').status_code==400
    assert client.post('/orders/new',data=payload('wrong')).status_code==400
    token=csrf(client);data=payload(token)
    for field,value in [('title',''),('description','коротко'),('priority','bad'),('author','999999'),('node','999999')]:
        bad=dict(data);bad[field]=value
        assert client.post('/orders/new',data=bad).status_code==422,field
    assert client.get('/orders?q=%27%20OR%201%3D1--').status_code==200
