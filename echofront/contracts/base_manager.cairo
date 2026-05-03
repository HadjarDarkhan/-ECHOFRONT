#[cfg(test)]
mod tests;

use starknet::ContractAddress;
use core::option::OptionTrait;

// ============================================================================
// ECHOFRONT - Base Manager Contract
// Управління конфігурацією бази, енергомережею та слотами модулів
// ============================================================================

// ────────────────────────────────────────────────────────────────────────────
// ECS Components (Dojo Engine)
// ────────────────────────────────────────────────────────────────────────────

#[derive(Copy, Drop, serde::Serde)]
struct BaseConfig {
    owner: ContractAddress,
    base_level: u32,
    max_slots: u32,
    energy_capacity: u128,
    energy_regeneration: u128,
    shield_integrity: u128,
    last_update_block: u64,
}

#[derive(Copy, Drop, serde::Serde)]
struct ModuleSlot {
    slot_id: u32,
    module_id: u32,
    installed_at: u64,
    energy_drain: u128,
    is_active: bool,
}

#[derive(Copy, Drop, serde::Serde)]
struct EnergyGrid {
    total_generation: u128,
    total_consumption: u128,
    surplus: u128,
    efficiency_multiplier: u128, // Fixed-point: 1.0 = 10000
}

// ────────────────────────────────────────────────────────────────────────────
// Events
// ────────────────────────────────────────────────────────────────────────────

#[derive(Drop, starknet::Event)]
enum BaseEvent {
    #[flat]
    BaseCreated: BaseCreated,
    #[flat]
    ModuleInstalled: ModuleInstalled,
    #[flat]
    ModuleRemoved: ModuleRemoved,
    #[flat]
    EnergyUpdated: EnergyUpdated,
    #[flat]
    BaseUpgraded: BaseUpgraded,
}

#[derive(Drop, starknet::Event)]
struct BaseCreated {
    base_id: u32,
    owner: ContractAddress,
    timestamp: u64,
}

#[derive(Drop, starknet::Event)]
struct ModuleInstalled {
    base_id: u32,
    slot_id: u32,
    module_id: u32,
    energy_drain: u128,
}

#[derive(Drop, starknet::Event)]
struct ModuleRemoved {
    base_id: u32,
    slot_id: u32,
}

#[derive(Drop, starknet::Event)]
struct EnergyUpdated {
    base_id: u32,
    generation: u128,
    consumption: u128,
    surplus: u128,
}

#[derive(Drop, starknet::Event)]
struct BaseUpgraded {
    base_id: u32,
    old_level: u32,
    new_level: u32,
}

// ────────────────────────────────────────────────────────────────────────────
// Storage
// ────────────────────────────────────────────────────────────────────────────

#[starknet::contract]
mod BaseManager {
    use starknet::ContractAddress;
    use core::option::OptionTrait;
    use super::{BaseConfig, ModuleSlot, EnergyGrid, BaseEvent};

    // Constants
    const MAX_BASES: u32 = 10000;
    const SLOTS_PER_BASE: u32 = 8;
    const ENERGY_SCALE: u128 = 10000; // Fixed-point precision
    const BASE_ENERGY_CAP: u128 = 1000;
    const BASE_REGEN_RATE: u128 = 10;

    #[storage]
    struct Storage {
        #[map]
        bases: ContractAddress => BaseConfig,
        #[map]
        module_slots: (ContractAddress, u32) => ModuleSlot,
        #[map]
        energy_grids: ContractAddress => EnergyGrid,
        base_counter: u32,
        admin: ContractAddress,
    }

    #[init]
    fn init(ref self: ContractState, admin: ContractAddress) {
        self.admin.write(admin);
        self.base_counter.write(0);
    }

    // ────────────────────────────────────────────────────────────────────────
    // External Functions
    // ────────────────────────────────────────────────────────────────────────

    #[external(v0)]
    fn create_base(ref self: ContractState, owner: ContractAddress) -> u32 {
        let base_count = self.base_counter.read();
        assert(base_count < MAX_BASES, 'Max bases reached');

        let base_id = base_count + 1;
        let current_block = starknet::get_block_number();

        let config = BaseConfig {
            owner,
            base_level: 1,
            max_slots: SLOTS_PER_BASE,
            energy_capacity: BASE_ENERGY_CAP,
            energy_regeneration: BASE_REGEN_RATE,
            shield_integrity: 100,
            last_update_block: current_block,
        };

        self.bases.write(owner, config);

        // Initialize energy grid
        let grid = EnergyGrid {
            total_generation: BASE_REGEN_RATE,
            total_consumption: 0,
            surplus: BASE_REGEN_RATE,
            efficiency_multiplier: ENERGY_SCALE,
        };
        self.energy_grids.write(owner, grid);

        // Initialize empty slots
        let mut slot_id: u32 = 0;
        while slot_id < SLOTS_PER_BASE {
            let slot = ModuleSlot {
                slot_id,
                module_id: 0,
                installed_at: 0,
                energy_drain: 0,
                is_active: false,
            };
            self.module_slots.write((owner, slot_id), slot);
            slot_id += 1;
        }

        self.base_counter.write(base_id);

        self.emit(BaseEvent::BaseCreated(BaseCreated {
            base_id,
            owner,
            timestamp: current_block,
        }));

        base_id
    }

