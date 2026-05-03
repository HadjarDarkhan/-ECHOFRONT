#!/bin/bash
# ECHOFRONT - UGC Validator Script
# Автоматична валідація UGC-модулів

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[VALID]${NC} $1"; }
log_error() { echo -e "${RED}[INVALID]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# ────────────────────────────────────────────────────────────────────────────
# Validation Rules (matching module_registry.cairo)
# ────────────────────────────────────────────────────────────────────────────

MAX_ENERGY_COST=500
MAX_STATS_RATIO=50  # base_stats / energy_cost
MAX_ROYALTY_PERCENT=1000  # 10% in basis points
MIN_NAME_LENGTH=1
MAX_NAME_LENGTH=32

# ────────────────────────────────────────────────────────────────────────────
# Validation Functions
# ────────────────────────────────────────────────────────────────────────────

validate_module_type() {
    local module_type=$1
    
    if [[ $module_type -ge 1 && $module_type -le 4 ]]; then
        return 0
    else
        return 1
    fi
}

validate_energy_cost() {
    local energy_cost=$1
    
    if [[ $energy_cost -ge 0 && $energy_cost -le $MAX_ENERGY_COST ]]; then
        return 0
    else
        return 1
    fi
}

validate_stats_ratio() {
    local base_stats=$1
    local energy_cost=$2
    
    if [[ $energy_cost -eq 0 ]]; then
        # Free modules have different rules
        if [[ $base_stats -le 500 ]]; then
            return 0
        else
            return 1
        fi
    fi
    
    local ratio=$((base_stats / energy_cost))
    
    if [[ $ratio -le $MAX_STATS_RATIO ]]; then
        return 0
    else
        return 1
    fi
}

validate_royalty() {
    local royalty_percent=$1
    
    if [[ $royalty_percent -ge 0 && $royalty_percent -le $MAX_ROYALTY_PERCENT ]]; then
        return 0
    else
        return 1
    fi
}

validate_name() {
    local name=$1
    local length=${#name}
    
    if [[ $length -ge $MIN_NAME_LENGTH && $length -le $MAX_NAME_LENGTH ]]; then
        return 0
    else
        return 1
    fi
}

simulate_difficulty_impact() {
    local module_type=$1
    local base_stats=$2
    local energy_cost=$3
    
    # Simulate module impact on wave difficulty
    local impact_score=0
    
    case $module_type in
        1) # Defense
            impact_score=$((base_stats / 100))
            ;;
        2) # Energy
            impact_score=$((energy_cost / 50))
            ;;
        3) # Offense
            impact_score=$((base_stats / 80))
            ;;
        4) # Support
            impact_score=$((base_stats / 120))
            ;;
    esac
    
    # Should not increase difficulty by more than 20%
    if [[ $impact_score -le 20 ]]; then
        return 0
    else
        return 1
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# Main Validation
# ────────────────────────────────────────────────────────────────────────────

validate_module() {
    local name=$1
    local module_type=$2
    local base_stats=$3
    local energy_cost=$4
    local royalty_percent=$5
    
    local issues=()
    local warnings=()
    
    log_info "Validating module: '$name'"
    log_info "  Type: $module_type, Stats: $base_stats, Energy: $energy_cost, Royalty: $royalty_percent%"
    
    # Validate name
    if ! validate_name "$name"; then
        issues+=("Invalid name length (must be $MIN_NAME_LENGTH-$MAX_NAME_LENGTH chars)")
    fi
    
    # Validate module type
    if ! validate_module_type $module_type; then
        issues+=("Invalid module type (must be 1-4)")
    fi
    
    # Validate energy cost
    if ! validate_energy_cost $energy_cost; then
        issues+=("Energy cost exceeds maximum ($MAX_ENERGY_COST)")
    fi
    
    # Validate stats ratio
    if ! validate_stats_ratio $base_stats $energy_cost; then
        issues+=("Stats/energy ratio too high (max $MAX_STATS_RATIO)")
    fi
    
    # Validate royalty
    if ! validate_royalty $royalty_percent; then
        issues+=("Royalty exceeds maximum (${MAX_ROYALTY_PERCENT} basis points = $(($MAX_ROYALTY_PERCENT / 100))%)")
    fi
    
    # Simulate difficulty impact
    if ! simulate_difficulty_impact $module_type $base_stats $energy_cost; then
        warnings+=("Module may significantly impact game difficulty")
    fi
    
    # Report results
    if [[ ${#issues[@]} -gt 0 ]]; then
        log_error "Module '$name' is INVALID"
        for issue in "${issues[@]}"; do
            echo "  ❌ $issue"
        done
        return 1
    else
        log_success "Module '$name' is VALID"
        
        if [[ ${#warnings[@]} -gt 0 ]]; then
            for warning in "${warnings[@]}"; do
                log_warning "$warning"
            done
        fi
        
        return 0
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# Batch Validation from JSON
# ────────────────────────────────────────────────────────────────────────────

validate_batch() {
    local json_file=$1
    
    if [ ! -f "$json_file" ]; then
        log_error "File not found: $json_file"
        exit 1
    fi
    
    log_info "Batch validating modules from: $json_file"
    
    local total=0
    local valid=0
    local invalid=0
    
    # Parse JSON and validate each module
    # Requires jq
    local count=$(jq '.modules | length' "$json_file")
    
    for ((i=0; i<count; i++)); do
        total=$((total + 1))
        
        local name=$(jq -r ".modules[$i].name" "$json_file")
        local module_type=$(jq -r ".modules[$i].type" "$json_file")
        local base_stats=$(jq -r ".modules[$i].base_stats" "$json_file")
        local energy_cost=$(jq -r ".modules[$i].energy_cost" "$json_file")
        local royalty_percent=$(jq -r ".modules[$i].royalty_percent" "$json_file")
        
        if validate_module "$name" $module_type $base_stats $energy_cost $royalty_percent; then
            valid=$((valid + 1))
        else
            invalid=$((invalid + 1))
        fi
        
        echo ""
    done
    
    echo "========================================"
    echo "Batch Validation Results"
    echo "========================================"
    echo "Total: $total | Valid: $valid | Invalid: $invalid"
    
    if [[ $invalid -gt 0 ]]; then
        exit 1
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# Usage
# ────────────────────────────────────────────────────────────────────────────

show_usage() {
    cat << EOF
ECHOFRONT UGC Validator

Usage: $0 <command> [options]

Commands:
    validate <name> <type> <stats> <energy> <royalty>
        Validate a single module
        
    batch <json_file>
        Validate multiple modules from JSON file
        
    help
        Show this help message

Module Types:
    1 = Defense
    2 = Energy
    3 = Offense
    4 = Support

Examples:
    $0 validate "Laser Turret" 1 500 75 500
    $0 batch modules_to_validate.json

JSON Format for batch validation:
    {
        "modules": [
            {
                "name": "Laser Turret",
                "type": 1,
                "base_stats": 500,
                "energy_cost": 75,
                "royalty_percent": 500
            }
        ]
    }

EOF
}

# ────────────────────────────────────────────────────────────────────────────
# Main
# ────────────────────────────────────────────────────────────────────────────

main() {
    case "${1:-help}" in
        validate)
            if [[ $# -lt 6 ]]; then
                log_error "Missing arguments"
                show_usage
                exit 1
            fi
            validate_module "$2" "$3" "$4" "$5" "$6"
            ;;
        batch)
            if [[ $# -lt 2 ]]; then
                log_error "Missing JSON file argument"
                show_usage
                exit 1
            fi
            validate_batch "$2"
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
