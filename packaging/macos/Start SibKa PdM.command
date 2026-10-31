#!/bin/bash
cd "$(dirname "$0")" || exit 1
./runtime/sibka-pdm
status=$?
if [ "$status" -ne 0 ]; then
  echo "Запуск завершился с ошибкой. Проверьте текст выше и файл настроек подключения."
  read -r -p "Нажмите Enter, чтобы закрыть окно."
fi
exit "$status"
