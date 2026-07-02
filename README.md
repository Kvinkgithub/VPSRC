🖥️ VPS Resources Checker by Kvink

Простой и красивый мониторинг ресурсов для VPS. Работает из коробки.

![Version](https://img.shields.io/badge/version-1.0-brightgreen)
![Platform](https://img.shields.io/badge/platform-Linux-blue)
![GitHub](https://img.shields.io/badge/license-MIT-green)

✨ Возможности


- 📊 Нагрузка CPU, память, диск
- 📋 Топ-5 процессов по CPU
- 📱 Статистика по olcRTC и x-ui
- 🛡️ Атаки на x-ui (TLS handshake)
- 🖥️ Диагностика GPU (drm/virtio_gpu)
- 📜 История за сегодня и вчера
- 🎨 Красивый и понятный интерфейс

---

🚀 Установка

```bash
curl -s https://raw.githubusercontent.com/Kvinkgithub/VPSRC/main/vpsrc.sh -o /usr/local/bin/vpsrc
chmod +x /usr/local/bin/vpsrc

```

🎯 Запуск

vpsrc

📋 Команды

1	🔄 Обновить

2	📊 olcRTC — детали

3	📊 x-ui — детали

4	📋 История за сегодня

5	🖥️ GPU — диагностика

0	👋 Выйти


📁 Логи:

Мониторинг автоматически сохраняет логи в
/var/log/cpu_monitor/cpu_YYYYMMDD.log

Посмотреть логи:
cat /var/log/cpu_monitor/cpu_$(date +%Y%m%d).log

📦 Требования
Linux

bash

curl (для установки)

👤 Автор
Kvink

GitHub: Kvinkgithub

📄 Лицензия
MIT
