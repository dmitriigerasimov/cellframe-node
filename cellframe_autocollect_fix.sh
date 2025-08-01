#!/bin/bash

# Cellframe Node Autocollect Diagnostic and Fix Script
# Исправление проблемы с расхождением между block autocollect status и block list signed

set -e

# Конфигурация
NETWORK="KelVPN"
CHAIN="main" 
CERT_NAME="kelvpn.masternode"
WALLET_ADDR="Rj7J7MjNgdr8DX5ECdLLkdmYJ1j3tFghMqXv6sGtiaKmFV7rVnRZ5sLkknnxhyZzSsdnUUQdmzoyLC2eh45xCfm1u5GJpKcNtXD3RPxd"
FEE="0.01e+18"
CLI_CMD="cellframe-node-cli"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функции логирования
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Проверка доступности CLI
check_cli() {
    log_info "Проверка доступности Cellframe Node CLI..."
    if ! command -v $CLI_CMD &> /dev/null; then
        log_error "Cellframe Node CLI не найден. Убедитесь, что он установлен и доступен в PATH."
        exit 1
    fi
    log_success "CLI доступен"
}

# Проверка статуса сети
check_network_status() {
    log_info "Проверка статуса сети $NETWORK..."
    
    local status_output
    status_output=$($CLI_CMD net get status -net $NETWORK 2>&1)
    
    if echo "$status_output" | grep -q "offline\|error\|failed"; then
        log_warning "Сеть может быть не полностью синхронизирована:"
        echo "$status_output"
    else
        log_success "Сеть синхронизирована"
    fi
}

# Получение списка блоков autocollect
get_autocollect_blocks() {
    log_info "Получение списка блоков из autocollect status..."
    
    local autocollect_blocks
    autocollect_blocks=$($CLI_CMD block autocollect status -net $NETWORK -chain $CHAIN 2>/dev/null | grep "0x" || true)
    
    if [ -z "$autocollect_blocks" ]; then
        log_warning "Список autocollect пуст"
        return 1
    fi
    
    echo "$autocollect_blocks" > /tmp/autocollect_blocks.txt
    local count=$(echo "$autocollect_blocks" | wc -l)
    log_info "Найдено $count блоков в autocollect status"
    
    return 0
}

# Получение списка подписанных блоков
get_signed_blocks() {
    log_info "Получение списка подписанных блоков..."
    
    local signed_blocks
    signed_blocks=$($CLI_CMD block list signed -net $NETWORK -cert $CERT_NAME -unspent 2>/dev/null | grep "0x" || true)
    
    if [ -z "$signed_blocks" ]; then
        log_warning "Список подписанных блоков пуст"
        return 1
    fi
    
    echo "$signed_blocks" > /tmp/signed_blocks.txt
    local count=$(echo "$signed_blocks" | wc -l)
    log_info "Найдено $count подписанных неизрасходованных блоков"
    
    return 0
}

# Сравнение списков блоков
compare_block_lists() {
    log_info "Сравнение списков блоков..."
    
    if [ ! -f /tmp/autocollect_blocks.txt ] || [ ! -f /tmp/signed_blocks.txt ]; then
        log_error "Не удалось получить списки блоков для сравнения"
        return 1
    fi
    
    # Проверка пересечений
    local common_blocks
    common_blocks=$(comm -12 <(sort /tmp/autocollect_blocks.txt) <(sort /tmp/signed_blocks.txt))
    
    if [ -n "$common_blocks" ]; then
        log_success "Найдены общие блоки между списками:"
        echo "$common_blocks"
    else
        log_warning "Нет общих блоков между autocollect и signed списками!"
    fi
    
    # Блоки только в autocollect
    local autocollect_only
    autocollect_only=$(comm -23 <(sort /tmp/autocollect_blocks.txt) <(sort /tmp/signed_blocks.txt))
    
    if [ -n "$autocollect_only" ]; then
        log_warning "Блоки только в autocollect (возможно уже собраны):"
        echo "$autocollect_only"
        echo "$autocollect_only" > /tmp/potentially_collected_blocks.txt
    fi
    
    # Блоки только в signed
    local signed_only
    signed_only=$(comm -13 <(sort /tmp/autocollect_blocks.txt) <(sort /tmp/signed_blocks.txt))
    
    if [ -n "$signed_only" ]; then
        log_info "Блоки только в signed (готовы к сбору):"
        echo "$signed_only"
        echo "$signed_only" > /tmp/ready_to_collect_blocks.txt
    fi
}

# Проверка статуса наград для блоков
check_reward_status() {
    log_info "Проверка статуса наград через srv_stake..."
    
    local reward_output
    reward_output=$($CLI_CMD srv_stake reward -net $NETWORK -cert $CERT_NAME 2>/dev/null || true)
    
    if [ -n "$reward_output" ]; then
        echo "$reward_output" > /tmp/reward_status.txt
        log_success "Статус наград сохранен в /tmp/reward_status.txt"
    else
        log_warning "Не удалось получить статус наград"
    fi
}

