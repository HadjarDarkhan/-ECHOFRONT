#[cfg(test)]
mod tests;

use starknet::ContractAddress;

// ============================================================================
// ECHOFRONT - Module Registry Contract
// Реєстр модулів, синергії, UGC-валідація
// ============================================================================

// ────────────────────────────────────────────────────────────────────────────
// ECS Components
// ────────────────────────────────────────────────────────────────────────────

#[derive(Copy, Drop, serde::Serde, PartialEq)]
struct ModuleDefinition {
    module_id: u32,
    name: felt252,
    creator: ContractAddress,
    module_type: u32, // 1=defense, 2=energy, 3=offense, 4=support
    base_stats: u128, // Fixed-point stats
    energy_cost: u128,
    rarity: u32,
    is_verified: bool,
    royalty_percent: u32, // Basis points (100 = 1%)
    created_at: u64,
}

#[derive(Copy, Drop, serde::Serde, PartialEq)]
struct SynergyRule {
    module_a: u32,
    module_b: u32,
    synergy_bonus: u128, // Fixed-point: 1.0 = 10000
    is_active: bool,
}

#[derive(Copy, Drop, serde::Serde, PartialEq)]
struct UGCValidationResult {
    module_id: u32,
    is_valid: bool,
    validation_score: u128,
    issues: felt252,
    validated_at: u64,
}

// ────────────────────────────────────────────────────────────────────────────
// Events
// ────────────────────────────────────────────────────────────────────────────

#[derive(Drop, starknet::Event)]
enum ModuleEvent {
    #[flat]
    ModuleRegistered: ModuleRegistered,
    #[flat]
    SynergyCreated: SynergyCreated,
    #[flat]
    ModuleValidated: ModuleValidated,
    #[flat]
    RoyaltyPaid: RoyaltyPaid,
}

#[derive(Drop, starknet::Event)]
struct ModuleRegistered {
    module_id: u32,
    name: felt252,
    creator: ContractAddress,
    module_type: u32,
    timestamp: u64,
}

#[derive(Drop, starknet::Event)]
struct SynergyCreated {
    module_a: u32,
    module_b: u32,
    synergy_bonus: u128,
}

#[derive(Drop, starknet::Event)]
struct ModuleValidated {
    module_id: u32,
    is_valid: bool,
    validation_score: u128,
}

#[derive(Drop, starknet::Event)]
struct RoyaltyPaid {
    module_id: u32,
    creator: ContractAddress,
    amount: u128,
    recipient: ContractAddress,
}

// ────────────────────────────────────────────────────────────────────────────
// Storage
// ────────────────────────────────────────────────────────────────────────────

#[starknet::contract]
mod ModuleRegistry {
    use starknet::ContractAddress;
    use core::option::OptionTrait;
    use super::{ModuleDefinition, SynergyRule, UGCValidationResult, ModuleEvent};

    const MAX_MODULES: u32 = 10000;
    const MAX_SYNERGIES: u32 = 5000;
    const MAX_ROYALTY_PERCENT: u32 = 1000; // 10% max
    const SYNERGY_SCALE: u128 = 10000;

    #[storage]
    struct Storage {
        #[map]
        modules: u32 => ModuleDefinition,
        #[map]
        synergies: (u32, u32) => SynergyRule,
        #[map]
        validations: u32 => UGCValidationResult,
        #[map]
        creator_modules: (ContractAddress, u32) => Array<u32>,
        module_counter: u32,
        synergy_counter: u32,
        admin: ContractAddress,
    }

    #[init]
    fn init(ref self: ContractState, admin: ContractAddress) {
        self.admin.write(admin);
        self.module_counter.write(0);
        self.synergy_counter.write(0);

        // Initialize base modules
        self._init_base_modules();
    }

    // ────────────────────────────────────────────────────────────────────────
    // Internal Functions
    // ────────────────────────────────────────────────────────────────────────

