#[cfg(test)]
mod tests;

use starknet::ContractAddress;

// ============================================================================
// ECHOFRONT - Tech DAG Contract
// Направлений ациклічний граф технологій для еволюції бази
// ============================================================================

// ────────────────────────────────────────────────────────────────────────────
// ECS Components
// ────────────────────────────────────────────────────────────────────────────

#[derive(Copy, Drop, serde::Serde, PartialEq)]
struct TechNode {
    tech_id: u32,
    name: felt252,
    tier: u32,
    cost: u128,
    is_unlocked: bool,
    unlock_time: u64,
}

#[derive(Copy, Drop, serde::Serde, PartialEq)]
struct TechEdge {
    from_tech: u32,
    to_tech: u32,
    dependency_level: u32, // 1 = direct, 2+ = indirect
}

#[derive(Copy, Drop, serde::Serde, PartialEq)]
struct PlayerTechProgress {
    player: ContractAddress,
    unlocked_count: u32,
    highest_tier: u32,
    total_investment: u128,
    last_unlock_block: u64,
}

// ────────────────────────────────────────────────────────────────────────────
// Events
// ────────────────────────────────────────────────────────────────────────────

#[derive(Drop, starknet::Event)]
enum TechEvent {
    #[flat]
    TechUnlocked: TechUnlocked,
    #[flat]
    EdgeCreated: EdgeCreated,
    #[flat]
    ProgressUpdated: ProgressUpdated,
}

#[derive(Drop, starknet::Event)]
struct TechUnlocked {
    player: ContractAddress,
    tech_id: u32,
    tier: u32,
    timestamp: u64,
}

#[derive(Drop, starknet::Event)]
struct EdgeCreated {
    from_tech: u32,
    to_tech: u32,
    dependency_level: u32,
}

#[derive(Drop, starknet::Event)]
struct ProgressUpdated {
    player: ContractAddress,
    unlocked_count: u32,
    highest_tier: u32,
}

// ────────────────────────────────────────────────────────────────────────────
// Storage
// ────────────────────────────────────────────────────────────────────────────

#[starknet::contract]
mod TechDAG {
    use starknet::ContractAddress;
    use core::option::OptionTrait;
    use super::{TechNode, TechEdge, PlayerTechProgress, TechEvent};

    const MAX_TECHS: u32 = 100;
    const MAX_EDGES: u32 = 500;
    const MAX_TIERS: u32 = 5;

    #[storage]
    struct Storage {
        #[map]
        tech_nodes: u32 => TechNode,
        #[map]
        tech_edges: (u32, u32) => TechEdge,
        #[map]
        player_progress: ContractAddress => PlayerTechProgress,
        #[map]
        player_techs: (ContractAddress, u32) => bool,
        tech_counter: u32,
        edge_counter: u32,
        admin: ContractAddress,
    }

    #[init]
    fn init(ref self: ContractState, admin: ContractAddress) {
        self.admin.write(admin);
        self.tech_counter.write(0);
        self.edge_counter.write(0);

        // Initialize root tech nodes (tier 0)
        self._init_root_techs();
    }

    // ────────────────────────────────────────────────────────────────────────
    // Internal Functions
    // ────────────────────────────────────────────────────────────────────────

    fn _init_root_techs(ref self: ContractState) {
        // Root technologies (no prerequisites)
        let root_techs = [
            (1, 'Energy Core', 0, 100),
            (2, 'Basic Defense', 0, 150),
            (3, 'Resource Scanner', 0, 200),
        ];

        let mut i = 0;
        while i < root_techs.len() {
            let (id, name, tier, cost) = root_techs[i];
            let node = TechNode {
                tech_id: id,
                name: name,
                tier,
                cost,
                is_unlocked: false,
                unlock_time: 0,
            };
            self.tech_nodes.write(id, node);
            i += 1;
        }
        self.tech_counter.write(3);
    }

    fn _has_prerequisites(
        self: @ContractState,
        player: ContractAddress,
        tech_id: u32,
    ) -> bool {
        // Check all edges pointing to this tech
        let mut check_id: u32 = 1;
        while check_id <= self.tech_counter.read() {
            let edge = self.tech_edges.read((check_id, tech_id));
            if edge.from_tech != 0 {
                // Edge exists
                let has_prereq = self.player_techs.read((player, check_id));
                if !has_prereq {
                    return false;
                }
            }
            check_id += 1;
        }
        true
    }

    fn _is_dag_valid(self: @ContractState, from_tech: u32, to_tech: u32) -> bool {
        // Prevent cycles: ensure no path from to_tech back to from_tech
        // Simple implementation: check direct reverse edge
        let reverse_edge = self.tech_edges.read((to_tech, from_tech));
        if reverse_edge.from_tech != 0 {
            return false;
        }
        true
    }

    // ────────────────────────────────────────────────────────────────────────
    // External Functions
    // ────────────────────────────────────────────────────────────────────────

