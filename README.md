# SibKa PdM

Система предиктивного технического обслуживания карьерной техники АО «СибКа».

Локальный прототип: **Python 3.11+ · Flask · MySQL/MariaDB**.

## Лабораторная 7

[Инструкция по запуску и проверке](docs/lab7/README.md)

Сквозной сценарий: обзор парка → карточка техники → диагностика узла → создание заявки → сохранение в БД → история и список заявок.

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
cp config.example.json config.local.json
python run_web.py
```

Перед запуском включите MySQL в XAMPP и проверьте наличие базы `sibka_pdm_v2`. Откройте http://127.0.0.1:5001.

## Тестирование

```bash
python -m pip install -r requirements-dev.txt
python -m pytest tests/ -q
```

[GitHub Actions](../../actions) запускает модульные и интеграционные проверки на отдельной MariaDB. Исходная схема базы находится в `database/v2/`.

[Макеты Figma](https://www.figma.com/design/wIpghANcxbR9EnrTGasLC2) · [Документация Wiki](https://github.com/SoftyMaNA/SibKa_PdM_Project/wiki)