    fn _init_base_modules(ref self: ContractState) {
        let base_modules = [
            (1, 'Basic Turret', 1, 100, 50),
            (2, 'Energy Cell', 2, 200, 0),
            (3, 'Shield Generator', 1, 150, 75),
            (4, 'Damage Amplifier', 3, 180, 60),
        ];

        let mut i = 0;
        while i < base_modules.len() {
            let (id, name, mtype, cost, energy) = base_modules[i];
            let module = ModuleDefinition {
                module_id: id,
                name,
                creator: 0_u16.into(), // System modules
                module_type: mtype,
                base_stats: 1000, // Base stats in fixed-point
                energy_cost: energy,
                rarity: 1,
                is_verified: true,
                royalty_percent: 0,
                created_at: 0,
            };
            self.modules.write(id, module);
            i += 1;
        }
        self.module_counter.write(4);
    }

    fn _validate_module_rules(
        self: @ContractState,
        name: felt252,
        module_type: u32,
        base_stats: u128,
        energy_cost: u128,
        royalty_percent: u32,
    ) -> (bool, felt252) {
        // Validate module type
        if module_type == 0 || module_type > 4 {
            return (false, 'Invalid module type');
        }

        // Validate royalty percent
        if royalty_percent > MAX_ROYALTY_PERCENT {
            return (false, 'Royalty exceeds maximum');
        }

        // Validate energy cost vs stats ratio (prevent OP modules)
        if energy_cost > 0 && base_stats / energy_cost > 50 {
            return (false, 'Stats/energy ratio too high');
        }

        // Validate name is not empty
        if name == 0 {
            return (false, 'Empty name');
        }

        (true, 'Valid')
    }

    fn _calculate_synergy(
        self: @ContractState,
        module_a: u32,
        module_b: u32,
    ) -> u128 {
        // Check for explicit synergy rule
        let rule = self.synergies.read((module_a, module_b));
        if rule.is_active && rule.synergy_bonus > 0 {
            return rule.synergy_bonus;
        }

        // Check reverse
        let reverse_rule = self.synergies.read((module_b, module_a));
        if reverse_rule.is_active && reverse_rule.synergy_bonus > 0 {
            return reverse_rule.synergy_bonus;
        }

        // Default: no synergy
        SYNERGY_SCALE // 1.0×
    }

    // ────────────────────────────────────────────────────────────────────────
    // External Functions
    // ────────────────────────────────────────────────────────────────────────

    #[external(v0)]
    fn register_module(
        ref self: ContractState,
        name: felt252,
        module_type: u32,
        base_stats: u128,
        energy_cost: u128,
        royalty_percent: u32,
    ) -> u32 {
        let creator = starknet::get_caller_address();
        let current_block = starknet::get_block_number();

        // Validate module rules
        let (is_valid, issues) = self._validate_module_rules(
            name, module_type, base_stats, energy_cost, royalty_percent
        );
        assert(is_valid, issues);

        let module_count = self.module_counter.read();
        assert(module_count < MAX_MODULES, 'Max modules reached');

        let new_id = module_count + 1;
        let module = ModuleDefinition {
            module_id: new_id,
            name,
            creator,
            module_type,
            base_stats,
            energy_cost,
            rarity: 1, // UGC starts as common
            is_verified: false, // Pending validation
            royalty_percent,
            created_at: current_block,
        };

        self.modules.write(new_id, module);
        self.module_counter.write(new_id);

        // Track creator's modules
        let mut creator_mods = self.creator_modules.read((creator, module_type));
        creator_mods.append(new_id);
        self.creator_modules.write((creator, module_type), creator_mods);

        self.emit(ModuleEvent::ModuleRegistered(ModuleRegistered {
            module_id: new_id,
            name,
            creator,
            module_type,
            timestamp: current_block,
        }));

        new_id
    }

    #[external(v0)]
    fn validate_module(
        ref self: ContractState,
        module_id: u32,
        validation_score: u128,
    ) {
        let admin = self.admin.read();
        assert(starknet::get_caller_address() == admin, 'Not admin');

        let mut module = self.modules.read(module_id);
        assert(module.module_id != 0, 'Module does not exist');
        assert(!module.is_verified, 'Module already verified');

        let current_block = starknet::get_block_number();
        let min_score: u128 = 8000; // 80% validation threshold

        let is_valid = validation_score >= min_score;

        // Create validation result
        let validation = UGCValidationResult {
            module_id,
            is_valid,
            validation_score,
            issues: if is_valid { 'Approved' } else { 'Rejected' },
            validated_at: current_block,
        };
        self.validations.write(module_id, validation);

        // Update module if valid
        if is_valid {
            module.is_verified = true;
            self.modules.write(module_id, module);
        }

        self.emit(ModuleEvent::ModuleValidated(ModuleValidated {
            module_id,
            is_valid,
            validation_score,
        }));
    }