    #[external(v0)]
    fn unlock_tech(
        ref self: ContractState,
        player: ContractAddress,
        tech_id: u32,
    ) {
        let tech_node = self.tech_nodes.read(tech_id);
        assert(tech_node.tech_id != 0, 'Tech does not exist');
        assert(!tech_node.is_unlocked, 'Tech already unlocked globally');

        // Check prerequisites
        assert(self._has_prerequisites(player, tech_id), 'Missing prerequisites');

        // Check if player already has this tech
        assert(!self.player_techs.read((player, tech_id)), 'Player already has tech');

        let current_block = starknet::get_block_number();

        // Mark as unlocked for player
        self.player_techs.write((player, tech_id), true);

        // Update player progress
        let mut progress = self.player_progress.read(player);
        progress.unlocked_count += 1;
        if tech_node.tier > progress.highest_tier {
            progress.highest_tier = tech_node.tier;
        }
        progress.total_investment += tech_node.cost;
        progress.last_unlock_block = current_block;
        self.player_progress.write(player, progress);

        // Mark tech as globally unlocked (optional, for UGC visibility)
        let mut updated_node = tech_node;
        updated_node.is_unlocked = true;
        updated_node.unlock_time = current_block;
        self.tech_nodes.write(tech_id, updated_node);

        self.emit(TechEvent::TechUnlocked(TechUnlocked {
            player,
            tech_id,
            tier: tech_node.tier,
            timestamp: current_block,
        }));

        self.emit(TechEvent::ProgressUpdated(ProgressUpdated {
            player,
            unlocked_count: progress.unlocked_count,
            highest_tier: progress.highest_tier,
        }));
    }

    #[external(v0)]
    fn create_dependency(
        ref self: ContractState,
        from_tech: u32,
        to_tech: u32,
        dependency_level: u32,
    ) {
        let admin = self.admin.read();
        assert(starknet::get_caller_address() == admin, 'Not admin');

        assert(from_tech != to_tech, 'Self-dependency not allowed');
        assert(self._is_dag_valid(from_tech, to_tech), 'Would create cycle');

        let edge_count = self.edge_counter.read();
        assert(edge_count < MAX_EDGES, 'Max edges reached');

        let edge = TechEdge {
            from_tech,
            to_tech,
            dependency_level,
        };
        self.tech_edges.write((from_tech, to_tech), edge);
        self.edge_counter.write(edge_count + 1);

        self.emit(TechEvent::EdgeCreated(EdgeCreated {
            from_tech,
            to_tech,
            dependency_level,
        }));
    }

    #[external(v0)]
    fn add_new_tech(
        ref self: ContractState,
        name: felt252,
        tier: u32,
        cost: u128,
    ) -> u32 {
        let admin = self.admin.read();
        assert(starknet::get_caller_address() == admin, 'Not admin');

        assert(tier <= MAX_TIERS, 'Tier exceeds maximum');

        let tech_count = self.tech_counter.read();
        assert(tech_count < MAX_TECHS, 'Max techs reached');

        let new_id = tech_count + 1;
        let node = TechNode {
            tech_id: new_id,
            name,
            tier,
            cost,
            is_unlocked: false,
            unlock_time: 0,
        };
        self.tech_nodes.write(new_id, node);
        self.tech_counter.write(new_id);

        new_id
    }

    // ────────────────────────────────────────────────────────────────────────
    // View Functions
    // ────────────────────────────────────────────────────────────────────────

    #[external(v0)]
    fn get_tech_node(self: @ContractState, tech_id: u32) -> TechNode {
        self.tech_nodes.read(tech_id)
    }

    #[external(v0)]
    fn get_tech_edge(
        self: @ContractState,
        from_tech: u32,
        to_tech: u32,
    ) -> TechEdge {
        self.tech_edges.read((from_tech, to_tech))
    }

    #[external(v0)]
    fn get_player_progress(
        self: @ContractState,
        player: ContractAddress,
    ) -> PlayerTechProgress {
        self.player_progress.read(player)
    }

    #[external(v0)]
    fn has_player_unlocked(
        self: @ContractState,
        player: ContractAddress,
        tech_id: u32,
    ) -> bool {
        self.player_techs.read((player, tech_id))
    }

    #[external(v0)]
    fn can_unlock_tech(
        self: @ContractState,
        player: ContractAddress,
        tech_id: u32,
    ) -> bool {
        let tech_node = self.tech_nodes.read(tech_id);
        if tech_node.tech_id == 0 {
            return false;
        }
        if self.player_techs.read((player, tech_id)) {
            return false;
        }
        self._has_prerequisites(player, tech_id)
    }

    #[external(v0)]
    fn get_available_techs(
        self: @ContractState,
        player: ContractAddress,
    ) -> Array<u32> {
        let mut available = ArrayTrait::new();
        let mut tech_id: u32 = 1;
        let max_tech = self.tech_counter.read();

        while tech_id <= max_tech {
            if self.can_unlock_tech(player, tech_id) {
                available.append(tech_id);
            }
            tech_id += 1;
        }
        available
    }
}
