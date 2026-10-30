"""Импорт SQL лабораторной 4 только в новую изолированную базу CI."""
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from pdm.db import connect,settings

config=settings()
if config['database']!='sibka_pdm_ci':
    raise SystemExit('Разрешён импорт только в sibka_pdm_ci')
config['database']='mysql'
connection=connect(config)
sql=(Path(__file__).resolve().parents[1]/'database/v2/SibKa_PdM_v2.sql').read_text(encoding='utf-8')
sql=sql.replace('`sibka_pdm_v2`','`sibka_pdm_ci`')
delimiter=';';buffer=''
try:
    with connection.cursor() as cursor:
        for line in sql.splitlines():
            if line.strip().startswith('--') or not line.strip():continue
            if line.startswith('DELIMITER '):
                delimiter=line.split()[1];continue
            buffer+=line+'\n'
            if buffer.rstrip().endswith(delimiter):
                statement=buffer.rstrip()[:-len(delimiter)].strip()
                if statement:cursor.execute(statement)
                buffer=''
    connection.commit()
    print('Изолированная база sibka_pdm_ci создана; SQL и триггеры импортированы.')
finally:
    connection.close()
