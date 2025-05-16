#!/bin/bash

LOG_FILE="system_state_$(date +%Y%m%d_%H%M%S).log"

# Если передан параметр — длительность трассировки в секундах
if [[ $# -ge 1 && $1 =~ ^[0-9]+$ ]]; then
    TRACE_DURATION=$1
else
    TRACE_DURATION=5
fi

echo "########## СБОР И АНАЛИЗ ЛОГОВ ##########" > "$LOG_FILE"

##### ЗАДАНИЕ 1: Состояние системы при запуске #####
get_system_info() {
    echo "===== Состояние системы на момент инициализации =====" >> "$LOG_FILE"
    echo "Дата: $(date)" >> "$LOG_FILE"
    echo "Хост: $(hostname)" >> "$LOG_FILE"
    echo "Ядер CPU: $(nproc)" >> "$LOG_FILE"
    echo "Версия ядра ОС: $(uname -r)" >> "$LOG_FILE"
    echo "Длительность трассировки: ${TRACE_DURATION} сек" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
}

get_process_list() {
    echo "----- Список процессов -----" >> "$LOG_FILE"
    ps -eo pid,comm,state --sort=pid | awk '
        NR==1 {print "PID    COMMAND         STATE"}
        NR>1 {
            process_count[$2]++
            printf "%-6s %-15s %-10s #%d\n", $1, $2, $3, process_count[$2]
        }
    ' >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
}

##### ЗАДАНИЕ 2: Трассировка переключений задач #####
start_tracing() {
    echo "===== Трассировка переключений задач (sched_switch) =====" >> "$LOG_FILE"
    echo "Событие: sched_switch" >> "$LOG_FILE"

    TRACE_TEMP_FILE=$(mktemp)

    # Настройка трассировки
    echo 'sched:sched_switch' | sudo tee /sys/kernel/debug/tracing/set_event > /dev/null
    echo 0 | sudo tee /sys/kernel/debug/tracing/tracing_on > /dev/null
    echo '' | sudo tee /sys/kernel/debug/tracing/trace > /dev/null
    echo 1 | sudo tee /sys/kernel/debug/tracing/tracing_on > /dev/null

    sleep "$TRACE_DURATION"

    echo 0 | sudo tee /sys/kernel/debug/tracing/tracing_on > /dev/null
    sudo cat /sys/kernel/debug/tracing/trace > "$TRACE_TEMP_FILE"
    cat "$TRACE_TEMP_FILE" >> "$LOG_FILE"

    echo "" >> "$LOG_FILE"
    echo "----- Переключения задач по ядрам -----" >> "$LOG_FILE"

    awk '
    /sched_switch/ {
        match($0, /CPU#([0-9]+)/, cpu);
        match($0, /prev_comm=([^ ]+)/, prev);
        match($0, /next_comm=([^ ]+)/, next);
        match($0, /([0-9]+\.[0-9]+)/, t);
        if (cpu[1] && prev[1] && next[1]) {
            printf "CPU%s: %s -> %s at %s\n", cpu[1], prev[1], next[1], t[1];
        }
    }
    ' "$TRACE_TEMP_FILE" >> "$LOG_FILE"

    mv "$TRACE_TEMP_FILE" trace_raw.log
}

##### ЗАДАНИЕ 3: Системные метрики #####
compute_cpu_metrics() {
    local before_file="$1"
    local after_file="$2"

    echo "===== Системные метрики =====" >> "$LOG_FILE"

    local before_cpu_line=$(grep '^cpu ' "$before_file")
    local after_cpu_line=$(grep '^cpu ' "$after_file")

    read -r -a before <<< "$before_cpu_line"
    read -r -a after <<< "$after_cpu_line"

    user_diff=$((after[1] - before[1]))
    nice_diff=$((after[2] - before[2]))
    system_diff=$((after[3] - before[3]))
    idle_diff=$((after[4] - before[4]))

    total_jiffies=$((user_diff + nice_diff + system_diff + idle_diff))
    USER_HZ=$(getconf CLK_TCK)
    [ -z "$USER_HZ" ] && USER_HZ=100

    echo "Общее время CPU (сек): $(echo "scale=2; $total_jiffies / $USER_HZ" | bc)" >> "$LOG_FILE"
    echo " - Время простаивания: $(echo "scale=2; $idle_diff / $USER_HZ" | bc) сек" >> "$LOG_FILE"
    echo " - Задачи (user+nice): $(echo "scale=2; ($user_diff + $nice_diff) / $USER_HZ" | bc) сек" >> "$LOG_FILE"
    echo " - Системное время (kernel): $(echo "scale=2; $system_diff / $USER_HZ" | bc) сек" >> "$LOG_FILE"

    echo "Процент простоя: $(echo "scale=2; $idle_diff / $total_jiffies * 100" | bc)%" >> "$LOG_FILE"
    echo "Процент задач (user+nice): $(echo "scale=2; ($user_diff + $nice_diff) / $total_jiffies * 100" | bc)%" >> "$LOG_FILE"
    echo "Процент переключений (kernel): $(echo "scale=2; $system_diff / $total_jiffies * 100" | bc)%" >> "$LOG_FILE"

    echo "" >> "$LOG_FILE"
}

##### ЗАДАНИЕ 4: Анализ активности процессов #####
analyze_process_activity() {
    echo "===== Анализ активности процессов =====" >> "$LOG_FILE"
    echo "----- Время состояний процессов (running, sleeping, runnable) -----" >> "$LOG_FILE"

    awk '
    BEGIN {
        first_timestamp = 0
        last_timestamp = 0
    }
    /sched_switch/ {
        # Извлечь timestamp (пример: "12345.6789: sched_switch")
        if (match($0, /[0-9]+\.[0-9]+/)) {
            timestamp = substr($0, RSTART, RLENGTH) + 0
            if (first_timestamp == 0) {
                first_timestamp = timestamp
            }
            last_timestamp = timestamp
        }

        # Инициализация переменных
        prev_pid = -1
        next_pid = -1
        prev_state = ""

        # Извлечь prev_pid
        if (match($0, /prev_pid=[0-9]+/)) {
            val = substr($0, RSTART, RLENGTH)
            split(val, arr, "=")
            prev_pid = arr[2]
        }

        # Извлечь next_pid
        if (match($0, /next_pid=[0-9]+/)) {
            val = substr($0, RSTART, RLENGTH)
            split(val, arr, "=")
            next_pid = arr[2]
        }

        # Извлечь prev_state
        if (match($0, /prev_state=[A-Z]+/)) {
            val = substr($0, RSTART, RLENGTH)
            split(val, arr, "=")
            prev_state = arr[2]
        }

        # Инициализация состояний
        if (!(prev_pid in last_state) && prev_pid != -1) {
            last_state[prev_pid] = ""
            state_start[prev_pid] = first_timestamp
            total_running[prev_pid] = 0
            total_sleeping[prev_pid] = 0
            total_runnable[prev_pid] = 0
        }
        if (!(next_pid in last_state) && next_pid != -1) {
            last_state[next_pid] = ""
            state_start[next_pid] = first_timestamp
            total_running[next_pid] = 0
            total_sleeping[next_pid] = 0
            total_runnable[next_pid] = 0
        }

        # Обновление времени состояний для всех известных PID
        for (pid in last_state) {
            duration = timestamp - state_start[pid]
            if (duration < 0) duration = 0
            if (last_state[pid] == "running") {
                total_running[pid] += duration
            } else if (last_state[pid] == "sleeping") {
                total_sleeping[pid] += duration
            } else if (last_state[pid] == "runnable") {
                total_runnable[pid] += duration
            }
            state_start[pid] = timestamp
        }

        # Обновить состояние prev_pid
        if (prev_pid != -1) {
            if (prev_state ~ /S|D/) {
                last_state[prev_pid] = "sleeping"
            } else if (prev_state == "R") {
                last_state[prev_pid] = "runnable"
            } else {
                last_state[prev_pid] = "unknown"
            }
        }

        # Обновить состояние next_pid
        if (next_pid != -1) {
            last_state[next_pid] = "running"
        }
    }
    END {
        # Добавить остаточное время для каждого PID
        for (pid in last_state) {
            duration = last_timestamp - state_start[pid]
            if (duration < 0) duration = 0
            if (last_state[pid] == "running") {
                total_running[pid] += duration
            } else if (last_state[pid] == "sleeping") {
                total_sleeping[pid] += duration
            } else if (last_state[pid] == "runnable") {
                total_runnable[pid] += duration
            }
        }

        # Вывести данные
        for (pid in total_running) {
            printf "%d(running) for %.2f -> %d(sleeping) for %.2f -> %d(runnable) for %.2f\n",
                   pid, total_running[pid],
                   pid, total_sleeping[pid],
                   pid, total_runnable[pid]
        }
    }
    ' trace_raw.log >> "$LOG_FILE"

    echo "" >> "$LOG_FILE"
}



##### Доп. Инфо: Топ процессы и загрузка #####
get_detailed_info() {
    ps -eo pid,comm,%cpu --sort=-%cpu | head -n 10 >> "$LOG_FILE"
    echo "--- Средняя загрузка системы ---" >> "$LOG_FILE"
    cat /proc/loadavg >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
}

##### Основной вызов #####

get_system_info
get_process_list

BEFORE_STAT=$(mktemp)
cat /proc/stat > "$BEFORE_STAT"

start_tracing

AFTER_STAT=$(mktemp)
cat /proc/stat > "$AFTER_STAT"

compute_cpu_metrics "$BEFORE_STAT" "$AFTER_STAT"
analyze_process_activity
get_detailed_info

rm "$BEFORE_STAT" "$AFTER_STAT"
rm -f trace_raw.log

echo "Лог сохранен в $LOG_FILE"
