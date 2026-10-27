-- Система предиктивного технического обслуживания карьерной техники
-- Версия 2. Новая схема для MariaDB 10.4.28 / phpMyAdmin 5.2.1.
-- Начальные записи сформированы программно для проверки работы БД.
-- Прогнозы в failure_predictions являются контрольными данными, не результатом ML.
-- Старая база не изменяется. При существующей sibka_pdm_v2 импорт нужно остановить.
-- Повторный импорт не предназначен для обновления существующей базы.
SET NAMES utf8mb4;
SET time_zone = '+00:00';
CREATE DATABASE `sibka_pdm_v2` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE `sibka_pdm_v2`;

CREATE TABLE equipment (
 id_equipment INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 equipment_code VARCHAR(30) NOT NULL UNIQUE,
 model VARCHAR(100) NOT NULL,
 manufacturer VARCHAR(80) NOT NULL,
 serial_number VARCHAR(80) UNIQUE,
 commissioning_date DATE,
 operating_hours DECIMAL(12,1) NOT NULL DEFAULT 0 CHECK (operating_hours >= 0),
 status ENUM('operating','maintenance','repair','retired') NOT NULL DEFAULT 'operating',
 external_1c_id VARCHAR(64) UNIQUE COMMENT 'Идентификатор обмена с 1С, заполняется при интеграции',
 created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;
CREATE TABLE node_groups (
 id_group INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 group_name VARCHAR(100) NOT NULL UNIQUE,
 description TEXT
) ENGINE=InnoDB;
CREATE TABLE equipment_nodes (
 id_node INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 id_equipment INT UNSIGNED NOT NULL,
 id_group INT UNSIGNED NOT NULL,
 node_code VARCHAR(40) NOT NULL,
 node_name VARCHAR(120) NOT NULL,
 UNIQUE (id_equipment,node_code),
 FOREIGN KEY (id_equipment) REFERENCES equipment(id_equipment) ON DELETE RESTRICT,
 FOREIGN KEY (id_group) REFERENCES node_groups(id_group) ON DELETE RESTRICT
) ENGINE=InnoDB;
CREATE TABLE specialists (
 id_specialist INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 full_name VARCHAR(150) NOT NULL,
 role ENUM('dispatcher','engineer','mechanic','administrator') NOT NULL,
 email VARCHAR(150) UNIQUE,
 is_active BOOLEAN NOT NULL DEFAULT TRUE
) ENGINE=InnoDB;
CREATE TABLE sensors (
 id_sensor INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 id_node INT UNSIGNED NOT NULL,
 sensor_code VARCHAR(50) NOT NULL UNIQUE,
 parameter ENUM('temperature','vibration','pressure') NOT NULL,
 unit VARCHAR(20) NOT NULL,
 warning_high DECIMAL(12,3) NOT NULL,
 critical_high DECIMAL(12,3) NOT NULL,
 is_active BOOLEAN NOT NULL DEFAULT TRUE,
 CHECK (warning_high < critical_high),
 CHECK ((parameter='temperature' AND unit='degC') OR
        (parameter='vibration' AND unit='mm/s') OR
        (parameter='pressure' AND unit='bar')),
 FOREIGN KEY (id_node) REFERENCES equipment_nodes(id_node) ON DELETE RESTRICT
) ENGINE=InnoDB;
CREATE TABLE telemetry (
 id_reading BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 id_sensor INT UNSIGNED NOT NULL,
 measured_at DATETIME(3) NOT NULL COMMENT 'UTC',
 value DECIMAL(12,3) NOT NULL,
 quality ENUM('valid','suspect','invalid') NOT NULL DEFAULT 'valid',
 source ENUM('generated','sensor','manual') NOT NULL DEFAULT 'generated',
 received_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
 UNIQUE (id_sensor,measured_at),
 FOREIGN KEY (id_sensor) REFERENCES sensors(id_sensor) ON DELETE RESTRICT
) ENGINE=InnoDB;
CREATE TABLE diagnostics (
 id_diagnostic BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 id_reading BIGINT UNSIGNED NOT NULL UNIQUE,
 severity ENUM('normal','warning','critical','unknown') NOT NULL,
 method VARCHAR(80) NOT NULL DEFAULT 'threshold_v1',
 warning_high_used DECIMAL(12,3) NOT NULL,
 critical_high_used DECIMAL(12,3) NOT NULL,
 conclusion TEXT NOT NULL,
 diagnosed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CHECK (warning_high_used < critical_high_used),
 FOREIGN KEY (id_reading) REFERENCES telemetry(id_reading) ON DELETE RESTRICT
) ENGINE=InnoDB;
CREATE TABLE failure_predictions (
 id_prediction BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 id_node INT UNSIGNED NOT NULL,
 calculated_at DATETIME NOT NULL,
 horizon_hours INT UNSIGNED NOT NULL CHECK (horizon_hours > 0),
 failure_probability DECIMAL(5,4) NOT NULL CHECK (failure_probability BETWEEN 0 AND 1),
 remaining_hours DECIMAL(12,1) CHECK (remaining_hours >= 0),
 model_version VARCHAR(80) NOT NULL,
 source ENUM('generated','model','expert') NOT NULL DEFAULT 'generated',
 explanation TEXT,
 FOREIGN KEY (id_node) REFERENCES equipment_nodes(id_node) ON DELETE RESTRICT,
 INDEX ix_prediction_node_time (id_node,calculated_at)
) ENGINE=InnoDB;
CREATE TABLE repair_orders (
 id_order INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 order_number VARCHAR(40) NOT NULL UNIQUE,
 id_node INT UNSIGNED NOT NULL,
 id_diagnostic BIGINT UNSIGNED,
 created_by INT UNSIGNED NOT NULL,
 assigned_to INT UNSIGNED,
 title VARCHAR(200) NOT NULL,
 description TEXT NOT NULL,
 priority ENUM('low','medium','high','critical') NOT NULL DEFAULT 'medium',
 status ENUM('created','approved','in_progress','completed','closed','rejected') NOT NULL DEFAULT 'created',
 created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
 planned_at DATETIME,
 completed_at DATETIME,
 closed_at DATETIME,
 work_result TEXT,
 external_1c_id VARCHAR(64) UNIQUE,
 CHECK (completed_at IS NULL OR completed_at >= created_at),
 CHECK (closed_at IS NULL OR (completed_at IS NOT NULL AND closed_at >= completed_at)),
 CHECK (status NOT IN ('completed','closed') OR
       (completed_at IS NOT NULL AND work_result IS NOT NULL AND CHAR_LENGTH(TRIM(work_result)) > 0)),
 CHECK (status <> 'closed' OR closed_at IS NOT NULL),
 FOREIGN KEY (id_node) REFERENCES equipment_nodes(id_node) ON DELETE RESTRICT,
 FOREIGN KEY (id_diagnostic) REFERENCES diagnostics(id_diagnostic) ON DELETE RESTRICT,
 FOREIGN KEY (created_by) REFERENCES specialists(id_specialist) ON DELETE RESTRICT,
 FOREIGN KEY (assigned_to) REFERENCES specialists(id_specialist) ON DELETE RESTRICT,
 INDEX ix_orders_status (status,priority)
) ENGINE=InnoDB;
CREATE TABLE spare_parts (
 id_part INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 part_code VARCHAR(60) NOT NULL UNIQUE,
 part_name VARCHAR(150) NOT NULL,
 unit VARCHAR(20) NOT NULL DEFAULT 'шт.',
 unit_price DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (unit_price >= 0)
) ENGINE=InnoDB;
CREATE TABLE parts_used (
 id_order INT UNSIGNED NOT NULL,
 id_part INT UNSIGNED NOT NULL,
 quantity DECIMAL(10,3) NOT NULL CHECK (quantity > 0),
 unit_price DECIMAL(12,2) NOT NULL CHECK (unit_price >= 0),
 PRIMARY KEY (id_order,id_part),
 FOREIGN KEY (id_order) REFERENCES repair_orders(id_order) ON DELETE RESTRICT,
 FOREIGN KEY (id_part) REFERENCES spare_parts(id_part) ON DELETE RESTRICT
) ENGINE=InnoDB;
CREATE TABLE order_status_history (
 id_history BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 id_order INT UNSIGNED NOT NULL,
 old_status VARCHAR(30),
 new_status VARCHAR(30) NOT NULL,
 changed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
 db_user VARCHAR(150) NOT NULL,
 FOREIGN KEY (id_order) REFERENCES repair_orders(id_order) ON DELETE RESTRICT
) ENGINE=InnoDB;
CREATE TABLE mylog (
 id_log BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 changed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
 db_user VARCHAR(150) NOT NULL,
 action ENUM('INSERT','UPDATE','DELETE') NOT NULL,
 table_name VARCHAR(64) NOT NULL,
 record_id BIGINT UNSIGNED NOT NULL,
 old_data TEXT,
 new_data TEXT
) ENGINE=InnoDB;

DELIMITER $$
CREATE TRIGGER equipment_after_insert AFTER INSERT ON equipment FOR EACH ROW
BEGIN
 INSERT INTO mylog(db_user,action,table_name,record_id,new_data)
 VALUES(USER(),'INSERT','equipment',NEW.id_equipment,CONCAT(NEW.equipment_code,': ',NEW.model,', ',NEW.status));
END$$
CREATE TRIGGER equipment_after_update AFTER UPDATE ON equipment FOR EACH ROW
BEGIN
 INSERT INTO mylog(db_user,action,table_name,record_id,old_data,new_data)
 VALUES(USER(),'UPDATE','equipment',NEW.id_equipment,CONCAT(OLD.model,', ',OLD.status),CONCAT(NEW.model,', ',NEW.status));
END$$
CREATE TRIGGER equipment_after_delete AFTER DELETE ON equipment FOR EACH ROW
BEGIN
 INSERT INTO mylog(db_user,action,table_name,record_id,old_data)
 VALUES(USER(),'DELETE','equipment',OLD.id_equipment,CONCAT(OLD.equipment_code,': ',OLD.model));
END$$
CREATE TRIGGER telemetry_before_insert BEFORE INSERT ON telemetry FOR EACH ROW
BEGIN
 DECLARE p VARCHAR(30);
 SELECT parameter INTO p FROM sensors WHERE id_sensor=NEW.id_sensor;
 IF p IN ('vibration','pressure') AND NEW.value < 0 THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Вибрация и давление не могут быть отрицательными';
 END IF;
END$$
CREATE TRIGGER telemetry_before_update BEFORE UPDATE ON telemetry FOR EACH ROW
BEGIN
 DECLARE p VARCHAR(30);
 SELECT parameter INTO p FROM sensors WHERE id_sensor=NEW.id_sensor;
 IF p IN ('vibration','pressure') AND NEW.value < 0 THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Вибрация и давление не могут быть отрицательными';
 END IF;
END$$
CREATE TRIGGER orders_before_insert BEFORE INSERT ON repair_orders FOR EACH ROW
BEGIN
 IF NEW.status <> 'created' THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Новая заявка должна иметь статус created';
 END IF;
 IF NEW.id_diagnostic IS NOT NULL AND NOT EXISTS (
 SELECT 1 FROM diagnostics d JOIN telemetry t ON t.id_reading=d.id_reading
 JOIN sensors s ON s.id_sensor=t.id_sensor
 WHERE d.id_diagnostic=NEW.id_diagnostic AND s.id_node=NEW.id_node) THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Диагностика должна относиться к узлу заявки';
 END IF;
END$$
CREATE TRIGGER orders_before_update BEFORE UPDATE ON repair_orders FOR EACH ROW
BEGIN
 IF OLD.status <> NEW.status AND NOT (
 (OLD.status='created' AND NEW.status IN ('approved','rejected')) OR
 (OLD.status='approved' AND NEW.status IN ('in_progress','rejected')) OR
 (OLD.status='in_progress' AND NEW.status='completed') OR
 (OLD.status='completed' AND NEW.status IN ('closed','in_progress'))
 ) THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Недопустимый переход статуса заявки';
 END IF;
 IF NEW.id_diagnostic IS NOT NULL AND NOT EXISTS (
 SELECT 1 FROM diagnostics d JOIN telemetry t ON t.id_reading=d.id_reading
 JOIN sensors s ON s.id_sensor=t.id_sensor
 WHERE d.id_diagnostic=NEW.id_diagnostic AND s.id_node=NEW.id_node) THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Диагностика должна относиться к узлу заявки';
 END IF;
END$$
CREATE TRIGGER orders_after_insert AFTER INSERT ON repair_orders FOR EACH ROW
BEGIN
 INSERT INTO order_status_history(id_order,old_status,new_status,db_user)
 VALUES(NEW.id_order,NULL,NEW.status,USER());
END$$
CREATE TRIGGER orders_after_update AFTER UPDATE ON repair_orders FOR EACH ROW
BEGIN
 IF OLD.status <> NEW.status THEN
 INSERT INTO order_status_history(id_order,old_status,new_status,db_user)
 VALUES(NEW.id_order,OLD.status,NEW.status,USER());
 END IF;
END$$
DELIMITER ;


START TRANSACTION;
INSERT INTO equipment (id_equipment,equipment_code,model,manufacturer,serial_number,commissioning_date,operating_hours,status) VALUES
(1,'SK-001','HD785-7','Komatsu','GEN-00001','2021-01-15',12350,'operating'),
(2,'SK-002','HD785-7','Komatsu','GEN-00002','2021-01-15',12700,'operating'),
(3,'SK-003','HD785-7','Komatsu','GEN-00003','2021-01-15',13050,'operating'),
(4,'SK-004','HD785-7','Komatsu','GEN-00004','2021-01-15',13400,'operating'),
(5,'SK-005','HD785-7','Komatsu','GEN-00005','2021-01-15',13750,'operating'),
(6,'SK-006','HD785-7','Komatsu','GEN-00006','2021-01-15',14100,'operating'),
(7,'SK-007','HD785-7','Komatsu','GEN-00007','2021-01-15',14450,'operating'),
(8,'SK-008','HD785-7','Komatsu','GEN-00008','2021-01-15',14800,'operating'),
(9,'SK-009','PC1250','Komatsu','GEN-00009','2021-01-15',15150,'operating'),
(10,'SK-010','PC1250','Komatsu','GEN-00010','2021-01-15',15500,'operating'),
(11,'SK-011','PC1250','Komatsu','GEN-00011','2021-01-15',15850,'operating'),
(12,'SK-012','PC1250','Komatsu','GEN-00012','2021-01-15',16200,'operating');
INSERT INTO node_groups (id_group,group_name,description) VALUES
(1,'Двигатель','Контроль двигателя'),
(2,'Гидравлика','Контроль давления'),
(3,'Трансмиссия','Передача мощности'),
(4,'Тормозная система','Торможение'),
(5,'Рулевое управление','Управляемость'),
(6,'Электрооборудование','Электропитание'),
(7,'Ходовая часть','Передвижение'),
(8,'Система охлаждения','Охлаждение агрегатов'),
(9,'Топливная система','Подача топлива'),
(10,'Смазочная система','Смазка узлов');
INSERT INTO equipment_nodes (id_node,id_equipment,id_group,node_code,node_name) VALUES
(1,1,1,'ENG','Двигатель'),
(3,2,1,'ENG','Двигатель'),
(5,3,1,'ENG','Двигатель'),
(7,4,1,'ENG','Двигатель'),
(9,5,1,'ENG','Двигатель'),
(11,6,1,'ENG','Двигатель'),
(13,7,1,'ENG','Двигатель'),
(15,8,1,'ENG','Двигатель'),
(17,9,1,'ENG','Двигатель'),
(19,10,1,'ENG','Двигатель'),
(21,11,1,'ENG','Двигатель'),
(23,12,1,'ENG','Двигатель'),
(2,1,2,'HYD','Гидросистема'),
(4,2,2,'HYD','Гидросистема'),
(6,3,2,'HYD','Гидросистема'),
(8,4,2,'HYD','Гидросистема'),
(10,5,2,'HYD','Гидросистема'),
(12,6,2,'HYD','Гидросистема'),
(14,7,2,'HYD','Гидросистема'),
(16,8,2,'HYD','Гидросистема'),
(18,9,2,'HYD','Гидросистема'),
(20,10,2,'HYD','Гидросистема'),
(22,11,2,'HYD','Гидросистема'),
(24,12,2,'HYD','Гидросистема');
INSERT INTO specialists (id_specialist,full_name,role,email) VALUES
(1,'Диспетчер 1','dispatcher','staff01@example.org'),
(2,'Инженер 1','engineer','staff02@example.org'),
(3,'Механик 1','mechanic','staff03@example.org'),
(4,'Администратор 1','administrator','staff04@example.org'),
(5,'Диспетчер 2','dispatcher','staff05@example.org'),
(6,'Инженер 2','engineer','staff06@example.org'),
(7,'Механик 2','mechanic','staff07@example.org'),
(8,'Администратор 2','administrator','staff08@example.org'),
(9,'Диспетчер 3','dispatcher','staff09@example.org'),
(10,'Инженер 3','engineer','staff10@example.org'),
(11,'Механик 3','mechanic','staff11@example.org'),
(12,'Администратор 3','administrator','staff12@example.org');
INSERT INTO sensors (id_sensor,id_node,sensor_code,parameter,unit,warning_high,critical_high) VALUES
(1,1,'SK001-temperature','temperature','degC',90,105),
(2,1,'SK001-vibration','vibration','mm/s',4.5,7.1),
(3,2,'SK001-pressure','pressure','bar',16,20),
(4,3,'SK002-temperature','temperature','degC',90,105),
(5,3,'SK002-vibration','vibration','mm/s',4.5,7.1),
(6,4,'SK002-pressure','pressure','bar',16,20),
(7,5,'SK003-temperature','temperature','degC',90,105),
(8,5,'SK003-vibration','vibration','mm/s',4.5,7.1),
(9,6,'SK003-pressure','pressure','bar',16,20),
(10,7,'SK004-temperature','temperature','degC',90,105),
(11,7,'SK004-vibration','vibration','mm/s',4.5,7.1),
(12,8,'SK004-pressure','pressure','bar',16,20),
(13,9,'SK005-temperature','temperature','degC',90,105),
(14,9,'SK005-vibration','vibration','mm/s',4.5,7.1),
(15,10,'SK005-pressure','pressure','bar',16,20),
(16,11,'SK006-temperature','temperature','degC',90,105),
(17,11,'SK006-vibration','vibration','mm/s',4.5,7.1),
(18,12,'SK006-pressure','pressure','bar',16,20),
(19,13,'SK007-temperature','temperature','degC',90,105),
(20,13,'SK007-vibration','vibration','mm/s',4.5,7.1),
(21,14,'SK007-pressure','pressure','bar',16,20),
(22,15,'SK008-temperature','temperature','degC',90,105),
(23,15,'SK008-vibration','vibration','mm/s',4.5,7.1),
(24,16,'SK008-pressure','pressure','bar',16,20),
(25,17,'SK009-temperature','temperature','degC',90,105),
(26,17,'SK009-vibration','vibration','mm/s',4.5,7.1),
(27,18,'SK009-pressure','pressure','bar',16,20),
(28,19,'SK010-temperature','temperature','degC',90,105),
(29,19,'SK010-vibration','vibration','mm/s',4.5,7.1),
(30,20,'SK010-pressure','pressure','bar',16,20),
(31,21,'SK011-temperature','temperature','degC',90,105),
(32,21,'SK011-vibration','vibration','mm/s',4.5,7.1),
(33,22,'SK011-pressure','pressure','bar',16,20),
(34,23,'SK012-temperature','temperature','degC',90,105),
(35,23,'SK012-vibration','vibration','mm/s',4.5,7.1),
(36,24,'SK012-pressure','pressure','bar',16,20);
INSERT INTO telemetry (id_reading,id_sensor,measured_at,value,quality,source) VALUES
(1,1,'2026-10-28 00:00:00',78.3,'valid','generated'),
(2,1,'2026-10-28 00:05:00',78.5,'valid','generated'),
(3,1,'2026-10-28 00:10:00',78.7,'valid','generated'),
(4,1,'2026-10-28 00:15:00',78.9,'valid','generated'),
(5,1,'2026-10-28 00:20:00',79.1,'valid','generated'),
(6,1,'2026-10-28 00:25:00',79.3,'valid','generated'),
(7,1,'2026-10-28 00:30:00',79.5,'valid','generated'),
(8,1,'2026-10-28 00:35:00',79.7,'valid','generated'),
(9,1,'2026-10-28 00:40:00',79.9,'valid','generated'),
(10,1,'2026-10-28 00:45:00',80.1,'valid','generated'),
(11,1,'2026-10-28 00:50:00',96,'valid','generated'),
(12,1,'2026-10-28 00:55:00',96,'valid','generated'),
(13,2,'2026-10-28 00:00:00',1.1,'valid','generated'),
(14,2,'2026-10-28 00:05:00',1.15,'valid','generated'),
(15,2,'2026-10-28 00:10:00',1.2,'valid','generated'),
(16,2,'2026-10-28 00:15:00',1.25,'valid','generated'),
(17,2,'2026-10-28 00:20:00',1.3,'valid','generated'),
(18,2,'2026-10-28 00:25:00',1.35,'valid','generated'),
(19,2,'2026-10-28 00:30:00',1.4,'valid','generated'),
(20,2,'2026-10-28 00:35:00',1.45,'valid','generated'),
(21,2,'2026-10-28 00:40:00',1.5,'valid','generated'),
(22,2,'2026-10-28 00:45:00',1.55,'valid','generated'),
(23,2,'2026-10-28 00:50:00',5.2,'valid','generated'),
(24,2,'2026-10-28 00:55:00',5.2,'valid','generated'),
(25,3,'2026-10-28 00:00:00',10.1,'valid','generated'),
(26,3,'2026-10-28 00:05:00',10.2,'valid','generated'),
(27,3,'2026-10-28 00:10:00',10.3,'valid','generated'),
(28,3,'2026-10-28 00:15:00',10.4,'valid','generated'),
(29,3,'2026-10-28 00:20:00',10.5,'valid','generated'),
(30,3,'2026-10-28 00:25:00',10.6,'valid','generated'),
(31,3,'2026-10-28 00:30:00',10.7,'valid','generated'),
(32,3,'2026-10-28 00:35:00',10.8,'valid','generated'),
(33,3,'2026-10-28 00:40:00',10.9,'valid','generated'),
(34,3,'2026-10-28 00:45:00',11.0,'valid','generated'),
(35,3,'2026-10-28 00:50:00',17,'valid','generated'),
(36,3,'2026-10-28 00:55:00',17,'valid','generated'),
(37,4,'2026-10-28 00:00:00',78.6,'valid','generated'),
(38,4,'2026-10-28 00:05:00',78.8,'valid','generated'),
(39,4,'2026-10-28 00:10:00',79.0,'valid','generated'),
(40,4,'2026-10-28 00:15:00',79.2,'valid','generated'),
(41,4,'2026-10-28 00:20:00',79.4,'valid','generated'),
(42,4,'2026-10-28 00:25:00',79.6,'valid','generated'),
(43,4,'2026-10-28 00:30:00',79.8,'valid','generated'),
(44,4,'2026-10-28 00:35:00',80.0,'valid','generated'),
(45,4,'2026-10-28 00:40:00',80.2,'valid','generated'),
(46,4,'2026-10-28 00:45:00',80.4,'valid','generated'),
(47,4,'2026-10-28 00:50:00',108,'valid','generated'),
(48,4,'2026-10-28 00:55:00',108,'valid','generated'),
(49,5,'2026-10-28 00:00:00',1.2,'valid','generated'),
(50,5,'2026-10-28 00:05:00',1.25,'valid','generated'),
(51,5,'2026-10-28 00:10:00',1.3,'valid','generated'),
(52,5,'2026-10-28 00:15:00',1.35,'valid','generated'),
(53,5,'2026-10-28 00:20:00',1.4,'valid','generated'),
(54,5,'2026-10-28 00:25:00',1.45,'valid','generated'),
(55,5,'2026-10-28 00:30:00',1.5,'valid','generated'),
(56,5,'2026-10-28 00:35:00',1.55,'valid','generated'),
(57,5,'2026-10-28 00:40:00',1.6,'valid','generated'),
(58,5,'2026-10-28 00:45:00',1.65,'valid','generated'),
(59,5,'2026-10-28 00:50:00',7.5,'valid','generated'),
(60,5,'2026-10-28 00:55:00',7.5,'valid','generated'),
(61,6,'2026-10-28 00:00:00',10.2,'valid','generated'),
(62,6,'2026-10-28 00:05:00',10.3,'valid','generated'),
(63,6,'2026-10-28 00:10:00',10.4,'valid','generated'),
(64,6,'2026-10-28 00:15:00',10.5,'valid','generated'),
(65,6,'2026-10-28 00:20:00',10.6,'valid','generated'),
(66,6,'2026-10-28 00:25:00',10.7,'valid','generated'),
(67,6,'2026-10-28 00:30:00',10.8,'valid','generated'),
(68,6,'2026-10-28 00:35:00',10.9,'valid','generated'),
(69,6,'2026-10-28 00:40:00',11.0,'valid','generated'),
(70,6,'2026-10-28 00:45:00',11.1,'valid','generated'),
(71,6,'2026-10-28 00:50:00',21,'valid','generated'),
(72,6,'2026-10-28 00:55:00',21,'valid','generated'),
(73,7,'2026-10-28 00:00:00',78.9,'valid','generated'),
(74,7,'2026-10-28 00:05:00',79.1,'valid','generated'),
(75,7,'2026-10-28 00:10:00',79.3,'valid','generated'),
(76,7,'2026-10-28 00:15:00',79.5,'valid','generated'),
(77,7,'2026-10-28 00:20:00',79.7,'valid','generated'),
(78,7,'2026-10-28 00:25:00',79.9,'valid','generated'),
(79,7,'2026-10-28 00:30:00',80.1,'valid','generated'),
(80,7,'2026-10-28 00:35:00',80.3,'valid','generated'),
(81,7,'2026-10-28 00:40:00',80.5,'valid','generated'),
(82,7,'2026-10-28 00:45:00',80.7,'valid','generated'),
(83,7,'2026-10-28 00:50:00',80.9,'valid','generated'),
(84,7,'2026-10-28 00:55:00',81.1,'valid','generated'),
(85,8,'2026-10-28 00:00:00',1.3,'valid','generated'),
(86,8,'2026-10-28 00:05:00',1.35,'valid','generated'),
(87,8,'2026-10-28 00:10:00',1.4,'valid','generated'),
(88,8,'2026-10-28 00:15:00',1.45,'valid','generated'),
(89,8,'2026-10-28 00:20:00',1.5,'valid','generated'),
(90,8,'2026-10-28 00:25:00',1.55,'valid','generated'),
(91,8,'2026-10-28 00:30:00',1.6,'valid','generated'),
(92,8,'2026-10-28 00:35:00',1.65,'valid','generated'),
(93,8,'2026-10-28 00:40:00',1.7,'valid','generated'),
(94,8,'2026-10-28 00:45:00',1.75,'valid','generated'),
(95,8,'2026-10-28 00:50:00',1.8,'valid','generated'),
(96,8,'2026-10-28 00:55:00',1.85,'valid','generated'),
(97,9,'2026-10-28 00:00:00',10.3,'valid','generated'),
(98,9,'2026-10-28 00:05:00',10.4,'valid','generated'),
(99,9,'2026-10-28 00:10:00',10.5,'valid','generated'),
(100,9,'2026-10-28 00:15:00',10.6,'valid','generated'),
(101,9,'2026-10-28 00:20:00',10.7,'valid','generated'),
(102,9,'2026-10-28 00:25:00',10.8,'valid','generated'),
(103,9,'2026-10-28 00:30:00',10.9,'valid','generated'),
(104,9,'2026-10-28 00:35:00',11.0,'valid','generated'),
(105,9,'2026-10-28 00:40:00',11.1,'valid','generated'),
(106,9,'2026-10-28 00:45:00',11.2,'valid','generated'),
(107,9,'2026-10-28 00:50:00',11.3,'valid','generated'),
(108,9,'2026-10-28 00:55:00',11.4,'valid','generated'),
(109,10,'2026-10-28 00:00:00',79.2,'valid','generated'),
(110,10,'2026-10-28 00:05:00',79.4,'valid','generated'),
(111,10,'2026-10-28 00:10:00',79.6,'valid','generated'),
(112,10,'2026-10-28 00:15:00',79.8,'valid','generated'),
(113,10,'2026-10-28 00:20:00',80.0,'valid','generated'),
(114,10,'2026-10-28 00:25:00',80.2,'valid','generated'),
(115,10,'2026-10-28 00:30:00',80.4,'valid','generated'),
(116,10,'2026-10-28 00:35:00',80.6,'valid','generated'),
(117,10,'2026-10-28 00:40:00',80.8,'valid','generated'),
(118,10,'2026-10-28 00:45:00',81.0,'valid','generated'),
(119,10,'2026-10-28 00:50:00',96,'valid','generated'),
(120,10,'2026-10-28 00:55:00',96,'valid','generated'),
(121,11,'2026-10-28 00:00:00',1.4,'valid','generated'),
(122,11,'2026-10-28 00:05:00',1.45,'valid','generated'),
(123,11,'2026-10-28 00:10:00',1.5,'valid','generated'),
(124,11,'2026-10-28 00:15:00',1.55,'valid','generated'),
(125,11,'2026-10-28 00:20:00',1.6,'valid','generated'),
(126,11,'2026-10-28 00:25:00',1.65,'valid','generated'),
(127,11,'2026-10-28 00:30:00',1.7,'valid','generated'),
(128,11,'2026-10-28 00:35:00',1.75,'valid','generated'),
(129,11,'2026-10-28 00:40:00',1.8,'valid','generated'),
(130,11,'2026-10-28 00:45:00',1.85,'valid','generated'),
(131,11,'2026-10-28 00:50:00',5.2,'valid','generated'),
(132,11,'2026-10-28 00:55:00',5.2,'valid','generated'),
(133,12,'2026-10-28 00:00:00',10.4,'valid','generated'),
(134,12,'2026-10-28 00:05:00',10.5,'valid','generated'),
(135,12,'2026-10-28 00:10:00',10.6,'valid','generated'),
(136,12,'2026-10-28 00:15:00',10.7,'valid','generated'),
(137,12,'2026-10-28 00:20:00',10.8,'valid','generated'),
(138,12,'2026-10-28 00:25:00',10.9,'valid','generated'),
(139,12,'2026-10-28 00:30:00',11.0,'valid','generated'),
(140,12,'2026-10-28 00:35:00',11.1,'valid','generated'),
(141,12,'2026-10-28 00:40:00',11.2,'valid','generated'),
(142,12,'2026-10-28 00:45:00',11.3,'valid','generated'),
(143,12,'2026-10-28 00:50:00',17,'valid','generated'),
(144,12,'2026-10-28 00:55:00',17,'valid','generated'),
(145,13,'2026-10-28 00:00:00',79.5,'valid','generated'),
(146,13,'2026-10-28 00:05:00',79.7,'valid','generated'),
(147,13,'2026-10-28 00:10:00',79.9,'valid','generated'),
(148,13,'2026-10-28 00:15:00',80.1,'valid','generated'),
(149,13,'2026-10-28 00:20:00',80.3,'valid','generated'),
(150,13,'2026-10-28 00:25:00',80.5,'valid','generated'),
(151,13,'2026-10-28 00:30:00',80.7,'valid','generated'),
(152,13,'2026-10-28 00:35:00',80.9,'valid','generated'),
(153,13,'2026-10-28 00:40:00',81.1,'valid','generated'),
(154,13,'2026-10-28 00:45:00',81.3,'valid','generated'),
(155,13,'2026-10-28 00:50:00',108,'valid','generated'),
(156,13,'2026-10-28 00:55:00',108,'valid','generated'),
(157,14,'2026-10-28 00:00:00',1.5,'valid','generated'),
(158,14,'2026-10-28 00:05:00',1.55,'valid','generated'),
(159,14,'2026-10-28 00:10:00',1.6,'valid','generated'),
(160,14,'2026-10-28 00:15:00',1.65,'valid','generated'),
(161,14,'2026-10-28 00:20:00',1.7,'valid','generated'),
(162,14,'2026-10-28 00:25:00',1.75,'valid','generated'),
(163,14,'2026-10-28 00:30:00',1.8,'valid','generated'),
(164,14,'2026-10-28 00:35:00',1.85,'valid','generated'),
(165,14,'2026-10-28 00:40:00',1.9,'valid','generated'),
(166,14,'2026-10-28 00:45:00',1.95,'valid','generated'),
(167,14,'2026-10-28 00:50:00',7.5,'valid','generated'),
(168,14,'2026-10-28 00:55:00',7.5,'valid','generated'),
(169,15,'2026-10-28 00:00:00',10.5,'valid','generated'),
(170,15,'2026-10-28 00:05:00',10.6,'valid','generated'),
(171,15,'2026-10-28 00:10:00',10.7,'valid','generated'),
(172,15,'2026-10-28 00:15:00',10.8,'valid','generated'),
(173,15,'2026-10-28 00:20:00',10.9,'valid','generated'),
(174,15,'2026-10-28 00:25:00',11.0,'valid','generated'),
(175,15,'2026-10-28 00:30:00',11.1,'valid','generated'),
(176,15,'2026-10-28 00:35:00',11.2,'valid','generated'),
(177,15,'2026-10-28 00:40:00',11.3,'valid','generated'),
(178,15,'2026-10-28 00:45:00',11.4,'valid','generated'),
(179,15,'2026-10-28 00:50:00',21,'valid','generated'),
(180,15,'2026-10-28 00:55:00',21,'valid','generated'),
(181,16,'2026-10-28 00:00:00',79.8,'valid','generated'),
(182,16,'2026-10-28 00:05:00',80.0,'valid','generated'),
(183,16,'2026-10-28 00:10:00',80.2,'valid','generated'),
(184,16,'2026-10-28 00:15:00',80.4,'valid','generated'),
(185,16,'2026-10-28 00:20:00',80.6,'valid','generated'),
(186,16,'2026-10-28 00:25:00',80.8,'valid','generated'),
(187,16,'2026-10-28 00:30:00',81.0,'valid','generated'),
(188,16,'2026-10-28 00:35:00',81.2,'valid','generated'),
(189,16,'2026-10-28 00:40:00',81.4,'valid','generated'),
(190,16,'2026-10-28 00:45:00',81.6,'valid','generated'),
(191,16,'2026-10-28 00:50:00',81.8,'valid','generated'),
(192,16,'2026-10-28 00:55:00',82.0,'valid','generated'),
(193,17,'2026-10-28 00:00:00',1.6,'valid','generated'),
(194,17,'2026-10-28 00:05:00',1.65,'valid','generated'),
(195,17,'2026-10-28 00:10:00',1.7,'valid','generated'),
(196,17,'2026-10-28 00:15:00',1.75,'valid','generated'),
(197,17,'2026-10-28 00:20:00',1.8,'valid','generated'),
(198,17,'2026-10-28 00:25:00',1.85,'valid','generated'),
(199,17,'2026-10-28 00:30:00',1.9,'valid','generated'),
(200,17,'2026-10-28 00:35:00',1.95,'valid','generated'),
(201,17,'2026-10-28 00:40:00',2.0,'valid','generated'),
(202,17,'2026-10-28 00:45:00',2.05,'valid','generated'),
(203,17,'2026-10-28 00:50:00',2.1,'valid','generated'),
(204,17,'2026-10-28 00:55:00',2.15,'valid','generated'),
(205,18,'2026-10-28 00:00:00',10.6,'valid','generated'),
(206,18,'2026-10-28 00:05:00',10.7,'valid','generated'),
(207,18,'2026-10-28 00:10:00',10.8,'valid','generated'),
(208,18,'2026-10-28 00:15:00',10.9,'valid','generated'),
(209,18,'2026-10-28 00:20:00',11.0,'valid','generated'),
(210,18,'2026-10-28 00:25:00',11.1,'valid','generated'),
(211,18,'2026-10-28 00:30:00',11.2,'valid','generated'),
(212,18,'2026-10-28 00:35:00',11.3,'valid','generated'),
(213,18,'2026-10-28 00:40:00',11.4,'valid','generated'),
(214,18,'2026-10-28 00:45:00',11.5,'valid','generated'),
(215,18,'2026-10-28 00:50:00',11.6,'valid','generated'),
(216,18,'2026-10-28 00:55:00',11.7,'valid','generated'),
(217,19,'2026-10-28 00:00:00',80.1,'valid','generated'),
(218,19,'2026-10-28 00:05:00',80.3,'valid','generated'),
(219,19,'2026-10-28 00:10:00',80.5,'valid','generated'),
(220,19,'2026-10-28 00:15:00',80.7,'valid','generated'),
(221,19,'2026-10-28 00:20:00',80.9,'valid','generated'),
(222,19,'2026-10-28 00:25:00',81.1,'valid','generated'),
(223,19,'2026-10-28 00:30:00',81.3,'valid','generated'),
(224,19,'2026-10-28 00:35:00',81.5,'valid','generated'),
(225,19,'2026-10-28 00:40:00',81.7,'valid','generated'),
(226,19,'2026-10-28 00:45:00',81.9,'valid','generated'),
(227,19,'2026-10-28 00:50:00',96,'valid','generated'),
(228,19,'2026-10-28 00:55:00',96,'valid','generated'),
(229,20,'2026-10-28 00:00:00',1.7,'valid','generated'),
(230,20,'2026-10-28 00:05:00',1.75,'valid','generated'),
(231,20,'2026-10-28 00:10:00',1.8,'valid','generated'),
(232,20,'2026-10-28 00:15:00',1.85,'valid','generated'),
(233,20,'2026-10-28 00:20:00',1.9,'valid','generated'),
(234,20,'2026-10-28 00:25:00',1.95,'valid','generated'),
(235,20,'2026-10-28 00:30:00',2.0,'valid','generated'),
(236,20,'2026-10-28 00:35:00',2.05,'valid','generated'),
(237,20,'2026-10-28 00:40:00',2.1,'valid','generated'),
(238,20,'2026-10-28 00:45:00',2.15,'valid','generated'),
(239,20,'2026-10-28 00:50:00',5.2,'valid','generated'),
(240,20,'2026-10-28 00:55:00',5.2,'valid','generated'),
(241,21,'2026-10-28 00:00:00',10.7,'valid','generated'),
(242,21,'2026-10-28 00:05:00',10.8,'valid','generated'),
(243,21,'2026-10-28 00:10:00',10.9,'valid','generated'),
(244,21,'2026-10-28 00:15:00',11.0,'valid','generated'),
(245,21,'2026-10-28 00:20:00',11.1,'valid','generated'),
(246,21,'2026-10-28 00:25:00',11.2,'valid','generated'),
(247,21,'2026-10-28 00:30:00',11.3,'valid','generated'),
(248,21,'2026-10-28 00:35:00',11.4,'valid','generated'),
(249,21,'2026-10-28 00:40:00',11.5,'valid','generated'),
(250,21,'2026-10-28 00:45:00',11.6,'valid','generated'),
(251,21,'2026-10-28 00:50:00',17,'valid','generated'),
(252,21,'2026-10-28 00:55:00',17,'valid','generated'),
(253,22,'2026-10-28 00:00:00',80.4,'valid','generated'),
(254,22,'2026-10-28 00:05:00',80.6,'valid','generated'),
(255,22,'2026-10-28 00:10:00',80.8,'valid','generated'),
(256,22,'2026-10-28 00:15:00',81.0,'valid','generated'),
(257,22,'2026-10-28 00:20:00',81.2,'valid','generated'),
(258,22,'2026-10-28 00:25:00',81.4,'valid','generated'),
(259,22,'2026-10-28 00:30:00',81.6,'valid','generated'),
(260,22,'2026-10-28 00:35:00',81.8,'valid','generated'),
(261,22,'2026-10-28 00:40:00',82.0,'valid','generated'),
(262,22,'2026-10-28 00:45:00',82.2,'valid','generated'),
(263,22,'2026-10-28 00:50:00',108,'valid','generated'),
(264,22,'2026-10-28 00:55:00',108,'valid','generated'),
(265,23,'2026-10-28 00:00:00',1.8,'valid','generated'),
(266,23,'2026-10-28 00:05:00',1.85,'valid','generated'),
(267,23,'2026-10-28 00:10:00',1.9,'valid','generated'),
(268,23,'2026-10-28 00:15:00',1.95,'valid','generated'),
(269,23,'2026-10-28 00:20:00',2.0,'valid','generated'),
(270,23,'2026-10-28 00:25:00',2.05,'valid','generated'),
(271,23,'2026-10-28 00:30:00',2.1,'valid','generated'),
(272,23,'2026-10-28 00:35:00',2.15,'valid','generated'),
(273,23,'2026-10-28 00:40:00',2.2,'valid','generated'),
(274,23,'2026-10-28 00:45:00',2.25,'valid','generated'),
(275,23,'2026-10-28 00:50:00',7.5,'valid','generated'),
(276,23,'2026-10-28 00:55:00',7.5,'valid','generated'),
(277,24,'2026-10-28 00:00:00',10.8,'valid','generated'),
(278,24,'2026-10-28 00:05:00',10.9,'valid','generated'),
(279,24,'2026-10-28 00:10:00',11.0,'valid','generated'),
(280,24,'2026-10-28 00:15:00',11.1,'valid','generated'),
(281,24,'2026-10-28 00:20:00',11.2,'valid','generated'),
(282,24,'2026-10-28 00:25:00',11.3,'valid','generated'),
(283,24,'2026-10-28 00:30:00',11.4,'valid','generated'),
(284,24,'2026-10-28 00:35:00',11.5,'valid','generated'),
(285,24,'2026-10-28 00:40:00',11.6,'valid','generated'),
(286,24,'2026-10-28 00:45:00',11.7,'valid','generated'),
(287,24,'2026-10-28 00:50:00',21,'valid','generated'),
(288,24,'2026-10-28 00:55:00',21,'valid','generated'),
(289,25,'2026-10-28 00:00:00',80.7,'valid','generated'),
(290,25,'2026-10-28 00:05:00',80.9,'valid','generated'),
(291,25,'2026-10-28 00:10:00',81.1,'valid','generated'),
(292,25,'2026-10-28 00:15:00',81.3,'valid','generated'),
(293,25,'2026-10-28 00:20:00',81.5,'valid','generated'),
(294,25,'2026-10-28 00:25:00',81.7,'valid','generated'),
(295,25,'2026-10-28 00:30:00',81.9,'valid','generated'),
(296,25,'2026-10-28 00:35:00',82.1,'valid','generated'),
(297,25,'2026-10-28 00:40:00',82.3,'valid','generated'),
(298,25,'2026-10-28 00:45:00',82.5,'valid','generated'),
(299,25,'2026-10-28 00:50:00',82.7,'valid','generated'),
(300,25,'2026-10-28 00:55:00',82.9,'valid','generated'),
(301,26,'2026-10-28 00:00:00',1.9,'valid','generated'),
(302,26,'2026-10-28 00:05:00',1.95,'valid','generated'),
(303,26,'2026-10-28 00:10:00',2.0,'valid','generated'),
(304,26,'2026-10-28 00:15:00',2.05,'valid','generated'),
(305,26,'2026-10-28 00:20:00',2.1,'valid','generated'),
(306,26,'2026-10-28 00:25:00',2.15,'valid','generated'),
(307,26,'2026-10-28 00:30:00',2.2,'valid','generated'),
(308,26,'2026-10-28 00:35:00',2.25,'valid','generated'),
(309,26,'2026-10-28 00:40:00',2.3,'valid','generated'),
(310,26,'2026-10-28 00:45:00',2.35,'valid','generated'),
(311,26,'2026-10-28 00:50:00',2.4,'valid','generated'),
(312,26,'2026-10-28 00:55:00',2.45,'valid','generated'),
(313,27,'2026-10-28 00:00:00',10.9,'valid','generated'),
(314,27,'2026-10-28 00:05:00',11.0,'valid','generated'),
(315,27,'2026-10-28 00:10:00',11.1,'valid','generated'),
(316,27,'2026-10-28 00:15:00',11.2,'valid','generated'),
(317,27,'2026-10-28 00:20:00',11.3,'valid','generated'),
(318,27,'2026-10-28 00:25:00',11.4,'valid','generated'),
(319,27,'2026-10-28 00:30:00',11.5,'valid','generated'),
(320,27,'2026-10-28 00:35:00',11.6,'valid','generated'),
(321,27,'2026-10-28 00:40:00',11.7,'valid','generated'),
(322,27,'2026-10-28 00:45:00',11.8,'valid','generated'),
(323,27,'2026-10-28 00:50:00',11.9,'valid','generated'),
(324,27,'2026-10-28 00:55:00',12.0,'valid','generated'),
(325,28,'2026-10-28 00:00:00',81.0,'valid','generated'),
(326,28,'2026-10-28 00:05:00',81.2,'valid','generated'),
(327,28,'2026-10-28 00:10:00',81.4,'valid','generated'),
(328,28,'2026-10-28 00:15:00',81.6,'valid','generated'),
(329,28,'2026-10-28 00:20:00',81.8,'valid','generated'),
(330,28,'2026-10-28 00:25:00',82.0,'valid','generated'),
(331,28,'2026-10-28 00:30:00',82.2,'valid','generated'),
(332,28,'2026-10-28 00:35:00',82.4,'valid','generated'),
(333,28,'2026-10-28 00:40:00',82.6,'valid','generated'),
(334,28,'2026-10-28 00:45:00',82.8,'valid','generated'),
(335,28,'2026-10-28 00:50:00',96,'valid','generated'),
(336,28,'2026-10-28 00:55:00',96,'valid','generated'),
(337,29,'2026-10-28 00:00:00',2.0,'valid','generated'),
(338,29,'2026-10-28 00:05:00',2.05,'valid','generated'),
(339,29,'2026-10-28 00:10:00',2.1,'valid','generated'),
(340,29,'2026-10-28 00:15:00',2.15,'valid','generated'),
(341,29,'2026-10-28 00:20:00',2.2,'valid','generated'),
(342,29,'2026-10-28 00:25:00',2.25,'valid','generated'),
(343,29,'2026-10-28 00:30:00',2.3,'valid','generated'),
(344,29,'2026-10-28 00:35:00',2.35,'valid','generated'),
(345,29,'2026-10-28 00:40:00',2.4,'valid','generated'),
(346,29,'2026-10-28 00:45:00',2.45,'valid','generated'),
(347,29,'2026-10-28 00:50:00',5.2,'valid','generated'),
(348,29,'2026-10-28 00:55:00',5.2,'valid','generated'),
(349,30,'2026-10-28 00:00:00',11.0,'valid','generated'),
(350,30,'2026-10-28 00:05:00',11.1,'valid','generated'),
(351,30,'2026-10-28 00:10:00',11.2,'valid','generated'),
(352,30,'2026-10-28 00:15:00',11.3,'valid','generated'),
(353,30,'2026-10-28 00:20:00',11.4,'valid','generated'),
(354,30,'2026-10-28 00:25:00',11.5,'valid','generated'),
(355,30,'2026-10-28 00:30:00',11.6,'valid','generated'),
(356,30,'2026-10-28 00:35:00',11.7,'valid','generated'),
(357,30,'2026-10-28 00:40:00',11.8,'valid','generated'),
(358,30,'2026-10-28 00:45:00',11.9,'valid','generated'),
(359,30,'2026-10-28 00:50:00',17,'valid','generated'),
(360,30,'2026-10-28 00:55:00',17,'valid','generated'),
(361,31,'2026-10-28 00:00:00',81.3,'valid','generated'),
(362,31,'2026-10-28 00:05:00',81.5,'valid','generated'),
(363,31,'2026-10-28 00:10:00',81.7,'valid','generated'),
(364,31,'2026-10-28 00:15:00',81.9,'valid','generated'),
(365,31,'2026-10-28 00:20:00',82.1,'valid','generated'),
(366,31,'2026-10-28 00:25:00',82.3,'valid','generated'),
(367,31,'2026-10-28 00:30:00',82.5,'valid','generated'),
(368,31,'2026-10-28 00:35:00',82.7,'valid','generated'),
(369,31,'2026-10-28 00:40:00',82.9,'valid','generated'),
(370,31,'2026-10-28 00:45:00',83.1,'valid','generated'),
(371,31,'2026-10-28 00:50:00',108,'valid','generated'),
(372,31,'2026-10-28 00:55:00',108,'valid','generated'),
(373,32,'2026-10-28 00:00:00',2.1,'valid','generated'),
(374,32,'2026-10-28 00:05:00',2.15,'valid','generated'),
(375,32,'2026-10-28 00:10:00',2.2,'valid','generated'),
(376,32,'2026-10-28 00:15:00',2.25,'valid','generated'),
(377,32,'2026-10-28 00:20:00',2.3,'valid','generated'),
(378,32,'2026-10-28 00:25:00',2.35,'valid','generated'),
(379,32,'2026-10-28 00:30:00',2.4,'valid','generated'),
(380,32,'2026-10-28 00:35:00',2.45,'valid','generated'),
(381,32,'2026-10-28 00:40:00',2.5,'valid','generated'),
(382,32,'2026-10-28 00:45:00',2.55,'valid','generated'),
(383,32,'2026-10-28 00:50:00',7.5,'valid','generated'),
(384,32,'2026-10-28 00:55:00',7.5,'valid','generated'),
(385,33,'2026-10-28 00:00:00',11.1,'valid','generated'),
(386,33,'2026-10-28 00:05:00',11.2,'valid','generated'),
(387,33,'2026-10-28 00:10:00',11.3,'valid','generated'),
(388,33,'2026-10-28 00:15:00',11.4,'valid','generated'),
(389,33,'2026-10-28 00:20:00',11.5,'valid','generated'),
(390,33,'2026-10-28 00:25:00',11.6,'valid','generated'),
(391,33,'2026-10-28 00:30:00',11.7,'valid','generated'),
(392,33,'2026-10-28 00:35:00',11.8,'valid','generated'),
(393,33,'2026-10-28 00:40:00',11.9,'valid','generated'),
(394,33,'2026-10-28 00:45:00',12.0,'valid','generated'),
(395,33,'2026-10-28 00:50:00',21,'valid','generated'),
(396,33,'2026-10-28 00:55:00',21,'valid','generated'),
(397,34,'2026-10-28 00:00:00',81.6,'valid','generated'),
(398,34,'2026-10-28 00:05:00',81.8,'valid','generated'),
(399,34,'2026-10-28 00:10:00',82.0,'valid','generated'),
(400,34,'2026-10-28 00:15:00',82.2,'valid','generated'),
(401,34,'2026-10-28 00:20:00',82.4,'valid','generated'),
(402,34,'2026-10-28 00:25:00',82.6,'valid','generated'),
(403,34,'2026-10-28 00:30:00',82.8,'valid','generated'),
(404,34,'2026-10-28 00:35:00',83.0,'valid','generated'),
(405,34,'2026-10-28 00:40:00',83.2,'valid','generated'),
(406,34,'2026-10-28 00:45:00',83.4,'valid','generated'),
(407,34,'2026-10-28 00:50:00',83.6,'valid','generated'),
(408,34,'2026-10-28 00:55:00',83.8,'valid','generated'),
(409,35,'2026-10-28 00:00:00',2.2,'valid','generated'),
(410,35,'2026-10-28 00:05:00',2.25,'valid','generated'),
(411,35,'2026-10-28 00:10:00',2.3,'valid','generated'),
(412,35,'2026-10-28 00:15:00',2.35,'valid','generated'),
(413,35,'2026-10-28 00:20:00',2.4,'valid','generated'),
(414,35,'2026-10-28 00:25:00',2.45,'valid','generated'),
(415,35,'2026-10-28 00:30:00',2.5,'valid','generated'),
(416,35,'2026-10-28 00:35:00',2.55,'valid','generated'),
(417,35,'2026-10-28 00:40:00',2.6,'valid','generated'),
(418,35,'2026-10-28 00:45:00',2.65,'valid','generated'),
(419,35,'2026-10-28 00:50:00',2.7,'valid','generated'),
(420,35,'2026-10-28 00:55:00',2.75,'valid','generated'),
(421,36,'2026-10-28 00:00:00',11.2,'valid','generated'),
(422,36,'2026-10-28 00:05:00',11.3,'valid','generated'),
(423,36,'2026-10-28 00:10:00',11.4,'valid','generated'),
(424,36,'2026-10-28 00:15:00',11.5,'valid','generated'),
(425,36,'2026-10-28 00:20:00',11.6,'valid','generated'),
(426,36,'2026-10-28 00:25:00',11.7,'valid','generated'),
(427,36,'2026-10-28 00:30:00',11.8,'valid','generated'),
(428,36,'2026-10-28 00:35:00',11.9,'valid','generated'),
(429,36,'2026-10-28 00:40:00',12.0,'valid','generated'),
(430,36,'2026-10-28 00:45:00',12.1,'valid','generated'),
(431,36,'2026-10-28 00:50:00',12.2,'valid','generated'),
(432,36,'2026-10-28 00:55:00',12.3,'valid','generated');
INSERT INTO diagnostics(id_diagnostic,id_reading,severity,warning_high_used,critical_high_used,conclusion)
SELECT t.id_reading,t.id_reading,
CASE WHEN t.quality<>'valid' THEN 'unknown' WHEN t.value>=s.critical_high THEN 'critical' WHEN t.value>=s.warning_high THEN 'warning' ELSE 'normal' END,
s.warning_high,s.critical_high,
CASE WHEN t.value>=s.critical_high THEN 'Достигнут критический верхний порог' WHEN t.value>=s.warning_high THEN 'Достигнут верхний порог предупреждения' ELSE 'Верхние пороги не превышены' END
FROM telemetry t JOIN sensors s ON s.id_sensor=t.id_sensor;
INSERT INTO failure_predictions (id_prediction,id_node,calculated_at,horizon_hours,failure_probability,remaining_hours,model_version,source,explanation) VALUES
(1,1,'2026-10-28 01:00:00',72,0.4,115,'control_dataset_v2','generated','Контрольная запись для проверки хранения; модель прогнозирования не запускалась.'),
(2,3,'2026-10-28 01:00:00',72,0.7,110,'control_dataset_v2','generated','Контрольная запись для проверки хранения; модель прогнозирования не запускалась.'),
(3,5,'2026-10-28 01:00:00',72,0.1,105,'control_dataset_v2','generated','Контрольная запись для проверки хранения; модель прогнозирования не запускалась.'),
(4,7,'2026-10-28 01:00:00',72,0.4,100,'control_dataset_v2','generated','Контрольная запись для проверки хранения; модель прогнозирования не запускалась.'),
(5,9,'2026-10-28 01:00:00',72,0.7,95,'control_dataset_v2','generated','Контрольная запись для проверки хранения; модель прогнозирования не запускалась.'),
(6,11,'2026-10-28 01:00:00',72,0.1,90,'control_dataset_v2','generated','Контрольная запись для проверки хранения; модель прогнозирования не запускалась.'),
(7,13,'2026-10-28 01:00:00',72,0.4,85,'control_dataset_v2','generated','Контрольная запись для проверки хранения; модель прогнозирования не запускалась.'),
(8,15,'2026-10-28 01:00:00',72,0.7,80,'control_dataset_v2','generated','Контрольная запись для проверки хранения; модель прогнозирования не запускалась.'),
(9,17,'2026-10-28 01:00:00',72,0.1,75,'control_dataset_v2','generated','Контрольная запись для проверки хранения; модель прогнозирования не запускалась.'),
(10,19,'2026-10-28 01:00:00',72,0.4,70,'control_dataset_v2','generated','Контрольная запись для проверки хранения; модель прогнозирования не запускалась.'),
(11,21,'2026-10-28 01:00:00',72,0.7,65,'control_dataset_v2','generated','Контрольная запись для проверки хранения; модель прогнозирования не запускалась.'),
(12,23,'2026-10-28 01:00:00',72,0.1,60,'control_dataset_v2','generated','Контрольная запись для проверки хранения; модель прогнозирования не запускалась.');
INSERT INTO spare_parts (id_part,part_code,part_name,unit,unit_price) VALUES
(1,'PART-001','Фильтр масляный','шт.',750),
(2,'PART-002','Фильтр топливный','шт.',1000),
(3,'PART-003','Фильтр воздушный','шт.',1250),
(4,'PART-004','Фильтр гидравлический','шт.',1500),
(5,'PART-005','Ремень привода','шт.',1750),
(6,'PART-006','Датчик температуры','шт.',2000),
(7,'PART-007','Датчик давления','шт.',2250),
(8,'PART-008','Датчик вибрации','шт.',2500),
(9,'PART-009','Патрубок охлаждения','шт.',2750),
(10,'PART-010','Уплотнительное кольцо','шт.',3000),
(11,'PART-011','Подшипник','шт.',3250),
(12,'PART-012','Прокладка','шт.',3500),
(13,'PART-013','Хомут','шт.',3750),
(14,'PART-014','Предохранитель','шт.',4000),
(15,'PART-015','Реле','шт.',4250),
(16,'PART-016','Разъём','шт.',4500),
(17,'PART-017','Втулка','шт.',4750),
(18,'PART-018','Шайба','шт.',5000),
(19,'PART-019','Болт крепёжный','шт.',5250),
(20,'PART-020','Гайка','шт.',5500),
(21,'PART-021','Сальник','шт.',5750),
(22,'PART-022','Пружина','шт.',6000),
(23,'PART-023','Штуцер','шт.',6250),
(24,'PART-024','Клапан','шт.',6500);
INSERT INTO repair_orders (id_order,order_number,id_node,id_diagnostic,created_by,assigned_to,title,description,priority,created_at) VALUES
(1,'TO-V2-001',1,12,2,3,'Диагностика двигателя SK-001','Проверить состояние узла, оценить показания и зафиксировать результат работ.','high','2026-10-28 01:05:00'),
(2,'TO-V2-002',3,48,2,3,'Диагностика двигателя SK-002','Проверить состояние узла, оценить показания и зафиксировать результат работ.','high','2026-10-28 01:05:00'),
(3,'TO-V2-003',5,84,2,3,'Диагностика двигателя SK-003','Проверить состояние узла, оценить показания и зафиксировать результат работ.','medium','2026-10-28 01:05:00'),
(4,'TO-V2-004',7,120,2,3,'Диагностика двигателя SK-004','Проверить состояние узла, оценить показания и зафиксировать результат работ.','high','2026-10-28 01:05:00'),
(5,'TO-V2-005',9,156,2,3,'Диагностика двигателя SK-005','Проверить состояние узла, оценить показания и зафиксировать результат работ.','high','2026-10-28 01:05:00'),
(6,'TO-V2-006',11,192,2,3,'Диагностика двигателя SK-006','Проверить состояние узла, оценить показания и зафиксировать результат работ.','medium','2026-10-28 01:05:00'),
(7,'TO-V2-007',13,228,2,3,'Диагностика двигателя SK-007','Проверить состояние узла, оценить показания и зафиксировать результат работ.','high','2026-10-28 01:05:00'),
(8,'TO-V2-008',15,264,2,3,'Диагностика двигателя SK-008','Проверить состояние узла, оценить показания и зафиксировать результат работ.','high','2026-10-28 01:05:00'),
(9,'TO-V2-009',17,300,2,3,'Диагностика двигателя SK-009','Проверить состояние узла, оценить показания и зафиксировать результат работ.','medium','2026-10-28 01:05:00'),
(10,'TO-V2-010',19,336,2,3,'Диагностика двигателя SK-010','Проверить состояние узла, оценить показания и зафиксировать результат работ.','high','2026-10-28 01:05:00'),
(11,'TO-V2-011',21,372,2,3,'Диагностика двигателя SK-011','Проверить состояние узла, оценить показания и зафиксировать результат работ.','high','2026-10-28 01:05:00'),
(12,'TO-V2-012',23,408,2,3,'Диагностика двигателя SK-012','Проверить состояние узла, оценить показания и зафиксировать результат работ.','medium','2026-10-28 01:05:00');
UPDATE repair_orders SET status='approved' WHERE id_order=2;
UPDATE repair_orders SET status='approved' WHERE id_order=3;
UPDATE repair_orders SET status='in_progress' WHERE id_order=3;
UPDATE repair_orders SET status='approved' WHERE id_order=4;
UPDATE repair_orders SET status='in_progress' WHERE id_order=4;
UPDATE repair_orders SET status='completed',completed_at='2026-10-28 03:00:00',work_result='Выполнена диагностика и обслуживание узла' WHERE id_order=4;
UPDATE repair_orders SET status='approved' WHERE id_order=5;
UPDATE repair_orders SET status='in_progress' WHERE id_order=5;
UPDATE repair_orders SET status='completed',completed_at='2026-10-28 03:00:00',work_result='Выполнена диагностика и обслуживание узла' WHERE id_order=5;
UPDATE repair_orders SET status='closed',closed_at='2026-10-28 04:00:00' WHERE id_order=5;
UPDATE repair_orders SET status='rejected' WHERE id_order=6;
UPDATE repair_orders SET status='approved' WHERE id_order=8;
UPDATE repair_orders SET status='approved' WHERE id_order=9;
UPDATE repair_orders SET status='in_progress' WHERE id_order=9;
UPDATE repair_orders SET status='approved' WHERE id_order=10;
UPDATE repair_orders SET status='in_progress' WHERE id_order=10;
UPDATE repair_orders SET status='completed',completed_at='2026-10-28 03:00:00',work_result='Выполнена диагностика и обслуживание узла' WHERE id_order=10;
UPDATE repair_orders SET status='approved' WHERE id_order=11;
UPDATE repair_orders SET status='in_progress' WHERE id_order=11;
UPDATE repair_orders SET status='completed',completed_at='2026-10-28 03:00:00',work_result='Выполнена диагностика и обслуживание узла' WHERE id_order=11;
UPDATE repair_orders SET status='closed',closed_at='2026-10-28 04:00:00' WHERE id_order=11;
UPDATE repair_orders SET status='rejected' WHERE id_order=12;
INSERT INTO parts_used(id_order,id_part,quantity,unit_price) VALUES
(3,3,1,1250),
(4,4,1,1500),
(5,5,1,1750),
(9,9,1,2750),
(10,10,1,3000),
(11,11,1,3250),
(3,15,2,4250),
(4,16,2,4500),
(5,17,2,4750),
(9,21,2,5750),
(10,22,2,6000),
(11,23,2,6250);
COMMIT;
-- Состояние по последнему показанию КАЖДОГО датчика.
-- Отсутствие диагностики/недостоверные/устаревшие данные дают unknown.
-- Порог устаревания для этого представления: 15 минут, время UTC.
CREATE VIEW equipment_health AS
SELECT e.id_equipment,e.equipment_code,e.model,
 CASE WHEN SUM(CASE WHEN d.severity='critical' AND t.quality='valid'
 AND t.measured_at BETWEEN UTC_TIMESTAMP()-INTERVAL 15 MINUTE AND UTC_TIMESTAMP() THEN 1 ELSE 0 END)>0 THEN 'critical'
 WHEN SUM(CASE WHEN d.severity='warning' AND t.quality='valid'
 AND t.measured_at BETWEEN UTC_TIMESTAMP()-INTERVAL 15 MINUTE AND UTC_TIMESTAMP() THEN 1 ELSE 0 END)>0 THEN 'warning'
 WHEN COUNT(s.id_sensor)=0 OR SUM(CASE WHEN s.id_sensor IS NOT NULL AND
 (t.id_reading IS NULL OR d.id_diagnostic IS NULL OR t.quality<>'valid' OR d.severity='unknown'
 OR t.measured_at < UTC_TIMESTAMP()-INTERVAL 15 MINUTE OR t.measured_at>UTC_TIMESTAMP()) THEN 1 ELSE 0 END)>0 THEN 'unknown'
 ELSE 'normal' END AS health_status,
 COUNT(s.id_sensor) AS active_sensors,
 MAX(t.measured_at) AS last_measurement_at
FROM equipment e
LEFT JOIN equipment_nodes n ON n.id_equipment=e.id_equipment
LEFT JOIN sensors s ON s.id_node=n.id_node AND s.is_active=1
LEFT JOIN telemetry t ON t.id_sensor=s.id_sensor AND NOT EXISTS
 (SELECT 1 FROM telemetry newer WHERE newer.id_sensor=t.id_sensor AND newer.measured_at>t.measured_at)
LEFT JOIN diagnostics d ON d.id_reading=t.id_reading
GROUP BY e.id_equipment,e.equipment_code,e.model;
CREATE VIEW repair_order_costs AS
 SELECT r.id_order,r.order_number,COALESCE(SUM(p.quantity*p.unit_price),0) AS parts_cost
 FROM repair_orders r LEFT JOIN parts_used p ON p.id_order=r.id_order
 GROUP BY r.id_order,r.order_number;
-- Проверка результата импорта: 13 таблиц и 2 представления.
SHOW FULL TABLES;
SELECT * FROM equipment_health;
SELECT * FROM repair_order_costs;
