-- Запросы только читают данные; выполнять в sibka_pdm_v2.
USE sibka_pdm_v2;
-- 13 BASE TABLE и 2 VIEW.
SELECT TABLE_TYPE, COUNT(*) AS object_count FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE() GROUP BY TABLE_TYPE;
-- Все внешние ключи и поля (13 связей).
SELECT TABLE_NAME, COLUMN_NAME, REFERENCED_TABLE_NAME, REFERENCED_COLUMN_NAME
FROM information_schema.KEY_COLUMN_USAGE
WHERE TABLE_SCHEMA=DATABASE() AND REFERENCED_TABLE_NAME IS NOT NULL
ORDER BY TABLE_NAME,COLUMN_NAME;
-- Телеметрия и результаты диагностики.
SELECT e.equipment_code,n.node_name,s.parameter,t.measured_at,t.value,s.unit,d.severity
FROM equipment e JOIN equipment_nodes n ON n.id_equipment=e.id_equipment
JOIN sensors s ON s.id_node=n.id_node JOIN telemetry t ON t.id_sensor=s.id_sensor
LEFT JOIN diagnostics d ON d.id_reading=t.id_reading ORDER BY e.equipment_code,t.measured_at,s.parameter;
-- История переходов статусов.
SELECT r.order_number,h.old_status,h.new_status,h.changed_at
FROM order_status_history h JOIN repair_orders r ON r.id_order=h.id_order ORDER BY h.id_history;
-- Стоимость именно запчастей, без трудозатрат.
SELECT * FROM repair_order_costs;
-- Текущее состояние; unknown ожидается при показаниях старше 15 минут.
SELECT * FROM equipment_health;
-- Установленные триггеры.
SHOW TRIGGERS;

-- Все статусы: ожидаются по две заявки каждого статуса.
SELECT status,COUNT(*) AS orders_count FROM repair_orders GROUP BY status;
-- Снимки пороговой диагностики на фиксированном наборе.
SELECT severity,COUNT(*) AS measurements FROM diagnostics GROUP BY severity;
-- Стоимость запчастей по заявкам, без стоимости труда.
SELECT * FROM repair_order_costs;
