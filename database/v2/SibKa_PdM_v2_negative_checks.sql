-- Выполнить весь файл после успешного импорта sibka_pdm_v2.
-- Изменения в InnoDB откатываются; временные результаты MEMORY сохраняются до конца подключения.
USE sibka_pdm_v2;
CREATE TEMPORARY TABLE validation_results (test_name VARCHAR(120), result VARCHAR(10), error_code INT) ENGINE=MEMORY;
DELIMITER $$
CREATE PROCEDURE run_integrity_checks_v2()
BEGIN
 DECLARE caught INT DEFAULT 0;
 START TRANSACTION;
 BEGIN
  DECLARE CONTINUE HANDLER FOR SQLEXCEPTION GET DIAGNOSTICS CONDITION 1 caught=MYSQL_ERRNO;
  UPDATE parts_used SET quantity=-1 WHERE id_order=3 AND id_part=3;
 END;
 INSERT INTO validation_results VALUES('Отрицательный расход',IF(caught=4025,'PASS','FAIL'),caught);
 SET caught=0;
 BEGIN
  DECLARE CONTINUE HANDLER FOR SQLEXCEPTION GET DIAGNOSTICS CONDITION 1 caught=MYSQL_ERRNO;
  INSERT INTO telemetry(id_sensor,measured_at,value) SELECT id_sensor,measured_at,value FROM telemetry WHERE id_reading=1;
 END;
 INSERT INTO validation_results VALUES('Дублирование показания',IF(caught=1062,'PASS','FAIL'),caught);
 SET caught=0;
 BEGIN
  DECLARE CONTINUE HANDLER FOR SQLEXCEPTION GET DIAGNOSTICS CONDITION 1 caught=MYSQL_ERRNO;
  INSERT INTO equipment_nodes(id_equipment,id_group,node_code,node_name) VALUES(4294967295,1,'INVALID','Проверка FK');
 END;
 INSERT INTO validation_results VALUES('Несуществующая техника',IF(caught=1452,'PASS','FAIL'),caught);
 SET caught=0;
 BEGIN
  DECLARE CONTINUE HANDLER FOR SQLEXCEPTION GET DIAGNOSTICS CONDITION 1 caught=MYSQL_ERRNO;
  UPDATE repair_orders SET status='closed',completed_at='2026-10-28 03:00:00',closed_at='2026-10-28 04:00:00',work_result='Проверка' WHERE id_order=1;
 END;
 INSERT INTO validation_results VALUES('Запрещённый переход created → closed',IF(caught=1644,'PASS','FAIL'),caught);
 ROLLBACK;
END$$
DELIMITER ;
CALL run_integrity_checks_v2();
DROP PROCEDURE run_integrity_checks_v2;
SELECT * FROM validation_results;
DROP TEMPORARY TABLE validation_results;
