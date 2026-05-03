#[cfg(test)]
mod tests;

use starknet::ContractAddress;

// ============================================================================
// ECHOFRONT - Wave Engine Contract
// Генерація хвиль, VRF-інтеграція, WaveResultProof верифікація
// ============================================================================

// ────────────────────────────────────────────────────────────────────────────
// ECS Components
// ────────────────────────────────────────────────────────────────────────────

#[derive(Copy, Drop, serde::Serde, PartialEq)]
struct WaveConfig {
    wave_number: u32,
    difficulty_alpha: u128, // Fixed-point: 1.0 = 10000
    enemy_count: u32,
    seed: u256,
    start_block: u64,
    end_block: u64,
    is_completed: bool,
}

#[derive(Copy, Drop, serde::Serde, PartialEq)]
struct WaveResultProof {
    player: ContractAddress,
    wave_number: u32,
    state_hash: u256,
    actions_hash: u256,
    vrf_seed: u256,
    score: u128,
    modules_used: Array<u32>,
    timestamp: u64,
}

#[derive(Copy, Drop, serde::Serde, PartialEq)]
struct PlayerWaveStats {
    total_waves: u32,
    completed_waves: u32,
    best_score: u128,
    total_score: u128,
    last_wave_block: u64,
}

#[derive(Copy, Drop, serde::Serde, PartialEq)]
struct ModuleDrop {
    module_id: u32,
    rarity: u32, // 1=common, 2=rare, 3=epic, 4=legendary
    seed_contribution: u256,
}

// ────────────────────────────────────────────────────────────────────────────
// Events
// ────────────────────────────────────────────────────────────────────────────

#[derive(Drop, starknet::Event)]
enum WaveEvent {
    #[flat]
    WaveStarted: WaveStarted,
    #[flat]
    WaveCompleted: WaveCompleted,
    #[flat]
    ProofSubmitted: ProofSubmitted,
    #[flat]
    ModuleDropped: ModuleDropped,
}

#[derive(Drop, starknet::Event)]
struct WaveStarted {
    wave_number: u32,
    difficulty: u128,
    enemy_count: u32,
    seed: u256,
    timestamp: u64,
}

#[derive(Drop, starknet::Event)]
struct WaveCompleted {
    wave_number: u32,
    player: ContractAddress,
    score: u128,
    is_valid: bool,
}

#[derive(Drop, starknet::Event)]
struct ProofSubmitted {
    player: ContractAddress,
    wave_number: u32,
    state_hash: u256,
    is_verified: bool,
}

#[derive(Drop, starknet::Event)]
struct ModuleDropped {
    player: ContractAddress,
    module_id: u32,
    rarity: u32,
    wave_number: u32,
}

// ────────────────────────────────────────────────────────────────────────────
// Storage
// ────────────────────────────────────────────────────────────────────────────

#[starknet::contract]
mod WaveEngine {
    use starknet::ContractAddress;
    use core::option::OptionTrait;
    use super::{WaveConfig, WaveResultProof, PlayerWaveStats, ModuleDrop, WaveEvent};

    const DIFFICULTY_SCALE: u128 = 10000;
    const BASE_DIFFICULTY: u128 = 10000; // 1.0×
    const DIFFICULTY_INCREMENT: u128 = 1500; // +0.15× per wave
    const MAX_WAVE_DURATION: u64 = 300; // 5 minutes in blocks (assuming 1s blocks)

    #[storage]
    struct Storage {
        #[map]
        wave_configs: u32 => WaveConfig,
        #[map]
        player_proofs: (ContractAddress, u32) => WaveResultProof,
        #[map]
        player_stats: ContractAddress => PlayerWaveStats,
        #[map]
        wave_completions: (u32, ContractAddress) => bool,
        current_wave: u32,
        vrf_seed: u256,
        admin: ContractAddress,
    }

    #[init]
    fn init(ref self: ContractState, admin: ContractAddress, initial_seed: u256) {
        self.admin.write(admin);
        self.vrf_seed.write(initial_seed);
        self.current_wave.write(0);
    }

    // ────────────────────────────────────────────────────────────────────────
    // Internal Functions
    // ────────────────────────────────────────────────────────────────────────

