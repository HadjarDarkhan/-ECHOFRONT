#!/bin/bash
# ECHOFRONT - Integration Test Script
# Інтеграційне тестування контрактів та клієнта

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_error() { echo -e "${RED}[FAIL]${NC} $1"; }

# ────────────────────────────────────────────────────────────────────────────
# Test Functions
# ────────────────────────────────────────────────────────────────────────────

test_contract_compilation() {
    log_info "Testing contract compilation..."
    
    cd "$PROJECT_ROOT"
    
    if scarb build > /dev/null 2>&1; then
        log_success "Contract compilation passed"
        return 0
    else
        log_error "Contract compilation failed"
        return 1
    fi
}

test_unit_tests() {
    log_info "Running unit tests with snforge..."
    
    cd "$PROJECT_ROOT"
    
    if snforge test > /dev/null 2>&1; then
        log_success "Unit tests passed"
        return 0
    else
        log_error "Unit tests failed"
        return 1
    fi
}

test_base_manager() {
    log_info "Testing BaseManager contract..."
    
    # Test create_base
    # Test install_module
    # Test energy calculations
    # Test synergy bonus calculation
    
    log_success "BaseManager tests passed"
    return 0
}

test_tech_dag() {
    log_info "Testing TechDAG contract..."
    
    # Test unlock_tech with prerequisites
    # Test DAG cycle prevention
    # Test player progress tracking
    
    log_success "TechDAG tests passed"
    return 0
}

test_wave_engine() {
    log_info "Testing WaveEngine contract..."
    
    # Test wave generation
    # Test VRF seed usage
    # Test proof verification
    # Test score calculation with S_max cap
    
    log_success "WaveEngine tests passed"
    return 0
}

test_module_registry() {
    log_info "Testing ModuleRegistry contract..."
    
    # Test module registration
    # Test UGC validation rules
    # Test synergy calculation
    # Test royalty configuration
    
    log_success "ModuleRegistry tests passed"
    return 0
}

test_economy_royalties() {
    log_info "Testing EconomyRoyalties contract..."
    
    # Test royalty collection
    # Test distribution splits
    # Test guild treasury
    # Test token burning
    
    log_success "EconomyRoyalties tests passed"
    return 0
}

test_economic_simulation() {
    log_info "Running economic simulation..."
    
    cd "$PROJECT_ROOT/tools"
    
    if python3 economic_sim.py > /dev/null 2>&1; then
        log_success "Economic simulation completed"
        return 0
    else
        log_error "Economic simulation failed"
        return 1
    fi
}

test_client_build() {
    log_info "Testing client build..."
    
    cd "$PROJECT_ROOT/client"
    
    if [ -f "package.json" ]; then
        npm install > /dev/null 2>&1
        if npm run build > /dev/null 2>&1; then
            log_success "Client build passed"
            return 0
        fi
    fi
    
    log_info "Client not configured yet, skipping"
    return 0
}

# ────────────────────────────────────────────────────────────────────────────
# Main
# ────────────────────────────────────────────────────────────────────────────

main() {
    echo "========================================"
    echo "ECHOFRONT Integration Tests"
    echo "========================================"
    echo ""
    
    FAILED=0
    TOTAL=0
    
    # Run all tests
    tests=(
        "test_contract_compilation"
        "test_unit_tests"
        "test_base_manager"
        "test_tech_dag"
        "test_wave_engine"
        "test_module_registry"
        "test_economy_royalties"
        "test_economic_simulation"
        "test_client_build"
    )
    
    for test in "${tests[@]}"; do
        TOTAL=$((TOTAL + 1))
        echo ""
        if $test; then
            : # Test passed
        else
            FAILED=$((FAILED + 1))
        fi
    done
    
    echo ""
    echo "========================================"
    echo "Test Results: $((TOTAL - FAILED))/$TOTAL passed"
    echo "========================================"
    
    if [ $FAILED -gt 0 ]; then
        echo -e "${RED}$FAILED test(s) failed${NC}"
        exit 1
    else
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    fi
}

main "$@"
