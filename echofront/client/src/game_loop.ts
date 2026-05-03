/**
 * ECHOFRONT - Game Loop with Batched Commit Logic
 * 
 * Off-chain game simulation with periodic on-chain state commits.
 * Commits every 45 seconds or at wave end.
 */

import { Account, CallData, RpcProvider } from 'starknet';
import { Controller } from '@cartridge/controller';
import { createClient } from '@dojoengine/core';
import type { SchemaType } from '../contracts/types';

// ────────────────────────────────────────────────────────────────────────────
// Constants
// ────────────────────────────────────────────────────────────────────────────

const COMMIT_INTERVAL_MS = 45000; // 45 seconds
const WAVE_TIMEOUT_MS = 300000; // 5 minutes
const MAX_BATCH_SIZE = 100;

// ────────────────────────────────────────────────────────────────────────────
// Types
// ────────────────────────────────────────────────────────────────────────────

interface GameState {
  baseConfig: BaseConfig;
  modules: ModuleSlot[];
  currentWave: number;
  score: number;
  resources: Resources;
  lastCommitTime: number;
}

interface BaseConfig {
  level: number;
  energyCapacity: bigint;
  energyRegeneration: bigint;
  shieldIntegrity: bigint;
  maxSlots: number;
}

interface ModuleSlot {
  slotId: number;
  moduleId: number;
  energyDrain: bigint;
  isActive: boolean;
}

interface Resources {
  energy: bigint;
  credits: bigint;
  materials: bigint;
}

interface ActionBatch {
  actions: GameAction[];
  timestamp: number;
  stateHash: string;
  waveNumber: number;
}

type GameAction =
  | { type: 'INSTALL_MODULE'; slotId: number; moduleId: number }
  | { type: 'REMOVE_MODULE'; slotId: number }
  | { type: 'UPGRADE_BASE' }
  | { type: 'UNLOCK_TECH'; techId: number }
  | { type: 'COMPLETE_WAVE'; score: number; modulesUsed: number[] };

// ────────────────────────────────────────────────────────────────────────────
// Game Loop Class
// ────────────────────────────────────────────────────────────────────────────

export class EchofrontGameLoop {
  private gameState: GameState | null = null;
  private actionQueue: GameAction[] = [];
  private commitTimer: NodeJS.Timeout | null = null;
  private isSimulating: boolean = false;
  
  private account: Account | null = null;
  private controller: Controller | null = null;
  private dojoClient: any = null;
  private provider: RpcProvider;

  constructor(rpcUrl: string) {
    this.provider = new RpcProvider({ nodeUrl: rpcUrl });
  }

  /**
   * Initialize game with Cartridge Controller (gasless session keys)
   */
  async initialize(controller: Controller): Promise<void> {
    this.controller = controller;
    this.account = await controller.account();
    
    // Initialize Dojo client
    this.dojoClient = await createClient<SchemaType>({
      clientUrl: 'http://localhost:8080',
      toriiUrl: 'http://localhost:8080',
      relayUrl: 'ws://localhost:9090',
      worldAddress: process.env.WORLD_ADDRESS!,
    });

    // Load initial state from Torii
    await this.loadGameState();

    // Start auto-commit timer
    this.startCommitTimer();

    console.log('🎮 ECHOFRONT initialized with gasless session keys');
  }

  /**
   * Load game state from Torii indexer
   */
  private async loadGameState(): Promise<void> {
    if (!this.dojoClient || !this.account) return;

    try {
      // Query base config
      const baseQuery = await this.dojoClient.getEntities({
        BaseConfig: {},
      });

      // Query module slots
      const modulesQuery = await this.dojoClient.getEntities({
        ModuleSlot: {},
      });

      // Query wave state
      const waveQuery = await this.dojoClient.getEntities({
        WaveConfig: {},
      });

      // Construct game state
      this.gameState = {
        baseConfig: {
          level: Number(baseQuery.entities[0]?.BaseConfig?.base_level ?? 1),
          energyCapacity: BigInt(baseQuery.entities[0]?.BaseConfig?.energy_capacity ?? 1000),
          energyRegeneration: BigInt(baseQuery.entities[0]?.BaseConfig?.energy_regeneration ?? 10),
          shieldIntegrity: BigInt(baseQuery.entities[0]?.BaseConfig?.shield_integrity ?? 100),
          maxSlots: Number(baseQuery.entities[0]?.BaseConfig?.max_slots ?? 8),
        },
        modules: modulesQuery.entities.map((e: any) => ({
          slotId: Number(e.ModuleSlot?.slot_id ?? 0),
          moduleId: Number(e.ModuleSlot?.module_id ?? 0),
          energyDrain: BigInt(e.ModuleSlot?.energy_drain ?? 0),
          isActive: e.ModuleSlot?.is_active ?? false,
        })),
        currentWave: Number(waveQuery.entities[0]?.WaveConfig?.wave_number ?? 0),
        score: 0,
        resources: {
          energy: BigInt(1000),
          credits: BigInt(5000),
          materials: BigInt(2000),
        },
        lastCommitTime: Date.now(),
      };

      console.log('📊 Game state loaded from Torii');
    } catch (error) {
      console.error('Failed to load game state:', error);
    }
  }

