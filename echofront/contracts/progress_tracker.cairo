#[cfg(test)]
mod tests;

use starknet::ContractAddress;

// ============================================================================
// ECHOFRONT - Progress Tracker Contract
// Досягнення, сезонний рейтинг, лідерборди
// ============================================================================

// ────────────────────────────────────────────────────────────────────────────
// ECS Components
// ────────────────────────────────────────────────────────────────────────────

#[derive(Copy, Drop, serde::Serde, PartialEq)]
struct Achievement {
    achievement_id: u32,
    name: felt252,
    description: felt252,
    requirement: u128,
    reward: u128,
    is_claimed: bool,
}

#[derive(Copy, Drop, serde::Serde, PartialEq)]
struct PlayerAchievements {
    player: ContractAddress,
    completed_count: u32,
    total_reward: u128,
    last_claim_block: u64,
}

#[derive(Copy, Drop, serde::Serde, PartialEq)]
struct SeasonStats {
    season_id: u32,
    start_block: u64,
    end_block: u64,
    total_players: u32,
    is_active: bool,
}

#[derive(Copy, Drop, serde::Serde, PartialEq)]
struct PlayerSeasonProgress {
    player: ContractAddress,
    season_id: u32,
    total_score: u128,
    waves_completed: u32,
    rank: u32,
    rewards_claimed: bool,
}

// ────────────────────────────────────────────────────────────────────────────
// Events
// ────────────────────────────────────────────────────────────────────────────

#[derive(Drop, starknet::Event)]
enum ProgressEvent {
    #[flat]
    AchievementUnlocked: AchievementUnlocked,
    #[flat]
    AchievementClaimed: AchievementClaimed,
    #[flat]
    SeasonStarted: SeasonStarted,
    #[flat]
    SeasonEnded: SeasonEnded,
    #[flat]
    RankUpdated: RankUpdated,
}

#[derive(Drop, starknet::Event)]
struct AchievementUnlocked {
    player: ContractAddress,
    achievement_id: u32,
    timestamp: u64,
}

#[derive(Drop, starknet::Event)]
struct AchievementClaimed {
    player: ContractAddress,
    achievement_id: u32,
    reward: u128,
}

#[derive(Drop, starknet::Event)]
struct SeasonStarted {
    season_id: u32,
    start_block: u64,
    end_block: u64,
}

#[derive(Drop, starknet::Event)]
struct SeasonEnded {
    season_id: u32,
    winner: ContractAddress,
    winning_score: u128,
}

#[derive(Drop, starknet::Event)]
struct RankUpdated {
    player: ContractAddress,
    season_id: u32,
    new_rank: u32,
    score: u128,
}

// ────────────────────────────────────────────────────────────────────────────
// Storage
// ────────────────────────────────────────────────────────────────────────────

#[starknet::contract]
mod ProgressTracker {
    use starknet::ContractAddress;
    use core::option::OptionTrait;
    use super::{
        Achievement, PlayerAchievements, SeasonStats, PlayerSeasonProgress,
        ProgressEvent,
    };

    const MAX_ACHIEVEMENTS: u32 = 100;
    const SEASON_DURATION: u64 = 100000; // ~1 week in blocks

    #[storage]
    struct Storage {
        #[map]
        achievements: u32 => Achievement,
        #[map]
        player_achievements: (ContractAddress, u32) => bool,
        #[map]
        player_progress: ContractAddress => PlayerAchievements,
        #[map]
        seasons: u32 => SeasonStats,
        #[map]
        player_season: (ContractAddress, u32) => PlayerSeasonProgress,
        current_season: u32,
        achievement_counter: u32,
        admin: ContractAddress,
    }

    #[init]
    fn init(ref self: ContractState, admin: ContractAddress) {
        self.admin.write(admin);
        self.achievement_counter.write(0);
        self.current_season.write(0);

        // Initialize base achievements
        self._init_achievements();
    }

    // ────────────────────────────────────────────────────────────────────────
    // Internal Functions
    // ────────────────────────────────────────────────────────────────────────

    fn _init_achievements(ref self: ContractState) {
        let achievements = [
            (1, 'First Blood', 'Complete first wave', 1, 100),
            (2, 'Wave Master', 'Complete 10 waves', 10, 500),
            (3, 'Tech Pioneer', 'Unlock 5 technologies', 5, 300),
            (4, 'Module Collector', 'Collect 20 modules', 20, 1000),
            (5, 'Perfect Defense', 'Reach wave 25 without losses', 25, 2000),
        ];

        let mut i = 0;
        while i < achievements.len() {
            let (id, name, desc, req, reward) = achievements[i];
            let achievement = Achievement {
                achievement_id: id,
                name,
                description: desc,
                requirement: req,
                reward,
                is_claimed: false,
            };
            self.achievements.write(id, achievement);
            i += 1;
        }
        self.achievement_counter.write(5);
    }

    fn _check_achievement_unlock(
        self: @ContractState,
        player: ContractAddress,
        achievement_id: u32,
        player_value: u128,
    ) -> bool {
        let achievement = self.achievements.read(achievement_id);
        if achievement.achievement_id == 0 {
            return false;
        }
        if self.player_achievements.read((player, achievement_id)) {
            return false; // Already unlocked
        }
        player_value >= achievement.requirement
    }

    // ────────────────────────────────────────────────────────────────────────
    // External Functions
    // ────────────────────────────────────────────────────────────────────────

