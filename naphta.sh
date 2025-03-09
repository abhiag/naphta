#!/usr/bin/env bash

# NapthaAI Cluster Manager v4.2
# Complete integrated solution with multi-node support and original setup workflow

# --------------------------
# Configuration
# --------------------------
declare -A CONFIG=(
    [MAX_NODES]=4                # Maximum allowed nodes
    [START_PORT]=8070            # Base port number
    [BASE_DIR]="${PWD}/nodes"    # Node directory
    [LOG_DIR]="${PWD}/logs"      # Log directory
    [TEMPLATE_ENV]="${PWD}/.naptha_cluster_env"
    [REPO_URL]="https://github.com/NapthaAI/naptha-node.git"
    [BATCH_SIZE]=2               # Processing batch size
    [CHECK_INTERVAL]=5           # Health check interval
    [API_TIMEOUT]=2              # API timeout seconds
)

# --------------------------
# UI Functions
# --------------------------
show_header() {
    clear
    echo "========================================"
    echo "    NapthaAI Cluster Manager v4.2"
    echo "========================================"
    echo " Active Nodes: $(ls ${CONFIG[BASE_DIR]} 2>/dev/null | wc -l)/${CONFIG[MAX_NODES]}"
    echo "----------------------------------------"
}

show_menu() {
    echo "1. Install New Nodes"
    echo "2. Start All Nodes"
    echo "3. Stop All Nodes"
    echo "4. Restart All Nodes"
    echo "5. Node Status Dashboard"
    echo "6. View Node Logs"
    echo "7. Cluster Health Monitor"
    echo "8. Update Node Software"
    echo "9. System Cleanup"
    echo "0. Exit"
    echo "----------------------------------------"
    read -p "Enter choice [0-9]: " choice
}

# --------------------------
# Core Functions
# --------------------------
init_system() {
    check_dependencies
    mkdir -p "${CONFIG[BASE_DIR]}"
    mkdir -p "${CONFIG[LOG_DIR]}"
    trap 'cleanup; exit 0' SIGINT SIGTERM
}

check_dependencies() {
    local deps=("git" "lsof" "curl" "jq")
    local install_cmd=""
    
    declare -A pkg_mgr=(
        ["apt-get"]="sudo apt-get install -y"
        ["yum"]="sudo yum install -y"
        ["dnf"]="sudo dnf install -y"
        ["pacman"]="sudo pacman -S --noconfirm"
        ["brew"]="brew install"
    )

    for mgr in "${!pkg_mgr[@]}"; do
        command -v "$mgr" &>/dev/null && {
            install_cmd="${pkg_mgr[$mgr]}"
            break
        }
    done

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            echo "Installing $dep..."
            $install_cmd "$dep" || {
                echo "Failed to install $dep. Install manually."
                exit 1
            }
        fi
    done
}

setup_environment() {
    if [ ! -f "${CONFIG[TEMPLATE_ENV]}" ]; then
        echo "Initial Cluster Setup"
        echo "---------------------"
        
        # Clone repo to get example env
        temp_dir=$(mktemp -d)
        git clone -q "${CONFIG[REPO_URL]}" "$temp_dir"
        cp "$temp_dir/.env.example" "${CONFIG[TEMPLATE_ENV]}"
        rm -rf "$temp_dir"

        # Get user credentials
        read -p "Enter PRIVATE_KEY: " PRIVATE_KEY
        read -p "Enter HUB_USERNAME: " HUB_USERNAME
        read -sp "Enter HUB_PASSWORD: " HUB_PASSWORD
        echo
        
        # Update template
        sed -i "s/^PRIVATE_KEY=.*/PRIVATE_KEY=$PRIVATE_KEY/" "${CONFIG[TEMPLATE_ENV]}"
        sed -i "s/^HUB_USERNAME=.*/HUB_USERNAME=$HUB_USERNAME/" "${CONFIG[TEMPLATE_ENV]}"
        sed -i "s/^HUB_PASSWORD=.*/HUB_PASSWORD=$HUB_PASSWORD/" "${CONFIG[TEMPLATE_ENV]}"

        # Optional API keys
        read -p "Set OPENAI_API_KEY? (y/n): " set_openai
        if [[ "$set_openai" == "y" || "$set_openai" == "Y" ]]; then
            read -p "Enter OPENAI_API_KEY: " OPENAI_API_KEY
            echo "OPENAI_API_KEY=$OPENAI_API_KEY" >> "${CONFIG[TEMPLATE_ENV]}"
        fi

        read -p "Set STABILITY_API_KEY? (y/n): " set_stability
        if [[ "$set_stability" == "y" || "$set_stability" == "Y" ]]; then
            read -p "Enter STABILITY_API_KEY: " STABILITY_API_KEY
            echo "STABILITY_API_KEY=$STABILITY_API_KEY" >> "${CONFIG[TEMPLATE_ENV]}"
        fi

        echo "Environment template created successfully."
    fi
}

