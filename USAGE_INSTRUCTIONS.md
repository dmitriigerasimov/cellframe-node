# Инструкция по исправлению проблемы Block Autocollect в Cellframe Node

## Проблема

В сети KelVPN обнаружена проблема, когда команда `block autocollect status` показывает блоки, за которые награды уже были собраны, что приводит к расхождению с `block list signed -unspent`.

## Решение

Создано комплексное решение, включающее:
1. **Анализ проблемы** - документ `cellframe_autocollect_issue_analysis.md`
2. **Автоматический скрипт диагностики и исправления** - `cellframe_autocollect_fix.sh`

## Быстрое решение

### 1. Ручное исправление

```bash
# Шаг 1: Обновить autocollect
cellframe-node-cli block autocollect renew -net KelVPN -cert kelvpn.masternode -addr Rj7J7MjNgdr8DX5ECdLLkdmYJ1j3tFghMqXv6sGtiaKmFV7rVnRZ5sLkknnxhyZzSsdnUUQdmzoyLC2eh45xCfm1u5GJpKcNtXD3RPxd

# Шаг 2: Проверить доступные блоки
cellframe-node-cli block list signed -net KelVPN -cert kelvpn.masternode -unspent

# Шаг 3: Собрать награды с проверенных блоков
cellframe-node-cli block reward collect -net KelVPN -chain main -cert kelvpn.masternode -addr Rj7J7MjNgdr8DX5ECdLLkdmYJ1j3tFghMqXv6sGtiaKmFV7rVnRZ5sLkknnxhyZzSsdnUUQdmzoyLC2eh45xCfm1u5GJpKcNtXD3RPxd -hashes <список_хешей> -fee 0.01e+18
```

### 2. Автоматическое исправление

```bash
# Скачать и запустить скрипт исправления
chmod +x cellframe_autocollect_fix.sh
./cellframe_autocollect_fix.sh
```

## Подробная инструкция

### Предварительные требования

1. **Доступ к серверу валидатора:**
   ```bash
   ssh user@31.130.154.78
   ```

2. **Проверка работоспособности CLI:**
   ```bash
   cellframe-node-cli --help
   ```

3. **Проверка синхронизации сети:**
   ```bash
   cellframe-node-cli net get status -net KelVPN
   ```

### Шаг 1: Диагностика проблемы

1. **Получить список autocollect:**
   ```bash
   cellframe-node-cli block autocollect status -net KelVPN -chain main
   ```

2. **Получить список подписанных блоков:**
   ```bash
   cellframe-node-cli block list signed -net KelVPN -cert kelvpn.masternode -unspent
   ```

3. **Проверить статус наград:**
   ```bash
   cellframe-node-cli srv_stake reward -net KelVPN -cert kelvpn.masternode
   ```

### Шаг 2: Сравнение списков

Создайте файлы для сравнения:
```bash
# Сохранить autocollect блоки
cellframe-node-cli block autocollect status -net KelVPN -chain main | grep "0x" > autocollect_blocks.txt

# Сохранить подписанные блоки
cellframe-node-cli block list signed -net KelVPN -cert kelvpn.masternode -unspent | grep "0x" > signed_blocks.txt

# Сравнить списки
diff autocollect_blocks.txt signed_blocks.txt
```

### Шаг 3: Исправление

1. **Обновить autocollect:**
   ```bash
   cellframe-node-cli block autocollect renew -net KelVPN -cert kelvpn.masternode -addr Rj7J7MjNgdr8DX5ECdLLkdmYJ1j3tFghMqXv6sGtiaKmFV7rVnRZ5sLkknnxhyZzSsdnUUQdmzoyLC2eh45xCfm1u5GJpKcNtXD3RPxd
   ```

2. **Собрать награды с доступных блоков:**
   ```bash
   # Используйте только блоки из signed_blocks.txt
   cellframe-node-cli block reward collect -net KelVPN -chain main -cert kelvpn.masternode -addr Rj7J7MjNgdr8DX5ECdLLkdmYJ1j3tFghMqXv6sGtiaKmFV7rVnRZ5sLkknnxhyZzSsdnUUQdmzoyLC2eh45xCfm1u5GJpKcNtXD3RPxd -hashes $(cat signed_blocks.txt | tr '\n' ',' | sed 's/,$//') -fee 0.01e+18
   ```

