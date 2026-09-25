# Модуль сбора телеметрических данных
def collect_data():
    print("Сбор данных с датчиков...")
    return {"temperature": 85, "vibration": 1.2, "pressure": 10}

if __name__ == "__main__":
    data = collect_data()
    print(f"Собраны данные: {data}")