# --------------------------
# Node Lifecycle Management
# --------------------------
install_nodes() {
    show_header
    setup_environment  # Ensure environment template exists
    
    local existing=$(ls ${CONFIG[BASE_DIR]} 2>/dev/null | wc -l)
    local available=$((CONFIG[MAX_NODES] - existing))
    
    [ $available -le 0 ] && {
        echo "Maximum node capacity reached (${CONFIG[MAX_NODES]})"
        read -p "Press any key to continue..."
        return
    }

    read -p "Nodes to install (1-$available): " num_nodes
    [[ ! "$num_nodes" =~ ^[1-9][0-9]*$ ]] || [ $num_nodes -gt $available ] && {
        echo "Invalid input! Using maximum available: $available"
        num_nodes=$available
    }

    for ((i=0; i<num_nodes; i++)); do
        node_id=$(get_next_node_id)
        setup_node "$node_id" && start_node "$node_id"
    done
    
    echo "---------------------------------------------------"
    echo "All nodes installed! Access nodes using these ports:"
    for ((i=0; i<num_nodes; i++)); do
        port=$((CONFIG[START_PORT] + node_id - num_nodes + 1 + i))
        echo "- Node $((node_id - num_nodes + 1 + i)): http://localhost:$port"
    done
    read -p "Press any key to continue..."
}

setup_node() {
    local node_id=$1
    local node_dir="${CONFIG[BASE_DIR]}/node_${node_id}"
    local node_port=$((CONFIG[START_PORT] + node_id))

    mkdir -p "$node_dir"
    git clone -q "${CONFIG[REPO_URL]}" "$node_dir" || return 1
    
    # Configure environment
    cp "${CONFIG[TEMPLATE_ENV]}" "${node_dir}/.env"
    echo "NODE_PORT=$node_port" >> "${node_dir}/.env"
    
    echo "Node ${node_id} configured on port $node_port"
}

start_node() {
    local node_id=$1
    local node_dir="${CONFIG[BASE_DIR]}/node_${node_id}"
    local log_file="${CONFIG[LOG_DIR]}/node_${node_id}.log"
    
    mkdir -p "${CONFIG[LOG_DIR]}"
    touch "$log_file"

    (
        cd "$node_dir" || return 1
        nohup bash launch.sh >> "$log_file" 2>&1 &
        echo $! > "${node_dir}/.pid"
        echo "Node $node_id started (PID: $(< "${node_dir}/.pid"))"
    )
}

stop_node() {
    local node_id=$1
    local node_dir="${CONFIG[BASE_DIR]}/node_${node_id}"
    
    [ -f "${node_dir}/.pid" ] && {
        kill -TERM $(< "${node_dir}/.pid") 2>/dev/null && rm "${node_dir}/.pid"
        echo "Node $node_id stopped"
    }
}