  /**
   * Queue action for batched commit
   */
  queueAction(action: GameAction): void {
    if (this.actionQueue.length >= MAX_BATCH_SIZE) {
      console.warn('⚠️ Action queue full, committing early...');
      this.commitActions();
    }

    this.actionQueue.push(action);
    console.log(`📝 Action queued: ${action.type} (queue size: ${this.actionQueue.length})`);
  }

  /**
   * Install module (queued)
   */
  installModule(slotId: number, moduleId: number, energyDrain: bigint): void {
    this.queueAction({
      type: 'INSTALL_MODULE',
      slotId,
      moduleId,
    });

    // Update local state immediately for responsive UI
    if (this.gameState) {
      const slot = this.gameState.modules.find(m => m.slotId === slotId);
      if (slot) {
        slot.moduleId = moduleId;
        slot.energyDrain = energyDrain;
        slot.isActive = true;
      }
    }
  }

  /**
   * Remove module (queued)
   */
  removeModule(slotId: number): void {
    this.queueAction({
      type: 'REMOVE_MODULE',
      slotId,
    });

    // Update local state
    if (this.gameState) {
      const slot = this.gameState.modules.find(m => m.slotId === slotId);
      if (slot) {
        slot.moduleId = 0;
        slot.energyDrain = BigInt(0);
        slot.isActive = false;
      }
    }
  }

  /**
   * Upgrade base (queued)
   */
  upgradeBase(): void {
    this.queueAction({ type: 'UPGRADE_BASE' });
  }

  /**
   * Unlock technology (queued)
   */
  unlockTech(techId: number): void {
    this.queueAction({
      type: 'UNLOCK_TECH',
      techId,
    });
  }

  /**
   * Complete wave and submit proof
   */
  async completeWave(score: number, modulesUsed: number[]): Promise<void> {
    if (!this.gameState) return;

    // Create wave completion action
    this.queueAction({
      type: 'COMPLETE_WAVE',
      score,
      modulesUsed,
    });

    // Force immediate commit for wave completion
    await this.commitActions();
  }

  /**
   * Calculate state hash for proof verification
   */
  private calculateStateHash(): string {
    if (!this.gameState) return '0x0';

    const stateString = JSON.stringify({
      base: this.gameState.baseConfig,
      modules: this.gameState.modules,
      wave: this.gameState.currentWave,
      timestamp: Date.now(),
    });

    // Simple hash (use proper crypto in production)
    return '0x' + Buffer.from(stateString).toString('hex').slice(0, 64);
  }