    #[external(v0)]
    fn install_module(
        ref self: ContractState,
        owner: ContractAddress,
        slot_id: u32,
        module_id: u32,
        energy_drain: u128,
    ) {
        let config = self.bases.read(owner);
        assert(config.owner == owner, 'Not base owner');
        assert(slot_id < config.max_slots, 'Invalid slot');

        let mut slot = self.module_slots.read((owner, slot_id));
        assert(!slot.is_active, 'Slot already occupied');

        // Check energy capacity
        let grid = self.energy_grids.read(owner);
        assert(
            grid.total_consumption + energy_drain <= grid.total_generation,
            'Insufficient energy'
        );

        let current_block = starknet::get_block_number();
        slot.module_id = module_id;
        slot.installed_at = current_block;
        slot.energy_drain = energy_drain;
        slot.is_active = true;

        self.module_slots.write((owner, slot_id), slot);

        // Update energy grid
        let new_consumption = grid.total_consumption + energy_drain;
        let new_surplus = grid.total_generation - new_consumption;
        let updated_grid = EnergyGrid {
            total_generation: grid.total_generation,
            total_consumption: new_consumption,
            surplus: new_surplus,
            efficiency_multiplier: grid.efficiency_multiplier,
        };
        self.energy_grids.write(owner, updated_grid);

        self.emit(BaseEvent::ModuleInstalled(ModuleInstalled {
            base_id: 0, // Could be derived from owner
            slot_id,
            module_id,
            energy_drain,
        }));
    }

    #[external(v0)]
    fn remove_module(ref self: ContractState, owner: ContractAddress, slot_id: u32) {
        let config = self.bases.read(owner);
        assert(config.owner == owner, 'Not base owner');

        let slot = self.module_slots.read((owner, slot_id));
        assert(slot.is_active, 'Slot not active');

        // Update energy grid
        let mut grid = self.energy_grids.read(owner);
        grid.total_consumption -= slot.energy_drain;
        grid.surplus = grid.total_generation - grid.total_consumption;
        self.energy_grids.write(owner, grid);

        // Reset slot
        let empty_slot = ModuleSlot {
            slot_id,
            module_id: 0,
            installed_at: 0,
            energy_drain: 0,
            is_active: false,
        };
        self.module_slots.write((owner, slot_id), empty_slot);

        self.emit(BaseEvent::ModuleRemoved(ModuleRemoved {
            base_id: 0,
            slot_id,
        }));
    }

    #[external(v0)]
    fn upgrade_base(ref self: ContractState, owner: ContractAddress) {
        let mut config = self.bases.read(owner);
        assert(config.owner == owner, 'Not base owner');

        let old_level = config.base_level;
        config.base_level += 1;
        config.max_slots += 2; // +2 slots per upgrade
        config.energy_capacity += 500;
        config.energy_regeneration += 5;

        self.bases.write(owner, config);

        // Update energy grid
        let mut grid = self.energy_grids.read(owner);
        grid.total_generation += 5;
        grid.surplus = grid.total_generation - grid.total_consumption;
        self.energy_grids.write(owner, grid);

        self.emit(BaseEvent::BaseUpgraded(BaseUpgraded {
            base_id: 0,
            old_level,
            new_level: config.base_level,
        }));
    }

    // ────────────────────────────────────────────────────────────────────────
    // View Functions
    // ────────────────────────────────────────────────────────────────────────

    #[external(v0)]
    fn get_base_config(self: @ContractState, owner: ContractAddress) -> BaseConfig {
        self.bases.read(owner)
    }

    #[external(v0)]
    fn get_module_slot(
        self: @ContractState,
        owner: ContractAddress,
        slot_id: u32,
    ) -> ModuleSlot {
        self.module_slots.read((owner, slot_id))
    }

    #[external(v0)]
    fn get_energy_grid(self: @ContractState, owner: ContractAddress) -> EnergyGrid {
        self.energy_grids.read(owner)
    }

    #[external(v0)]
    fn calculate_synergy_bonus(
        self: @ContractState,
        owner: ContractAddress,
    ) -> u128 {
        // S_max = 2.5× limit for synergy
        let grid = self.energy_grids.read(owner);
        let synergy_ratio = grid.total_generation * ENERGY_SCALE / 
            (grid.total_consumption + 1); // Avoid division by zero
        
        if synergy_ratio > 25000 {
            // 2.5× in fixed-point
            return 25000;
        }
        synergy_ratio
    }
}
