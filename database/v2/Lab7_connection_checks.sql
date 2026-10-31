-- Лабораторная 7. Проверка подключения и результата работы приложения.
-- Выполнять в phpMyAdmin: SQL. Существующие таблицы и записи не изменяются.
USE sibka_pdm_v2;
SELECT DATABASE() AS current_database, VERSION() AS server_version;
SELECT COUNT(*) AS equipment_count FROM equipment;
SELECT COUNT(*) AS sensor_count FROM sensors;
SELECT COUNT(*) AS reading_count FROM telemetry;

-- Последние заявки, в том числе созданные через веб-приложение.
SELECT o.order_number,e.equipment_code,n.node_name,o.title,o.status,
       s.full_name AS author,o.created_at,o.planned_at
FROM repair_orders o
JOIN equipment_nodes n ON n.id_node=o.id_node
JOIN equipment e ON e.id_equipment=n.id_equipment
JOIN specialists s ON s.id_specialist=o.created_by
ORDER BY o.id_order DESC LIMIT 10;

-- Проверка диагностического основания и истории созданной заявки.
SELECT o.order_number,d.severity,d.conclusion,h.new_status,h.changed_at
FROM repair_orders o
LEFT JOIN diagnostics d ON d.id_diagnostic=o.id_diagnostic
LEFT JOIN order_status_history h ON h.id_order=o.id_order
ORDER BY o.id_order DESC,h.id_history DESC LIMIT 10;