### Шаг 4: Проверка результата

1. **Повторная проверка autocollect:**
   ```bash
   cellframe-node-cli block autocollect status -net KelVPN -chain main
   ```

2. **Проверка изменений в signed blocks:**
   ```bash
   cellframe-node-cli block list signed -net KelVPN -cert kelvpn.masternode -unspent
   ```

## Использование автоматического скрипта

### Конфигурация скрипта

Перед запуском убедитесь, что в скрипте `cellframe_autocollect_fix.sh` указаны правильные параметры:

```bash
# Откройте скрипт для редактирования
nano cellframe_autocollect_fix.sh

# Проверьте эти параметры:
NETWORK="KelVPN"
CHAIN="main" 
CERT_NAME="kelvpn.masternode"
WALLET_ADDR="Rj7J7MjNgdr8DX5ECdLLkdmYJ1j3tFghMqXv6sGtiaKmFV7rVnRZ5sLkknnxhyZzSsdnUUQdmzoyLC2eh45xCfm1u5GJpKcNtXD3RPxd"
FEE="0.01e+18"
```

### Запуск скрипта

```bash
# Сделать скрипт исполняемым
chmod +x cellframe_autocollect_fix.sh

# Запустить диагностику и исправление
./cellframe_autocollect_fix.sh
```

### Анализ результатов

Скрипт создаст отчет с именем `cellframe_autocollect_report_YYYYMMDD_HHMMSS.txt`, содержащий:
- Список блоков в autocollect
- Список подписанных блоков
- Блоки готовые к сбору
- Блоки, возможно уже собранные
- Статус наград

## Мониторинг и профилактика

### Создание регулярного мониторинга

1. **Создать скрипт мониторинга:**
   ```bash
   cat > autocollect_monitor.sh << 'EOF'
   #!/bin/bash
   
   # Простой мониторинг autocollect
   AUTOCOLLECT_COUNT=$(cellframe-node-cli block autocollect status -net KelVPN -chain main | grep -c "0x" || echo "0")
   SIGNED_COUNT=$(cellframe-node-cli block list signed -net KelVPN -cert kelvpn.masternode -unspent | grep -c "0x" || echo "0")
   
   echo "$(date): Autocollect blocks: $AUTOCOLLECT_COUNT, Signed blocks: $SIGNED_COUNT"
   
   if [ "$AUTOCOLLECT_COUNT" -gt 0 ] && [ "$SIGNED_COUNT" -eq 0 ]; then
       echo "WARNING: Possible autocollect sync issue detected!"
   fi
   EOF
   
   chmod +x autocollect_monitor.sh
   ```

2. **Добавить в crontab:**
   ```bash
   # Проверка каждые 30 минут
   crontab -e
   
   # Добавить строку:
   */30 * * * * /path/to/autocollect_monitor.sh >> /var/log/autocollect_monitor.log 2>&1
   ```

### Обновление версии

Убедитесь, что используется версия Cellframe Node >= 5.3-277, где исправлена проблема с автоматическим сбором наград.

```bash
# Проверить версию
cellframe-node-cli version

# Или проверить в логах
journalctl -u cellframe-node | grep -i version
```

## Поддержка и устранение неполадок

### Часто встречающиеся ошибки

1. **"Block reward is already collected"**
   - Блок уже обработан, исключите его из списка для сбора

2. **"Can't create reward collect TX"**
   - Проверьте баланс для оплаты комиссии
   - Убедитесь в корректности адреса кошелька

3. **"Socket read error"**
   - Проверьте, запущен ли сервис cellframe-node
   - Проверьте доступность CLI

### Контакты для поддержки

При серьезных проблемах обратитесь к разработчикам Cellframe:
- GitHub: https://github.com/demlabsinc/cellframe-node
- Telegram: @cellframe_dev
- Technical support: tech_support@cellframe.net

## Заключение

Данное решение должно устранить проблему с рассинхронизацией между `block autocollect status` и `block list signed`. Регулярное выполнение `autocollect renew` и мониторинг состояния помогут предотвратить повторение проблемы.

**Важно:** Всегда используйте `block list signed -unspent` как источник истины для определения блоков доступных для сбора наград.