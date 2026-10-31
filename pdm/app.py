"""HTTP-маршруты локального прототипа."""
from datetime import datetime
import os
import secrets
import pymysql
from flask import Flask, abort, flash, redirect, render_template, request, session, url_for
from .db import close_db, one, query
from .services import (LABELS, PARAMETERS, UNITS, ORDER_STATES, PRIORITIES, aggregate,
                       create_order, fleet, readings, orders)


def create_app(test_config=None):
    app = Flask(__name__)
    app.config.update(SECRET_KEY=os.environ.get('PDM_SECRET_KEY') or secrets.token_hex(32),
                      MAX_CONTENT_LENGTH=64*1024, SESSION_COOKIE_SAMESITE='Lax', SESSION_COOKIE_HTTPONLY=True)
    if test_config:
        app.config.update(test_config)
    app.teardown_appcontext(close_db)

    @app.before_request
    def csrf():
        session.setdefault('csrf', secrets.token_hex(24))
        if request.method == 'POST' and not secrets.compare_digest(session['csrf'],request.form.get('csrf','')):
            abort(400, description='Обновите страницу и повторите отправку формы.')

    @app.context_processor
    def context():
        return dict(labels=LABELS, parameters=PARAMETERS, units=UNITS, states=ORDER_STATES,
                    priorities=PRIORITIES, now=datetime.utcnow())

    @app.template_filter('dt')
    def dt(value):
        return value.strftime('%d.%m.%Y %H:%M') if value else 'Нет измерений'

    @app.template_filter('num')
    def num(value):
        return f'{float(value):g}' if value is not None else '–'

    @app.errorhandler(pymysql.MySQLError)
    def database_error(error):
        app.logger.error('Database operation failed: %s',type(error).__name__)
        return render_template('error.html', title='Подключение к базе данных',
            message='Не удалось выполнить операцию. Проверьте запуск MySQL в XAMPP, имя базы sibka_pdm_v2 и config.local.json.'),503

    @app.errorhandler(404)
    @app.errorhandler(400)
    def request_error(error):
        return render_template('error.html',title='Запрос не выполнен',message=error.description),error.code

    @app.get('/')
    def dashboard():
        machines=fleet();rows=orders()
        counts={k:sum(e['condition']==k for e in machines) for k in LABELS}
        return render_template('dashboard.html',title='Обзор парка техники',active='overview',
            machines=machines,counts=counts,active_orders=sum(o['status'] not in ('closed','rejected') for o in rows))

    @app.get('/equipment')
    def equipment_list():
        machines=fleet();term=request.args.get('q','').strip().lower()
        if term: machines=[e for e in machines if term in (e['equipment_code']+' '+e['model']).lower()]
        return render_template('equipment_list.html',title='Техника',active='equipment',machines=machines,term=term)

    @app.get('/equipment/<int:equipment_id>')
    def equipment_card(equipment_id):
        item=one('SELECT * FROM equipment WHERE id_equipment=%s',(equipment_id,))
        if not item: abort(404,description='Техника не найдена.')
        nodes=query('SELECT * FROM equipment_nodes WHERE id_equipment=%s ORDER BY id_node',(equipment_id,))
        data=readings(equipment_id=equipment_id)
        for node in nodes:
            node['readings']=[r for r in data if r['id_node']==node['id_node']]
            node['condition']=aggregate([r['condition'] for r in node['readings']])
        recent=query('''SELECT o.*,n.node_name FROM repair_orders o JOIN equipment_nodes n ON n.id_node=o.id_node
            WHERE n.id_equipment=%s ORDER BY o.created_at DESC LIMIT 5''',(equipment_id,))
        return render_template('equipment.html',title=f"Карточка техники {item['equipment_code']}",active='equipment',item=item,nodes=nodes,recent=recent)

    @app.get('/diagnostics')
    def diagnostics():
        machines=fleet();eq=request.args.get('equipment',type=int)
        if eq is None and machines: eq=machines[0]['id_equipment']
        item=one('SELECT * FROM equipment WHERE id_equipment=%s',(eq,))
        if not item: abort(404,description='Техника не найдена.')
        nodes=query('SELECT * FROM equipment_nodes WHERE id_equipment=%s ORDER BY id_node',(eq,))
        node_id=request.args.get('node',type=int) or (nodes[0]['id_node'] if nodes else None)
        if node_id not in [n['id_node'] for n in nodes]: abort(404,description='Узел техники не найден.')
        data=readings(node_id=node_id)
        for row in data:
            row['series']=list(reversed(query('''SELECT value,measured_at,quality FROM telemetry
                WHERE id_sensor=%s ORDER BY measured_at DESC LIMIT 24''',(row['id_sensor'],))))
            values=[float(r['value']) for r in row['series'] if r['quality']=='valid']
            lo=min([0]+values);hi=max([float(row['critical_high'])*1.15]+values)
            row['plot_segments']=[]; segment=[]
            for i,r in enumerate(row['series']):
                if r['quality']!='valid':
                    if segment: row['plot_segments'].append(' '.join(segment));segment=[]
                    continue
                x=40+i*560/max(1,len(row['series'])-1);y=170-(float(r['value'])-lo)/(hi-lo)*140
                segment.append(f'{x:.1f},{y:.1f}')
            if segment: row['plot_segments'].append(' '.join(segment))
            row['warning_y']=170-(float(row['warning_high'])-lo)/(hi-lo)*140
            row['critical_y']=170-(float(row['critical_high'])-lo)/(hi-lo)*140
        return render_template('diagnostics.html',title='Телеметрия и диагностика',active='diagnostics',
            machines=machines,item=item,nodes=nodes,node_id=node_id,data=data,condition=aggregate([r['condition'] for r in data]))

    @app.route('/orders/new',methods=['GET','POST'])
    def order_new():
        node_id=request.values.get('node',type=int)
        nodes=query('''SELECT n.*,e.equipment_code FROM equipment_nodes n JOIN equipment e ON e.id_equipment=n.id_equipment
            ORDER BY e.equipment_code,n.id_node''')
        authors=query('SELECT * FROM specialists WHERE is_active=1 ORDER BY full_name')
        error=None
        if request.method=='POST':
            try:
                planned=request.form.get('planned_at','')
                planned=datetime.strptime(planned,'%Y-%m-%dT%H:%M') if planned else None
                order_id=create_order(node_id,request.form.get('author',type=int),
                    request.form.get('title','').strip(),request.form.get('description','').strip(),
                    request.form.get('priority',''),planned)
                flash('Заявка сохранена в базе данных. История создания записана.')
                return redirect(url_for('order_card',order_id=order_id),code=303)
            except ValueError as exc:
                error=str(exc)
        return render_template('new_order.html',title='Новая ремонтная заявка',active='orders',
                               nodes=nodes,authors=authors,node_id=node_id,error=error),422 if error else 200

    @app.get('/orders')
    def order_list():
        status=request.args.get('status','');search=request.args.get('q','').strip()[:100]
        if status and status not in ORDER_STATES: abort(400,description='Неизвестное состояние заявки.')
        return render_template('orders.html',title='Ремонтные заявки',active='orders',rows=orders(status,search),status=status,search=search)

    @app.get('/orders/<int:order_id>')
    def order_card(order_id):
        row=one('''SELECT o.*,e.equipment_code,n.node_name,s.full_name AS author,a.full_name AS assignee,
            d.conclusion FROM repair_orders o JOIN equipment_nodes n ON n.id_node=o.id_node
            JOIN equipment e ON e.id_equipment=n.id_equipment JOIN specialists s ON s.id_specialist=o.created_by
            LEFT JOIN specialists a ON a.id_specialist=o.assigned_to
            LEFT JOIN diagnostics d ON d.id_diagnostic=o.id_diagnostic WHERE o.id_order=%s''',(order_id,))
        if not row: abort(404,description='Заявка не найдена.')
        history=query('SELECT * FROM order_status_history WHERE id_order=%s ORDER BY id_history',(order_id,))
        return render_template('order.html',title=row['order_number'],active='orders',row=row,history=history)

    return app
