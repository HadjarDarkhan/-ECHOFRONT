#[cfg(test)]
mod tests;

use starknet::ContractAddress;

// ============================================================================
// ECHOFRONT - Economy & Royalties Contract
// Роялті UGC, гільдійна скарбниця, економічний баланс
// ============================================================================

// ────────────────────────────────────────────────────────────────────────────
// ECS Components
// ────────────────────────────────────────────────────────────────────────────

#[derive(Copy, Drop, serde::Serde, PartialEq)]
struct GuildTreasury {
    guild_id: u32,
    total_balance: u128,
    member_count: u32,
    royalty_share: u32, // Basis points
    last_distribution: u64,
}

#[derive(Copy, Drop, serde::Serde, PartialEq)]
struct RoyaltyConfig {
    platform_fee: u32, // Basis points (e.g., 250 = 2.5%)
    creator_share: u32, // Basis points (e.g., 750 = 7.5%)
    guild_share: u32, // Basis points (e.g., 250 = 2.5%)
    burn_rate: u32, // Basis points (e.g., 100 = 1% burned)
}

#[derive(Copy, Drop, serde::Serde, PartialEq)]
struct EconomicMetrics {
    total_volume: u128,
    total_royalties: u128,
    total_burned: u128,
    total_distributed: u128,
    last_update_block: u64,
}

#[derive(Copy, Drop, serde::Serde, PartialEq)]
struct PlayerEarnings {
    player: ContractAddress,
    total_earned: u128,
    pending_claim: u128,
    last_claim_block: u64,
}

// ────────────────────────────────────────────────────────────────────────────
// Events
// ────────────────────────────────────────────────────────────────────────────

#[derive(Drop, starknet::Event)]
enum EconomyEvent {
    #[flat]
    RoyaltyCollected: RoyaltyCollected,
    #[flat]
    RoyaltyDistributed: RoyaltyDistributed,
    #[flat]
    GuildCreated: GuildCreated,
    #[flat]
    TokensBurned: TokensBurned,
    #[flat]
    ClaimedRewards: ClaimedRewards,
}

#[derive(Drop, starknet::Event)]
struct RoyaltyCollected {
    module_id: u32,
    amount: u128,
    platform_fee: u128,
    creator_share: u128,
    guild_share: u128,
    burned: u128,
}

#[derive(Drop, starknet::Event)]
struct RoyaltyDistributed {
    recipient: ContractAddress,
    amount: u128,
    source: felt252,
}

#[derive(Drop, starknet::Event)]
struct GuildCreated {
    guild_id: u32,
    treasury_balance: u128,
    timestamp: u64,
}

#[derive(Drop, starknet::Event)]
struct TokensBurned {
    amount: u128,
    burn_address: ContractAddress,
    timestamp: u64,
}

#[derive(Drop, starknet::Event)]
struct ClaimedRewards {
    player: ContractAddress,
    amount: u128,
    timestamp: u64,
}

// ────────────────────────────────────────────────────────────────────────────
// Storage
// ────────────────────────────────────────────────────────────────────────────

#[starknet::contract]
mod EconomyRoyalties {
    use starknet::ContractAddress;
    use core::option::OptionTrait;
    use super::{
        GuildTreasury, RoyaltyConfig, EconomicMetrics, PlayerEarnings,
        EconomyEvent,
    };

    const BURN_ADDRESS: ContractAddress = 0x1_dead;
    const BASIS_POINTS: u32 = 10000;

    #[storage]
    struct Storage {
        #[map]
        guild_treasuries: u32 => GuildTreasury,
        #[map]
        player_guilds: ContractAddress => u32,
        royalty_config: RoyaltyConfig,
        economic_metrics: EconomicMetrics,
        #[map]
        player_earnings: ContractAddress => PlayerEarnings,
        #[map]
        guild_counter: u32,
        admin: ContractAddress,
    }