    fn _calculate_difficulty(
        self: @ContractState,
        wave_number: u32,
    ) -> u128 {
        // α (alpha) = BASE + (wave × increment)
        // Capped at reasonable limits
        let increment = (wave_number as u128) * DIFFICULTY_INCREMENT;
        let difficulty = BASE_DIFFICULTY + increment;
        
        // Cap at 10× base difficulty
        if difficulty > BASE_DIFFICULTY * 10 {
            return BASE_DIFFICULTY * 10;
        }
        difficulty
    }

    fn _generate_enemy_count(
        self: @ContractState,
        wave_number: u32,
        seed: u256,
    ) -> u32 {
        // Deterministic enemy count based on wave and seed
        let base_enemies = 5 + (wave_number * 2);
        let variance = (seed.low % 5) as u32;
        base_enemies + variance
    }

    fn _verify_proof(
        self: @ContractState,
        proof: @WaveResultProof,
        wave_config: @WaveConfig,
    ) -> bool {
        // Verify VRF seed matches
        if proof.vrf_seed != wave_config.seed {
            return false;
        }

        // Verify wave number
        if proof.wave_number != wave_config.wave_number {
            return false;
        }

        // Verify state hash is non-zero (client computed valid state)
        if proof.state_hash == 0_u256 {
            return false;
        }

        // Verify actions hash is non-zero
        if proof.actions_hash == 0_u256 {
            return false;
        }

        // Verify timestamp is within wave duration
        let current_block = starknet::get_block_number();
        if current_block < wave_config.start_block {
            return false;
        }
        if current_block > wave_config.end_block + 60 {
            // 60 block grace period
            return false;
        }

        true
    }

    fn _calculate_score(
        self: @ContractState,
        proof: @WaveResultProof,
        wave_config: @WaveConfig,
    ) -> u128 {
        // Score formula: base × difficulty × synergy_bonus
        let base_score: u128 = 1000;
        let difficulty_multiplier = wave_config.difficulty_alpha;
        
        // Simple synergy check (modules used)
        let module_count = proof.modules_used.len();
        let synergy_bonus = if module_count > 3 {
            DIFFICULTY_SCALE + (module_count - 3) * 500 // +0.05× per extra module
        } else {
            DIFFICULTY_SCALE
        };

        // Cap synergy at S_max = 2.5×
        let max_synergy = DIFFICULTY_SCALE * 25 / 10; // 2.5×
        let actual_synergy = if synergy_bonus > max_synergy {
            max_synergy
        } else {
            synergy_bonus
        };

        let score = base_score * difficulty_multiplier * actual_synergy / 
                    (DIFFICULTY_SCALE * DIFFICULTY_SCALE);
        score
    }

    fn _determine_module_drop(
        self: @ContractState,
        player: ContractAddress,
        wave_number: u32,
        score: u128,
        seed: u256,
    ) -> Option<ModuleDrop> {
        // Determine if drop occurs based on score and randomness
        let drop_threshold: u128 = 5000;
        if score < drop_threshold {
            return Option::None;
        }

        // Calculate rarity based on score
        let rarity: u32 = if score > 50000 {
            4 // legendary
        } else if score > 20000 {
            3 // epic
        } else if score > 10000 {
            2 // rare
        } else {
            1 // common
        };

        // Deterministic module ID from seed and player
        let module_id = ((seed.low + player as u256) % 1000) as u32;

        Option::Some(ModuleDrop {
            module_id,
            rarity,
            seed_contribution: seed,
        })
    }

    // ────────────────────────────────────────────────────────────────────────
    // External Functions
    // ────────────────────────────────────────────────────────────────────────

    #[external(v0)]
    fn start_next_wave(ref self: ContractState) -> u32 {
        let admin = self.admin.read();
        assert(starknet::get_caller_address() == admin, 'Not admin');

        let current_wave_num = self.current_wave.read();
        let new_wave_num = current_wave_num + 1;
        let current_block = starknet::get_block_number();

        // Update VRF seed (in production, use Starknet VRF oracle)
        let mut seed = self.vrf_seed.read();
        seed.low += 1; // Simple increment for demo; use real VRF in prod
        self.vrf_seed.write(seed);

        // Calculate wave parameters
        let difficulty = self._calculate_difficulty(new_wave_num);
        let enemy_count = self._generate_enemy_count(new_wave_num, seed);

        let wave_config = WaveConfig {
            wave_number: new_wave_num,
            difficulty_alpha: difficulty,
            enemy_count,
            seed,
            start_block: current_block,
            end_block: current_block + MAX_WAVE_DURATION,
            is_completed: false,
        };

        self.wave_configs.write(new_wave_num, wave_config);
        self.current_wave.write(new_wave_num);

        self.emit(WaveEvent::WaveStarted(WaveStarted {
            wave_number: new_wave_num,
            difficulty,
            enemy_count,
            seed,
            timestamp: current_block,
        }));

        new_wave_num
    }

