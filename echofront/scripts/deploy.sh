#!/bin/bash
# ECHOFRONT - Deployment Script
# Деплой контрактів на Starknet через StarkZap/Dojo

set -e

# ────────────────────────────────────────────────────────────────────────────
# Configuration
# ────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_ROOT/tools/starkzap_config.toml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ────────────────────────────────────────────────────────────────────────────
# Helper Functions
# ────────────────────────────────────────────────────────────────────────────

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_dependencies() {
    log_info "Checking dependencies..."
    
    if ! command -v starkli &> /dev/null; then
        log_error "starkli not found. Install: curl https://get.starkli.sh | sh"
        exit 1
    fi
    
    if ! command -v scarb &> /dev/null; then
        log_error "scarb not found. Install: curl --proto '=https' --tlsv1.2 -sSf https://docs.swmansion.com/scarb/install.sh | sh"
        exit 1
    fi
    
    if ! command -v sozo &> /dev/null; then
        log_error "sozo (Dojo) not found. Install: curl -L https://install.dojoengine.org | bash"
        exit 1
    fi
    
    log_success "All dependencies found"
}

# ────────────────────────────────────────────────────────────────────────────
# Main Deployment Functions
# ────────────────────────────────────────────────────────────────────────────

deploy_local() {
    log_info "Deploying to local Katana..."
    
    cd "$PROJECT_ROOT"
    
    # Start Katana if not running
    if ! pgrep -x "katana" > /dev/null; then
        log_info "Starting Katana dev node..."
        katana --disable-fee --allowed-origins "*" &
        sleep 3
    fi
    
    # Build contracts
    log_info "Building contracts with Scarb..."
    scarb build
    
    # Deploy world (Dojo)
    log_info "Deploying Dojo world..."
    sozo build
    sozo migrate apply
    
    log_success "Local deployment complete!"
    log_info "World Address: $(cat .sozo/worlds/latest.json | jq -r '.world_address')"
}

deploy_sepolia() {
    log_info "Deploying to Starknet Sepolia..."
    
    # Check environment variables
    if [ -z "$STARKNET_ACCOUNT_ADDRESS" ]; then
        log_error "STARKNET_ACCOUNT_ADDRESS not set"
        exit 1
    fi
    
    if [ -z "$STARKNET_PRIVATE_KEY" ]; then
        log_error "STARKNET_PRIVATE_KEY not set"
        exit 1
    fi
    
    cd "$PROJECT_ROOT"
    
    # Build contracts
    log_info "Building contracts..."
    scarb build
    
    # Declare and deploy
    log_info "Running Sozo migration..."
    sozo build
    sozo migrate apply --env sepolia
    
    log_success "Sepolia deployment complete!"
}

deploy_mainnet() {
    log_warning "Deploying to Starknet Mainnet..."
    log_warning "This will cost real ETH. Continue? (y/n)"
    
    read -r response
    if [[ "$response" != "y" ]]; then
        log_info "Deployment cancelled"
        exit 0
    fi
    
    # Check environment variables
    if [ -z "$STARKNET_ACCOUNT_ADDRESS" ]; then
        log_error "STARKNET_ACCOUNT_ADDRESS not set"
        exit 1
    fi
    
    if [ -z "$STARKNET_PRIVATE_KEY" ]; then
        log_error "STARKNET_PRIVATE_KEY not set"
        exit 1
    fi
    
    cd "$PROJECT_ROOT"
    
    # Build and deploy
    log_info "Building contracts..."
    scarb build
    
    log_info "Running Sozo migration..."
    sozo build
    sozo migrate apply --env mainnet
    
    log_success "Mainnet deployment complete!"
}

# ────────────────────────────────────────────────────────────────────────────
# Post-Deployment Setup
# ────────────────────────────────────────────────────────────────────────────

setup_contracts() {
    log_info "Setting up contracts after deployment..."
    
    WORLD_ADDRESS=$(cat .sozo/worlds/latest.json | jq -r '.world_address')
    
    # Initialize BaseManager
    log_info "Initializing BaseManager..."
    # starkli invoke $BASE_MANAGER init $ADMIN_ADDRESS
    
    # Initialize TechDAG
    log_info "Initializing TechDAG..."
    # starkli invoke $TECH_DAG init $ADMIN_ADDRESS
    
    # Initialize WaveEngine
    log_info "Initializing WaveEngine..."
    # starkli invoke $WAVE_ENGINE init $ADMIN_ADDRESS 0x1234567890abcdef
    
    # Initialize ModuleRegistry
    log_info "Initializing ModuleRegistry..."
    # starkli invoke $MODULE_REGISTRY init $ADMIN_ADDRESS
    
    # Initialize ProgressTracker
    log_info "Initializing ProgressTracker..."
    # starkli invoke $PROGRESS_TRACKER init $ADMIN_ADDRESS
    
    # Initialize EconomyRoyalties
    log_info "Initializing EconomyRoyalties..."
    # starkli invoke $ECONOMY_ROYALTIES init $ADMIN_ADDRESS
    
    log_success "Contract setup complete!"
}

start_torii() {
    log_info "Starting Torii indexer..."
    
    WORLD_ADDRESS=$(cat .sozo/worlds/latest.json | jq -r '.world_address')
    
    torii \
        --world $WORLD_ADDRESS \
        --rpc http://localhost:5050 \
        --http \
        --http.addr 0.0.0.0 \
        --http.port 8080 \
        --ws \
        --ws.addr 0.0.0.0 \
        --ws.port 9090 \
        --allowed-origins "*" &
    
    log_success "Torii started on http://localhost:8080"
}

# ────────────────────────────────────────────────────────────────────────────
# Usage
# ────────────────────────────────────────────────────────────────────────────

show_usage() {
    cat << EOF
ECHOFRONT Deployment Script

Usage: $0 <command> [options]

Commands:
    local       Deploy to local Katana devnet
    sepolia     Deploy to Starknet Sepolia testnet
    mainnet     Deploy to Starknet mainnet
    setup       Run post-deployment setup
    torii       Start Torii indexer
    full-local  Full local setup (deploy + setup + torii)
    help        Show this help message

Environment Variables (for sepolia/mainnet):
    STARKNET_ACCOUNT_ADDRESS    Your Starknet account address
    STARKNET_PRIVATE_KEY        Your private key

Examples:
    $0 local
    $0 sepolia
    STARKNET_ACCOUNT_ADDRESS=0x... STARKNET_PRIVATE_KEY=0x... $0 sepolia
    $0 full-local

EOF
}

# ────────────────────────────────────────────────────────────────────────────
# Main
# ────────────────────────────────────────────────────────────────────────────

main() {
    case "${1:-help}" in
        local)
            check_dependencies
            deploy_local
            ;;
        sepolia)
            check_dependencies
            deploy_sepolia
            ;;
        mainnet)
            check_dependencies
            deploy_mainnet
            ;;
        setup)
            setup_contracts
            ;;
        torii)
            start_torii
            ;;
        full-local)
            check_dependencies
            deploy_local
            setup_contracts
            start_torii
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            log_error "Unknown command: $1"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