    #[init]
    fn init(ref self: ContractState, admin: ContractAddress) {
        self.admin.write(admin);
        self.guild_counter.write(0);

        // Initialize royalty configuration
        let config = RoyaltyConfig {
            platform_fee: 250, // 2.5%
            creator_share: 750, // 7.5%
            guild_share: 250, // 2.5%
            burn_rate: 100, // 1%
        };
        self.royalty_config.write(config);

        // Initialize economic metrics
        let metrics = EconomicMetrics {
            total_volume: 0,
            total_royalties: 0,
            total_burned: 0,
            total_distributed: 0,
            last_update_block: starknet::get_block_number(),
        };
        self.economic_metrics.write(metrics);
    }

    // ────────────────────────────────────────────────────────────────────────
    // Internal Functions
    // ────────────────────────────────────────────────────────────────────────

    fn _calculate_royalty_split(
        self: @ContractState,
        amount: u128,
    ) -> (u128, u128, u128, u128) {
        let config = self.royalty_config.read();

        let platform_fee = amount * config.platform_fee as u128 / BASIS_POINTS as u128;
        let creator_share = amount * config.creator_share as u128 / BASIS_POINTS as u128;
        let guild_share = amount * config.guild_share as u128 / BASIS_POINTS as u128;
        let burned = amount * config.burn_rate as u128 / BASIS_POINTS as u128;

        (platform_fee, creator_share, guild_share, burned)
    }

    fn _update_metrics(
        ref self: ContractState,
        volume: u128,
        royalties: u128,
        burned: u128,
        distributed: u128,
    ) {
        let mut metrics = self.economic_metrics.read();
        metrics.total_volume += volume;
        metrics.total_royalties += royalties;
        metrics.total_burned += burned;
        metrics.total_distributed += distributed;
        metrics.last_update_block = starknet::get_block_number();
        self.economic_metrics.write(metrics);
    }

    // ────────────────────────────────────────────────────────────────────────
    // External Functions
    // ────────────────────────────────────────────────────────────────────────

    #[external(v0)]
    fn collect_royalty(
        ref self: ContractState,
        module_id: u32,
        sale_amount: u128,
        creator: ContractAddress,
    ) {
        let royalty_rate: u128 = 500; // 5% royalty on secondary sales
        let royalty_amount = sale_amount * royalty_rate / 10000;

        let (platform_fee, creator_share, guild_share, burned) = 
            self._calculate_royalty_split(royalty_amount);

        // Update creator earnings
        let mut creator_earnings = self.player_earnings.read(creator);
        creator_earnings.player = creator;
        creator_earnings.total_earned += creator_share;
        creator_earnings.pending_claim += creator_share;
        self.player_earnings.write(creator, creator_earnings);

        // Distribute guild share (if creator is in a guild)
        let guild_id = self.player_guilds.read(creator);
        if guild_id > 0 {
            let mut treasury = self.guild_treasuries.read(guild_id);
            treasury.total_balance += guild_share;
            self.guild_treasuries.write(guild_id, treasury);
        }

        // Burn tokens
        if burned > 0 {
            // In production, actually burn tokens
            self.emit(EconomyEvent::TokensBurned(TokensBurned {
                amount: burned,
                burn_address: BURN_ADDRESS,
                timestamp: starknet::get_block_number(),
            }));
        }

        // Update metrics
        self._update_metrics(sale_amount, royalty_amount, burned, creator_share + guild_share);

        self.emit(EconomyEvent::RoyaltyCollected(RoyaltyCollected {
            module_id,
            amount: royalty_amount,
            platform_fee,
            creator_share,
            guild_share,
            burned,
        }));

        if creator_share > 0 {
            self.emit(EconomyEvent::RoyaltyDistributed(RoyaltyDistributed {
                recipient: creator,
                amount: creator_share,
                source: 'Creator Royalty',
            }));
        }
    }

    #[external(v0)]
    fn create_guild(ref self: ContractState, guild_id: u32) {
        let current_block = starknet::get_block_number();
        
        let treasury = GuildTreasury {
            guild_id,
            total_balance: 0,
            member_count: 1,
            royalty_share: 250, // 2.5% default
            last_distribution: current_block,
        };

        self.guild_treasuries.write(guild_id, treasury);
        self.guild_counter.write(guild_id + 1);

        self.emit(EconomyEvent::GuildCreated(GuildCreated {
            guild_id,
            treasury_balance: 0,
            timestamp: current_block,
        }));
    }