# --------------------------
# Monitoring & Maintenance
# --------------------------
node_status() {
    show_header
    printf "%-8s %-8s %-8s %-15s\n" "NodeID" "Status" "PID" "Port"
    echo "----------------------------------------"
    
    for node_dir in "${CONFIG[BASE_DIR]}"/node_*; do
        [ -d "$node_dir" ] || continue
        local node_id=${node_dir##*_}
        local pid_file="${node_dir}/.pid"
        local status="Down"
        local pid="N/A"
        local port=$(grep -oP 'NODE_PORT=\K\d+' "${node_dir}/.env")

        [ -f "$pid_file" ] && {
            pid=$(< "$pid_file")
            ps -p "$pid" &>/dev/null && status="Running" || status="Zombie"
        }

        printf "%-8s %-8s %-8s %-15s\n" "$node_id" "$status" "$pid" "$port"
    done
    read -p "Press any key to continue..."
}

health_monitor() {
    while true; do
        clear
        echo "Cluster Health Monitor - Ctrl+C to exit"
        echo "----------------------------------------"
        
        for node_dir in "${CONFIG[BASE_DIR]}"/node_*; do
            [ -d "$node_dir" ] || continue
            local node_id=${node_dir##*_}
            local port=$(grep -oP 'NODE_PORT=\K\d+' "${node_dir}/.env")
            local pid_file="${node_dir}/.pid"
            
            [ -f "$pid_file" ] && {
                pid=$(< "$pid_file")
                if ! ps -p "$pid" &>/dev/null; then
                    echo "Node $node_id crashed! Restarting..."
                    start_node "$node_id"
                elif ! curl -s -m ${CONFIG[API_TIMEOUT]} "http://localhost:$port/health" &>/dev/null; then
                    echo "Node $node_id unresponsive! Recycling..."
                    stop_node "$node_id"
                    start_node "$node_id"
                fi
            }
        done
        sleep ${CONFIG[CHECK_INTERVAL]}
    done
}

# --------------------------
# Utility Functions
# --------------------------
get_next_node_id() {
    local max_id=-1
    for node_dir in "${CONFIG[BASE_DIR]}"/node_*; do
        [ -d "$node_dir" ] || continue
        local current_id=${node_dir##*_}
        [ $current_id -gt $max_id ] && max_id=$current_id
    done
    echo $((max_id + 1))
}

cleanup() {
    echo "Performing system cleanup..."
    for node_dir in "${CONFIG[BASE_DIR]}"/node_*; do
        [ -d "$node_dir" ] || continue
        local node_id=${node_dir##*_}
        stop_node "$node_id"
    done
    rm -rf "${CONFIG[BASE_DIR]}/*.pid"
    echo "Cleanup complete. Goodbye!"
}

# --------------------------
# Main Execution
# --------------------------
main() {
    init_system
    while true; do
        show_header
        show_menu
        case $choice in
            1) install_nodes ;;
            2) for node in "${CONFIG[BASE_DIR]}"/node_*; do [ -d "$node" ] && start_node "${node##*_}"; done ;;
            3) for node in "${CONFIG[BASE_DIR]}"/node_*; do [ -d "$node" ] && stop_node "${node##*_}"; done ;;
            4) for node in "${CONFIG[BASE_DIR]}"/node_*; do [ -d "$node" ] && (stop_node "${node##*_}"; start_node "${node##*_}"); done ;;
            5) node_status ;;
            6) read -p "Enter Node ID: " id; [ -f "${CONFIG[LOG_DIR]}/node_${id}.log" ] && less "${CONFIG[LOG_DIR]}/node_${id}.log" || echo "Invalid node ID"; read -p "Press any key...";;
            7) health_monitor ;;
            8) for node in "${CONFIG[BASE_DIR]}"/node_*; do (cd "$node" && git pull); done; read -p "Update completed. Press any key...";;
            9) cleanup ;;
            0) cleanup; exit 0 ;;
            *) echo "Invalid option"; sleep 1 ;;
        esac
    done
}

# Start application
main
