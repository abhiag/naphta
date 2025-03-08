#!/usr/bin/env bash

# NapthaAI Cluster Manager v3.0
# Full featured management system with menu interface

# --------------------------
# Configuration
# --------------------------
declare -A CONFIG=(
    [NUM_NODES]=100             # Number of nodes to launch
    [START_PORT]=8070           # Base port number (updated as requested)
    [BASE_DIR]="naptha_nodes"   # Parent directory for nodes
    [REPO_URL]="https://github.com/NapthaAI/naptha-node.git"
    [ENV_TEMPLATE]=".env"       # Template environment file
    [BATCH_SIZE]=10             # Nodes to process simultaneously
    [LOG_DIR]="logs"            # Centralized log directory
    [CHECK_INTERVAL]=5          # Health check interval in seconds
    [API_TIMEOUT]=2             # API response timeout
)

# --------------------------
# UI Functions
# --------------------------
show_header() {
    clear
    echo "========================================"
    echo " NapthaAI Node Cluster Manager v3.0"
    echo "========================================"
    echo "Nodes: ${CONFIG[NUM_NODES]}  |  Port Range: ${CONFIG[START_PORT]}-$((CONFIG[START_PORT] + CONFIG[NUM_NODES] - 1))"
    echo "----------------------------------------"
}

show_menu() {
    echo "1. Start All Nodes"
    echo "2. Stop All Nodes"
    echo "3. Restart All Nodes"
    echo "4. Check Node Status"
    echo "5. View Node Logs"
    echo "6. Cluster Health Monitor"
    echo "7. Update All Nodes"
    echo "8. Cleanup System"
    echo "9. Configuration"
    echo "0. Exit"
    echo "----------------------------------------"
    read -p "Enter choice [0-9]: " choice
}

# --------------------------
# Core Functions
# --------------------------
check_dependencies() {
    local deps=("git" "lsof" "curl")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            echo "Error: Required dependency '$dep' not found"
            exit 1
        fi
    done
}

is_port_available() {
    ! lsof -i :"$1" > /dev/null
}

find_available_port() {
    local port="${CONFIG[START_PORT]}"
    while [[ $port -lt $((CONFIG[START_PORT] + CONFIG[NUM_NODES])) ]]; do
        if is_port_available "$port"; then
            echo "$port"
            return 0
        fi
        ((port++))
    done
    echo "Error: No available ports in range"
    return 1
}

setup_node() {
    local node_id=$1
    local node_dir="${CONFIG[BASE_DIR]}/node_${node_id}"
    
    echo "Setting up node ${node_id}..."
    
    # Clone repository if needed
    if [[ ! -d "${node_dir}/.git" ]]; then
        if ! git clone "${CONFIG[REPO_URL]}" "$node_dir"; then
            echo "Failed to clone repository for node ${node_id}"
            return 1
        fi
    fi

    # Update repository
    (
        cd "$node_dir" || return 1
        git pull --quiet || return 1
    )

    # Configure environment
    local node_port=$(find_available_port)
    if [[ $? -ne 0 ]]; then
        echo "Failed to find port for node ${node_id}"
        return 1
    fi
    
    sed "s/^NODE_PORT=.*/NODE_PORT=${node_port}/" "${CONFIG[ENV_TEMPLATE]}" > "${node_dir}/.env"

    echo "Node ${node_id} configured on port ${node_port}"
}

start_node() {
    local node_id=$1
    local node_dir="${CONFIG[BASE_DIR]}/node_${node_id}"
    local log_file="${CONFIG[LOG_DIR]}/node_${node_id}.log"
    
    (
        cd "$node_dir" || return 1
        nohup bash launch.sh >> "$log_file" 2>&1 &
        local pid=$!
        echo "$pid" > "${node_dir}/.pid"
        echo "Node ${node_id} started (PID: ${pid})"
    )
}

stop_node() {
    local node_id=$1
    local node_dir="${CONFIG[BASE_DIR]}/node_${node_id}"
    
    if [[ -f "${node_dir}/.pid" ]]; then
        local pid=$(< "${node_dir}/.pid")
        if kill -TERM "$pid" 2> /dev/null; then
            rm "${node_dir}/.pid"
            echo "Node ${node_id} stopped"
        else
            echo "Failed to stop node ${node_id}"
            return 1
        fi
    else
        echo "Node ${node_id} not running"
    fi
}

# --------------------------
# Menu Handlers
# --------------------------
start_nodes() {
    show_header
    echo "Starting cluster (Batch size: ${CONFIG[BATCH_SIZE]})..."
    for ((i=0; i<CONFIG[NUM_NODES]; i++)); do
        ((i%CONFIG[BATCH_SIZE]==0)) && wait
        setup_node "$i" && start_node "$i" &
    done
    wait
    read -p "Nodes started. Press any key to continue..."
}