  /**
   * Commit batched actions to chain
   */
  async commitActions(): Promise<void> {
    if (this.actionQueue.length === 0 || !this.account || !this.gameState) {
      return;
    }

    console.log(`🚀 Committing ${this.actionQueue.length} actions...`);

    try {
      // Create action batch
      const batch: ActionBatch = {
        actions: [...this.actionQueue],
        timestamp: Date.now(),
        stateHash: this.calculateStateHash(),
        waveNumber: this.gameState.currentWave,
      };

      // Process each action
      const calls: any[] = [];

      for (const action of batch.actions) {
        switch (action.type) {
          case 'INSTALL_MODULE':
            calls.push({
              contractAddress: process.env.BASE_MANAGER_ADDRESS!,
              entrypoint: 'install_module',
              calldata: CallData.compile({
                owner: this.account.address,
                slot_id: action.slotId,
                module_id: action.moduleId,
                energy_drain: 50, // Would calculate from module config
              }),
            });
            break;

          case 'REMOVE_MODULE':
            calls.push({
              contractAddress: process.env.BASE_MANAGER_ADDRESS!,
              entrypoint: 'remove_module',
              calldata: CallData.compile({
                owner: this.account.address,
                slot_id: action.slotId,
              }),
            });
            break;

          case 'UPGRADE_BASE':
            calls.push({
              contractAddress: process.env.BASE_MANAGER_ADDRESS!,
              entrypoint: 'upgrade_base',
              calldata: CallData.compile({
                owner: this.account.address,
              }),
            });
            break;

          case 'UNLOCK_TECH':
            calls.push({
              contractAddress: process.env.TECH_DAG_ADDRESS!,
              entrypoint: 'unlock_tech',
              calldata: CallData.compile({
                player: this.account.address,
                tech_id: action.techId,
              }),
            });
            break;

          case 'COMPLETE_WAVE':
            const actionsHash = this.calculateActionsHash(batch.actions);
            calls.push({
              contractAddress: process.env.WAVE_ENGINE_ADDRESS!,
              entrypoint: 'submit_wave_result',
              calldata: CallData.compile({
                player: this.account.address,
                state_hash: [
                  BigInt(batch.stateHash) & ((BigInt(1) << BigInt(128)) - BigInt(1)),
                  BigInt(batch.stateHash) >> BigInt(128),
                ],
                actions_hash: [
                  BigInt(actionsHash) & ((BigInt(1) << BigInt(128)) - BigInt(1)),
                  BigInt(actionsHash) >> BigInt(128),
                ],
                modules_used: action.modulesUsed,
              }),
            });
            break;
        }
      }

      // Execute multicall (gasless via Cartridge session keys)
      const tx = await this.account.execute(calls);
      
      console.log('✅ Actions committed!', tx.transaction_hash);

      // Wait for transaction
      await this.provider.waitForTransaction(tx.transaction_hash);

      // Clear queue and update state
      this.actionQueue = [];
      this.gameState.lastCommitTime = Date.now();
      
      // Reload state from chain
      await this.loadGameState();

    } catch (error) {
      console.error('❌ Failed to commit actions:', error);
      throw error;
    }
  }

  /**
   * Calculate actions hash for proof
   */
  private calculateActionsHash(actions: GameAction[]): string {
    const actionsString = JSON.stringify(actions);
    return '0x' + Buffer.from(actionsString).toString('hex').slice(0, 64);
  }

  /**
   * Start auto-commit timer
   */
  private startCommitTimer(): void {
    if (this.commitTimer) {
      clearInterval(this.commitTimer);
    }

    this.commitTimer = setInterval(() => {
      if (this.actionQueue.length > 0) {
        console.log('⏰ Auto-commit triggered (45s interval)');
        this.commitActions();
      }
    }, COMMIT_INTERVAL_MS);
  }

  /**
   * Stop game loop
   */
  stop(): void {
    if (this.commitTimer) {
      clearInterval(this.commitTimer);
      this.commitTimer = null;
    }
    this.isSimulating = false;
    console.log('⏹️ Game loop stopped');
  }

  /**
   * Get current game state
   */
  getGameState(): GameState | null {
    return this.gameState;
  }

  /**
   * Get queued actions count
   */
  getQueuedActionsCount(): number {
    return this.actionQueue.length;
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Usage Example
// ────────────────────────────────────────────────────────────────────────────

/*
import { Controller } from '@cartridge/controller';

async function main() {
  // Initialize Cartridge Controller with session keys
  const controller = new Controller({
    namespace: 'echofront',
    policies: [
      {
        contractAddress: process.env.BASE_MANAGER_ADDRESS!,
        entrypoints: ['install_module', 'remove_module', 'upgrade_base'],
        maxCallsPerMinute: 10,
      },
      {
        contractAddress: process.env.WAVE_ENGINE_ADDRESS!,
        entrypoints: ['submit_wave_result'],
        maxCallsPerMinute: 2,
      },
    ],
  });

  // Connect wallet (social login / gasless)
  await controller.connect();

  // Initialize game loop
  const gameLoop = new EchofrontGameLoop('https://starknet-sepolia.public.blastapi.io');
  await gameLoop.initialize(controller);

  // Queue some actions
  gameLoop.installModule(0, 1, BigInt(50));
  gameLoop.installModule(1, 2, BigInt(75));
  gameLoop.upgradeBase();

  // Actions will auto-commit after 45s or can force commit
  // await gameLoop.commitActions();

  // Complete wave (forces immediate commit)
  // await gameLoop.completeWave(15000, [1, 2, 3]);
}

main().catch(console.error);
*/
