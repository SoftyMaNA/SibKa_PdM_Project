"""Чтение последней телеметрии и атомарное создание ремонтной заявки."""
from datetime import datetime
from math import isfinite
from uuid import uuid4
from diagnostics import Thresholds
from .db import get_db, query, one

LABELS = {'normal': 'Норма', 'warning': 'Внимание', 'critical': 'Критично', 'unknown': 'Нет данных'}
PARAMETERS = {'temperature': 'Температура', 'vibration': 'Вибрация', 'pressure': 'Давление'}
UNITS = {'degC': '°C', 'mm/s': 'мм/с', 'bar': 'бар'}
ORDER_STATES = {'created': 'Создана', 'approved': 'Согласована', 'in_progress': 'В работе',
                'completed': 'Выполнена', 'closed': 'Закрыта', 'rejected': 'Отклонена'}
PRIORITIES = {'low': 'Низкий', 'medium': 'Средний', 'high': 'Высокий', 'critical': 'Критический'}


def sensor_condition(value, quality, warning, critical):
    """Не классифицировать отсутствующие и недостоверные измерения как норму."""
    if value is None or quality != 'valid':
        return 'unknown'
    try:
        value, warning, critical = float(value), float(warning), float(critical)
        Thresholds(warning, critical)
        if not isfinite(value):
            return 'unknown'
    except (TypeError, ValueError, OverflowError):
        return 'unknown'
    return 'critical' if value >= critical else 'warning' if value >= warning else 'normal'


def aggregate(states):
    if not states:
        return 'unknown'
    for level in ('critical', 'warning', 'unknown'):
        if level in states:
            return level
    return 'normal'


def readings(equipment_id=None, node_id=None):
    where, params = '', []
    if equipment_id is not None:
        where += ' AND n.id_equipment=%s'; params.append(equipment_id)
    if node_id is not None:
        where += ' AND n.id_node=%s'; params.append(node_id)
    rows = query('''SELECT s.*, n.id_equipment,n.node_name,t.id_reading,t.measured_at,
        t.value,t.quality,t.source FROM sensors s
        JOIN equipment_nodes n ON n.id_node=s.id_node
        LEFT JOIN telemetry t ON t.id_reading=(SELECT t2.id_reading FROM telemetry t2
          WHERE t2.id_sensor=s.id_sensor ORDER BY t2.measured_at DESC,t2.id_reading DESC LIMIT 1)
        WHERE s.is_active=1''' + where + ' ORDER BY s.id_node,s.id_sensor', params)
    for row in rows:
        row['condition'] = sensor_condition(row['value'], row['quality'], row['warning_high'], row['critical_high'])
    return rows


def fleet():
    rows = query('SELECT * FROM equipment ORDER BY equipment_code')
    all_readings = readings()
    for row in rows:
        data = [r for r in all_readings if r['id_equipment'] == row['id_equipment']]
        row['condition'] = aggregate([r['condition'] for r in data])
        dates = [r['measured_at'] for r in data if r['measured_at']]
        row['last_at'] = max(dates) if dates else None
        row['problem_nodes'] = ', '.join(dict.fromkeys(r['node_name'] for r in data if r['condition'] in ('warning', 'critical')))
    return rows


def create_order(node_id, author_id, title, description, priority, planned_at=None):
    """Проверить справочники, закрепить диагностику и записать заявку одной транзакцией."""
    db = get_db()
    try:
        # Узел блокируется на время операции, чтобы основание и заявка были согласованы.
        node = one('SELECT * FROM equipment_nodes WHERE id_node=%s FOR UPDATE', (node_id,))
        if not node:
            raise ValueError('Выберите существующий узел техники.')
        author = one('SELECT * FROM specialists WHERE id_specialist=%s AND is_active=1', (author_id,))
        if not author:
            raise ValueError('Выберите действующего автора заявки.')
        if not title or not 3 <= len(title) <= 200:
            raise ValueError('Название заявки должно содержать от 3 до 200 символов.')
        if not description or not 10 <= len(description) <= 4000:
            raise ValueError('Описание должно содержать от 10 до 4000 символов.')
        if priority not in PRIORITIES:
            raise ValueError('Выберите допустимый приоритет.')
        now = datetime.utcnow()
        if planned_at and planned_at < now:
            raise ValueError('Плановый срок должен быть позже текущего времени UTC.')
        data = readings(node_id=node_id)
        alerts = [r for r in data if r['condition'] in ('warning', 'critical')]
        if not alerts:
            raise ValueError('Для выбранного узла нет достоверного порогового отклонения.')
        alerts.sort(key=lambda r: (r['condition'] == 'critical', r['measured_at']), reverse=True)
        basis = alerts[0]
        conclusion = (f"{PARAMETERS[basis['parameter']]}: {basis['value']} {UNITS[basis['unit']]}; "
                      f"состояние: {LABELS[basis['condition']]}. Измерение UTC: {basis['measured_at']}.")
        with db.cursor() as c:
            c.execute('''INSERT INTO diagnostics(id_reading,severity,warning_high_used,critical_high_used,conclusion)
                VALUES(%s,%s,%s,%s,%s) ON DUPLICATE KEY UPDATE id_diagnostic=LAST_INSERT_ID(id_diagnostic)''',
                (basis['id_reading'],basis['condition'],basis['warning_high'],basis['critical_high'],conclusion))
            diagnostic = one('SELECT id_diagnostic FROM diagnostics WHERE id_reading=%s', (basis['id_reading'],))
            number = 'ТО-' + now.strftime('%Y%m%d') + '-' + uuid4().hex[:10].upper()
            c.execute('''INSERT INTO repair_orders(order_number,id_node,id_diagnostic,created_by,title,
                description,priority,planned_at) VALUES(%s,%s,%s,%s,%s,%s,%s,%s)''',
                (number,node_id,diagnostic['id_diagnostic'],author_id,title,description,priority,planned_at))
            order_id = c.lastrowid
        db.commit()
        return order_id
    except Exception:
        db.rollback()
        raise


def orders(status='', search=''):
    sql = '''SELECT o.*,e.equipment_code,n.node_name,s.full_name AS author,a.full_name AS assignee
        FROM repair_orders o JOIN equipment_nodes n ON n.id_node=o.id_node
        JOIN equipment e ON e.id_equipment=n.id_equipment
        JOIN specialists s ON s.id_specialist=o.created_by
        LEFT JOIN specialists a ON a.id_specialist=o.assigned_to WHERE 1=1'''
    params = []
    if status:
        sql += ' AND o.status=%s';params.append(status)
    if search:
        sql += ' AND (o.order_number LIKE %s OR e.equipment_code LIKE %s)';params += ['%'+search+'%']*2
    return query(sql+' ORDER BY o.created_at DESC,o.id_order DESC',params)