    #[external(v0)]
    fn unlock_achievement(
        ref self: ContractState,
        player: ContractAddress,
        achievement_id: u32,
        player_value: u128,
    ) {
        let achievement = self.achievements.read(achievement_id);
        assert(achievement.achievement_id != 0, 'Achievement does not exist');

        if !self._check_achievement_unlock(player, achievement_id, player_value) {
            return; // Not yet qualified
        }

        // Mark as unlocked
        self.player_achievements.write((player, achievement_id), true);

        // Update player progress
        let mut progress = self.player_progress.read(player);
        progress.completed_count += 1;
        progress.total_reward += achievement.reward;
        progress.last_claim_block = starknet::get_block_number();
        self.player_progress.write(player, progress);

        self.emit(ProgressEvent::AchievementUnlocked(AchievementUnlocked {
            player,
            achievement_id,
            timestamp: starknet::get_block_number(),
        }));
    }

    #[external(v0)]
    fn claim_achievement_reward(
        ref self: ContractState,
        player: ContractAddress,
        achievement_id: u32,
    ) -> u128 {
        let achievement = self.achievements.read(achievement_id);
        assert(achievement.achievement_id != 0, 'Achievement does not exist');
        assert(self.player_achievements.read((player, achievement_id)), 'Not unlocked');
        assert(!achievement.is_claimed, 'Already claimed');

        // Mark as claimed
        let mut updated_achievement = achievement;
        updated_achievement.is_claimed = true;
        self.achievements.write(achievement_id, updated_achievement);

        // In production, transfer reward tokens here

        self.emit(ProgressEvent::AchievementClaimed(AchievementClaimed {
            player,
            achievement_id,
            reward: achievement.reward,
        }));

        achievement.reward
    }

    #[external(v0)]
    fn start_new_season(ref self: ContractState) -> u32 {
        let admin = self.admin.read();
        assert(starknet::get_caller_address() == admin, 'Not admin');

        let current_season_num = self.current_season.read();
        let new_season_num = current_season_num + 1;
        let current_block = starknet::get_block_number();

        let season = SeasonStats {
            season_id: new_season_num,
            start_block: current_block,
            end_block: current_block + SEASON_DURATION,
            total_players: 0,
            is_active: true,
        };

        self.seasons.write(new_season_num, season);
        self.current_season.write(new_season_num);

        self.emit(ProgressEvent::SeasonStarted(SeasonStarted {
            season_id: new_season_num,
            start_block: current_block,
            end_block: current_block + SEASON_DURATION,
        }));

        new_season_num
    }

    #[external(v0)]
    fn update_season_progress(
        ref self: ContractState,
        player: ContractAddress,
        score: u128,
        waves_completed: u32,
    ) {
        let season_num = self.current_season.read();
        assert(season_num > 0, 'No active season');

        let season = self.seasons.read(season_num);
        assert(season.is_active, 'Season not active');

        let mut progress = self.player_season.read((player, season_num));
        progress.player = player;
        progress.season_id = season_num;
        progress.total_score += score;
        progress.waves_completed += waves_completed;
        progress.rank = 0; // Will be calculated
        progress.rewards_claimed = false;
        self.player_season.write((player, season_num), progress);
    }

    #[external(v0)]
    fn end_season(ref self: ContractState) {
        let admin = self.admin.read();
        assert(starknet::get_caller_address() == admin, 'Not admin');

        let season_num = self.current_season.read();
        let season = self.seasons.read(season_num);
        assert(season.is_active, 'Season not active');

        // Find winner (simplified - in production use Torii for leaderboard)
        // This would iterate through all players and find highest score

        let mut updated_season = season;
        updated_season.is_active = false;
        self.seasons.write(season_num, updated_season);

        self.emit(ProgressEvent::SeasonEnded(SeasonEnded {
            season_id: season_num,
            winner: 0_u16.into(), // Would be actual winner
            winning_score: 0,
        }));
    }

    // ────────────────────────────────────────────────────────────────────────
    // View Functions
    #────────────────────────────────────────────────────────────────────────

    #[external(v0)]
    fn get_achievement(self: @ContractState, id: u32) -> Achievement {
        self.achievements.read(id)
    }

    #[external(v0)]
    fn has_player_achievement(
        self: @ContractState,
        player: ContractAddress,
        achievement_id: u32,
    ) -> bool {
        self.player_achievements.read((player, achievement_id))
    }

    #[external(v0)]
    fn get_player_progress(
        self: @ContractState,
        player: ContractAddress,
    ) -> PlayerAchievements {
        self.player_progress.read(player)
    }

    #[external(v0)]
    fn get_current_season(self: @ContractState) -> SeasonStats {
        let season_num = self.current_season.read();
        self.seasons.read(season_num)
    }

    #[external(v0)]
    fn get_player_season_progress(
        self: @ContractState,
        player: ContractAddress,
        season_id: u32,
    ) -> PlayerSeasonProgress {
        self.player_season.read((player, season_id))
    }

    #[external(v0)]
    fn get_available_achievements(
        self: @ContractState,
        player: ContractAddress,
    ) -> Array<u32> {
        let mut available = ArrayTrait::new();
        let mut id: u32 = 1;
        let max_id = self.achievement_counter.read();

        while id <= max_id {
            if !self.player_achievements.read((player, id)) {
                available.append(id);
            }
            id += 1;
        }
        available
    }
}