    #[external(v0)]
    fn submit_wave_result(
        ref self: ContractState,
        player: ContractAddress,
        state_hash: u256,
        actions_hash: u256,
        modules_used: Array<u32>,
    ) -> u128 {
        let current_wave_num = self.current_wave.read();
        assert(current_wave_num > 0, 'No active wave');

        let wave_config = self.wave_configs.read(current_wave_num);
        assert(!wave_config.is_completed, 'Wave already completed');

        // Create proof
        let proof = WaveResultProof {
            player,
            wave_number: current_wave_num,
            state_hash,
            actions_hash,
            vrf_seed: wave_config.seed,
            score: 0, // Will be calculated
            modules_used,
            timestamp: starknet::get_block_number(),
        };

        // Verify proof
        let is_valid = self._verify_proof(@proof, @wave_config);
        assert(is_valid, 'Invalid proof');

        // Calculate score
        let score = self._calculate_score(@proof, @wave_config);

        // Store proof
        self.player_proofs.write((player, current_wave_num), proof);
        self.wave_completions.write((current_wave_num, player), true);

        // Update player stats
        let mut stats = self.player_stats.read(player);
        stats.total_waves += 1;
        stats.completed_waves += 1;
        if score > stats.best_score {
            stats.best_score = score;
        }
        stats.total_score += score;
        stats.last_wave_block = starknet::get_block_number();
        self.player_stats.write(player, stats);

        // Mark wave as completed (if first completion)
        let mut updated_config = wave_config;
        updated_config.is_completed = true;
        self.wave_configs.write(current_wave_num, updated_config);

        // Check for module drop
        let drop = self._determine_module_drop(
            player, current_wave_num, score, wave_config.seed
        );
        match drop {
            Option::Some(module_drop) => {
                self.emit(WaveEvent::ModuleDropped(ModuleDropped {
                    player,
                    module_id: module_drop.module_id,
                    rarity: module_drop.rarity,
                    wave_number: current_wave_num,
                }));
            },
            Option::None => {},
        };

        self.emit(WaveEvent::ProofSubmitted(ProofSubmitted {
            player,
            wave_number: current_wave_num,
            state_hash,
            is_verified: is_valid,
        }));

        self.emit(WaveEvent::WaveCompleted(WaveCompleted {
            wave_number: current_wave_num,
            player,
            score,
            is_valid,
        }));

        score
    }

    #[external(v0)]
    fn update_vrf_seed(ref self: ContractState, new_seed: u256) {
        let admin = self.admin.read();
        assert(starknet::get_caller_address() == admin, 'Not admin');
        self.vrf_seed.write(new_seed);
    }

    // ────────────────────────────────────────────────────────────────────────
    // View Functions
    // ────────────────────────────────────────────────────────────────────────

    #[external(v0)]
    fn get_current_wave(self: @ContractState) -> WaveConfig {
        let wave_num = self.current_wave.read();
        self.wave_configs.read(wave_num)
    }

    #[external(v0)]
    fn get_wave_config(self: @ContractState, wave_number: u32) -> WaveConfig {
        self.wave_configs.read(wave_number)
    }

    #[external(v0)]
    fn get_player_proof(
        self: @ContractState,
        player: ContractAddress,
        wave_number: u32,
    ) -> WaveResultProof {
        self.player_proofs.read((player, wave_number))
    }

    #[external(v0)]
    fn get_player_stats(
        self: @ContractState,
        player: ContractAddress,
    ) -> PlayerWaveStats {
        self.player_stats.read(player)
    }

    #[external(v0)]
    fn has_player_completed_wave(
        self: @ContractState,
        wave_number: u32,
        player: ContractAddress,
    ) -> bool {
        self.wave_completions.read((wave_number, player))
    }

    #[external(v0)]
    fn calculate_next_wave_params(
        self: @ContractState,
    ) -> (u128, u32) {
        let next_wave = self.current_wave.read() + 1;
        let difficulty = self._calculate_difficulty(next_wave);
        let seed = self.vrf_seed.read();
        let enemy_count = self._generate_enemy_count(next_wave, seed);
        (difficulty, enemy_count)
    }
}