    #[external(v0)]
    fn create_synergy(
        ref self: ContractState,
        module_a: u32,
        module_b: u32,
        synergy_bonus: u128,
    ) {
        let admin = self.admin.read();
        assert(starknet::get_caller_address() == admin, 'Not admin');

        let module_a_def = self.modules.read(module_a);
        let module_b_def = self.modules.read(module_b);
        assert(module_a_def.module_id != 0, 'Module A does not exist');
        assert(module_b_def.module_id != 0, 'Module B does not exist');

        // Cap synergy bonus at S_max = 2.5×
        let max_synergy = SYNERGY_SCALE * 25 / 10;
        assert(synergy_bonus <= max_synergy, 'Synergy exceeds maximum');

        let synergy_count = self.synergy_counter.read();
        assert(synergy_count < MAX_SYNERGIES, 'Max synergies reached');

        let rule = SynergyRule {
            module_a,
            module_b,
            synergy_bonus,
            is_active: true,
        };
        self.synergies.write((module_a, module_b), rule);
        self.synergy_counter.write(synergy_count + 1);

        self.emit(ModuleEvent::SynergyCreated(SynergyCreated {
            module_a,
            module_b,
            synergy_bonus,
        }));
    }

    #[external(v0)]
    fn pay_royalty(
        ref self: ContractState,
        module_id: u32,
        amount: u128,
        recipient: ContractAddress,
    ) {
        let module = self.modules.read(module_id);
        assert(module.module_id != 0, 'Module does not exist');
        assert(module.is_verified, 'Module not verified');
        assert(module.royalty_percent > 0, 'No royalty set');

        // In production, this would transfer tokens
        // For now, just emit event
        self.emit(ModuleEvent::RoyaltyPaid(RoyaltyPaid {
            module_id,
            creator: module.creator,
            amount,
            recipient,
        }));
    }

    // ────────────────────────────────────────────────────────────────────────
    // View Functions
    // ────────────────────────────────────────────────────────────────────────

    #[external(v0)]
    fn get_module(self: @ContractState, module_id: u32) -> ModuleDefinition {
        self.modules.read(module_id)
    }

    #[external(v0)]
    fn get_synergy(
        self: @ContractState,
        module_a: u32,
        module_b: u32,
    ) -> SynergyRule {
        self.synergies.read((module_a, module_b))
    }

    #[external(v0)]
    fn get_validation(self: @ContractState, module_id: u32) -> UGCValidationResult {
        self.validations.read(module_id)
    }

    #[external(v0)]
    fn get_creator_modules(
        self: @ContractState,
        creator: ContractAddress,
        module_type: u32,
    ) -> Array<u32> {
        self.creator_modules.read((creator, module_type))
    }

    #[external(v0)]
    fn calculate_total_synergy(
        self: @ContractState,
        modules: Array<u32>,
    ) -> u128 {
        let mut total_synergy = SYNERGY_SCALE; // Start at 1.0×
        let mut i = 0;
        while i < modules.len() {
            let mut j = i + 1;
            while j < modules.len() {
                let mod_a = *modules.at(i);
                let mod_b = *modules.at(j);
                let synergy = self._calculate_synergy(mod_a, mod_b);
                if synergy > SYNERGY_SCALE {
                    total_synergy += synergy - SYNERGY_SCALE;
                }
                j += 1;
            }
            i += 1;
        }

        // Cap at S_max = 2.5×
        let max_synergy = SYNERGY_SCALE * 25 / 10;
        if total_synergy > max_synergy {
            return max_synergy;
        }
        total_synergy
    }

    #[external(v0)]
    fn is_module_valid(self: @ContractState, module_id: u32) -> bool {
        let module = self.modules.read(module_id);
        module.is_verified
    }
}