stop_nodes() {
    show_header
    echo "Stopping all nodes..."
    for ((i=0; i<CONFIG[NUM_NODES]; i++)); do
        ((i%CONFIG[BATCH_SIZE]==0)) && wait
        stop_node "$i" &
    done
    wait
    read -p "Nodes stopped. Press any key to continue..."
}

node_status() {
    show_header
    echo "Node Status (Ports ${CONFIG[START_PORT]}-$((CONFIG[START_PORT] + CONFIG[NUM_NODES] - 1))):"
    for ((i=0; i<CONFIG[NUM_NODES]; i++)); do
        local node_dir="${CONFIG[BASE_DIR]}/node_${i}"
        local status="\e[31mDown\e[0m"
        local port="N/A"
        local pid=""
        
        if [[ -f "${node_dir}/.pid" ]]; then
            pid=$(< "${node_dir}/.pid")
            if ps -p "$pid" > /dev/null; then
                status="\e[32mRunning\e[0m"
                port=$(grep "NODE_PORT" "${node_dir}/.env" | cut -d= -f2)
            else
                status="\e[33mZombie\e[0m"
            fi
        fi
        
        printf "Node %03d: %b  Port: %-5s PID: %-6s\n" "$i" "$status" "$port" "$pid"
    done
    read -p "Press any key to continue..."
}

view_logs() {
    show_header
    read -p "Enter node number [0-$((CONFIG[NUM_NODES]-1))]: " node_num
    if [[ $node_num -ge 0 && $node_num -lt ${CONFIG[NUM_NODES]} ]]; then
        less "${CONFIG[LOG_DIR]}/node_${node_num}.log"
    else
        read -p "Invalid node number! Press any key to continue..."
    fi
}

health_monitor() {
    show_header
    echo "Starting health monitor (Interval: ${CONFIG[CHECK_INTERVAL]}s)..."
    while true; do
        for ((i=0; i<CONFIG[NUM_NODES]; i++)); do
            local node_dir="${CONFIG[BASE_DIR]}/node_${i}"
            local port=$(grep "NODE_PORT" "${node_dir}/.env" | cut -d= -f2)
            
            if [[ -f "${node_dir}/.pid" ]]; then
                local pid=$(< "${node_dir}/.pid")
                if ! ps -p "$pid" > /dev/null; then
                    echo -e "\e[31mNode ${i} crashed! Restarting...\e[0m"
                    start_node "$i"
                elif ! curl -s --max-time ${CONFIG[API_TIMEOUT]} "http://localhost:${port}/health" > /dev/null; then
                    echo -e "\e[33mNode ${i} unresponsive! Restarting...\e[0m"
                    stop_node "$i"
                    start_node "$i"
                fi
            fi
            ((i%CONFIG[BATCH_SIZE]==0)) && wait
        done
        sleep "${CONFIG[CHECK_INTERVAL]}"
    done
}

# --------------------------
# System Functions
# --------------------------
cleanup() {
    echo "Cleaning up..."
    for ((i=0; i<CONFIG[NUM_NODES]; i++)); do
        local node_dir="${CONFIG[BASE_DIR]}/node_${i}"
        if [[ -f "${node_dir}/.pid" ]]; then
            local pid=$(< "${node_dir}/.pid")
            kill -TERM "$pid" 2> /dev/null
        fi
    done
    exit 0
}

update_nodes() {
    show_header
    echo "Updating all nodes..."
    for ((i=0; i<CONFIG[NUM_NODES]; i++)); do
        local node_dir="${CONFIG[BASE_DIR]}/node_${i}"
        (
            cd "$node_dir" || return
            git pull --quiet && echo "Node ${i} updated"
        ) &
        ((i%CONFIG[BATCH_SIZE]==0)) && wait
    done
    wait
    read -p "Update completed. Press any key to continue..."
}

# --------------------------
# Main Execution
# --------------------------
main_menu() {
    while true; do
        show_header
        show_menu
        case $choice in
            1) start_nodes ;;
            2) stop_nodes ;;
            3) stop_nodes; start_nodes ;;
            4) node_status ;;
            5) view_logs ;;
            6) health_monitor ;;
            7) update_nodes ;;
            8) cleanup ;;
            9) exit 0 ;;
            0) cleanup; exit 0 ;;
            *) echo "Invalid option"; sleep 1 ;;
        esac
    done
}

# --------------------------
# Initialization
# --------------------------
init_system() {
    check_dependencies
    mkdir -p "${CONFIG[BASE_DIR]}"
    mkdir -p "${CONFIG[LOG_DIR]}"
    trap cleanup SIGINT SIGTERM
}

# --------------------------
# Start Application
# --------------------------
init_system
main_menu