    #[external(v0)]
    fn join_guild(ref self: ContractState, player: ContractAddress, guild_id: u32) {
        let treasury = self.guild_treasuries.read(guild_id);
        assert(treasury.guild_id != 0, 'Guild does not exist');

        self.player_guilds.write(player, guild_id);

        let mut updated_treasury = treasury;
        updated_treasury.member_count += 1;
        self.guild_treasuries.write(guild_id, updated_treasury);
    }

    #[external(v0)]
    fn claim_rewards(ref self: ContractState, player: ContractAddress) -> u128 {
        let mut earnings = self.player_earnings.read(player);
        assert(earnings.pending_claim > 0, 'No pending rewards');

        let claim_amount = earnings.pending_claim;
        earnings.pending_claim = 0;
        earnings.last_claim_block = starknet::get_block_number();
        self.player_earnings.write(player, earnings);

        // In production, transfer tokens here

        self.emit(EconomyEvent::ClaimedRewards(ClaimedRewards {
            player,
            amount: claim_amount,
            timestamp: starknet::get_block_number(),
        }));

        claim_amount
    }

    #[external(v0)]
    fn update_royalty_config(
        ref self: ContractState,
        platform_fee: u32,
        creator_share: u32,
        guild_share: u32,
        burn_rate: u32,
    ) {
        let admin = self.admin.read();
        assert(starknet::get_caller_address() == admin, 'Not admin');

        // Validate total doesn't exceed 100%
        let total = platform_fee + creator_share + guild_share + burn_rate;
        assert(total <= BASIS_POINTS, 'Total exceeds 100%');

        let config = RoyaltyConfig {
            platform_fee,
            creator_share,
            guild_share,
            burn_rate,
        };
        self.royalty_config.write(config);
    }

    #[external(v0)]
    fn distribute_guild_rewards(ref self: ContractState, guild_id: u32) {
        let admin = self.admin.read();
        assert(starknet::get_caller_address() == admin, 'Not admin');

        let mut treasury = self.guild_treasuries.read(guild_id);
        assert(treasury.guild_id != 0, 'Guild does not exist');
        assert(treasury.total_balance > 0, 'No balance to distribute');

        let per_member = treasury.total_balance / treasury.member_count;
        let total_distributed = per_member * treasury.member_count;

        // Reset treasury
        treasury.total_balance -= total_distributed;
        treasury.last_distribution = starknet::get_block_number();
        self.guild_treasuries.write(guild_id, treasury);

        // Update metrics
        self._update_metrics(0, 0, 0, total_distributed);

        self.emit(EconomyEvent::RoyaltyDistributed(RoyaltyDistributed {
            recipient: 0_u16.into(), // Would iterate members in production
            amount: total_distributed,
            source: 'Guild Distribution',
        }));
    }

    // ────────────────────────────────────────────────────────────────────────
    // View Functions
    // ────────────────────────────────────────────────────────────────────────

    #[external(v0)]
    fn get_royalty_config(self: @ContractState) -> RoyaltyConfig {
        self.royalty_config.read()
    }

    #[external(v0)]
    fn get_economic_metrics(self: @ContractState) -> EconomicMetrics {
        self.economic_metrics.read()
    }

    #[external(v0)]
    fn get_guild_treasury(self: @ContractState, guild_id: u32) -> GuildTreasury {
        self.guild_treasuries.read(guild_id)
    }

    #[external(v0)]
    fn get_player_earnings(
        self: @ContractState,
        player: ContractAddress,
    ) -> PlayerEarnings {
        self.player_earnings.read(player)
    }

    #[external(v0)]
    fn get_player_guild(self: @ContractState, player: ContractAddress) -> u32 {
        self.player_guilds.read(player)
    }

    #[external(v0)]
    fn calculate_royalty_preview(
        self: @ContractState,
        sale_amount: u128,
    ) -> (u128, u128, u128, u128) {
        let royalty_rate: u128 = 500; // 5%
        let royalty_amount = sale_amount * royalty_rate / 10000;
        self._calculate_royalty_split(royalty_amount)
    }
}