# Обновление autocollect
renew_autocollect() {
    log_info "Обновление autocollect..."
    
    local renew_output
    renew_output=$($CLI_CMD block autocollect renew -net $NETWORK -cert $CERT_NAME -addr $WALLET_ADDR 2>&1 || true)
    
    if echo "$renew_output" | grep -q "success\|ok\|completed"; then
        log_success "Autocollect успешно обновлен"
    else
        log_warning "Обновление autocollect завершилось с предупреждениями:"
        echo "$renew_output"
    fi
    
    # Небольшая пауза для обработки
    sleep 2
}

# Сбор наград с проверенных блоков
collect_rewards() {
    log_info "Попытка сбора наград с доступных блоков..."
    
    if [ ! -f /tmp/ready_to_collect_blocks.txt ]; then
        log_warning "Нет блоков готовых к сбору"
        return 0
    fi
    
    local blocks_to_collect
    blocks_to_collect=$(cat /tmp/ready_to_collect_blocks.txt | tr '\n' ',' | sed 's/,$//')
    
    if [ -z "$blocks_to_collect" ]; then
        log_warning "Список блоков для сбора пуст"
        return 0
    fi
    
    log_info "Попытка сбора наград с блоков: $blocks_to_collect"
    
    local collect_output
    collect_output=$($CLI_CMD block reward collect -net $NETWORK -chain $CHAIN -cert $CERT_NAME -addr $WALLET_ADDR -hashes $blocks_to_collect -fee $FEE 2>&1 || true)
    
    if echo "$collect_output" | grep -q "already collected\|Can't create reward collect TX"; then
        log_warning "Некоторые блоки уже собраны или недоступны для сбора:"
        echo "$collect_output"
    elif echo "$collect_output" | grep -q "success\|ok\|completed\|transaction"; then
        log_success "Сбор наград завершен успешно"
        echo "$collect_output"
    else
        log_error "Ошибка при сборе наград:"
        echo "$collect_output"
    fi
}

# Финальная проверка
final_verification() {
    log_info "Финальная проверка состояния..."
    
    sleep 5  # Пауза для обработки транзакций
    
    # Повторное получение списков
    log_info "Повторная проверка autocollect status..."
    get_autocollect_blocks
    
    log_info "Повторная проверка signed blocks..."
    get_signed_blocks
    
    compare_block_lists
}

# Создание отчета
create_report() {
    local report_file="cellframe_autocollect_report_$(date +%Y%m%d_%H%M%S).txt"
    
    log_info "Создание отчета: $report_file"
    
    {
        echo "========================================"
        echo "Cellframe Node Autocollect Diagnostic Report"
        echo "Generated: $(date)"
        echo "Network: $NETWORK"
        echo "Chain: $CHAIN"
        echo "Certificate: $CERT_NAME"
        echo "========================================"
        echo
        
        if [ -f /tmp/autocollect_blocks.txt ]; then
            echo "Blocks in autocollect status:"
            cat /tmp/autocollect_blocks.txt
            echo
        fi
        
        if [ -f /tmp/signed_blocks.txt ]; then
            echo "Signed unspent blocks:"
            cat /tmp/signed_blocks.txt
            echo
        fi
        
        if [ -f /tmp/potentially_collected_blocks.txt ]; then
            echo "Potentially already collected blocks:"
            cat /tmp/potentially_collected_blocks.txt
            echo
        fi
        
        if [ -f /tmp/ready_to_collect_blocks.txt ]; then
            echo "Blocks ready to collect:"
            cat /tmp/ready_to_collect_blocks.txt
            echo
        fi
        
        if [ -f /tmp/reward_status.txt ]; then
            echo "Reward status (srv_stake):"
            cat /tmp/reward_status.txt
            echo
        fi
        
    } > "$report_file"
    
    log_success "Отчет сохранен в $report_file"
}

# Очистка временных файлов
cleanup() {
    log_info "Очистка временных файлов..."
    rm -f /tmp/autocollect_blocks.txt
    rm -f /tmp/signed_blocks.txt
    rm -f /tmp/potentially_collected_blocks.txt
    rm -f /tmp/ready_to_collect_blocks.txt
    rm -f /tmp/reward_status.txt
}

# Главная функция
main() {
    echo -e "${BLUE}====================================================================${NC}"
    echo -e "${BLUE}    Cellframe Node Autocollect Diagnostic and Fix Script${NC}"
    echo -e "${BLUE}====================================================================${NC}"
    echo
    
    # Проверки
    check_cli
    check_network_status
    
    echo
    log_info "Начало диагностики..."
    
    # Получение текущего состояния
    get_autocollect_blocks
    get_signed_blocks
    check_reward_status
    
    # Анализ
    compare_block_lists
    
    echo
    log_info "Начало исправления..."
    
    # Исправления
    renew_autocollect
    
    # Сбор доступных наград
    collect_rewards
    
    # Финальная проверка
    final_verification
    
    # Создание отчета
    create_report
    
    # Очистка
    cleanup
    
    echo
    log_success "Диагностика и исправление завершены!"
    echo -e "${YELLOW}Рекомендации:${NC}"
    echo "1. Проверьте созданный отчет для детального анализа"
    echo "2. Если проблема повторяется, рассмотрите обновление до последней версии"
    echo "3. Настройте регулярный мониторинг состояния autocollect"
}

# Обработка сигналов
trap cleanup EXIT

# Запуск
main "$@"