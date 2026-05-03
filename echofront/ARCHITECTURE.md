# ECHOFRONT - Архітектура Ончейн Гри

**Cooperative Defense + Base Evolution на Starknet**

---

## 📐 Загальний Огляд

ECHOFRONT — це ончейн гра з кооперативною обороною та еволюцією бази, побудована на Starknet з використанням Dojo Engine. Гра поєднує off-chain симуляцію з періодичним on-chain комітом стану для мінімізації газу.

---

## 🏗️ Архітектурна Діаграма

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           КЛІЄНТ (Off-Chain)                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌────────────┐ │
│  │ React/Three.js│  │ Game Loop    │  │ Batch Queue  │  │ UI/HUD     │ │
│  │ / Godot WebGL│  │ (45s timer)  │  │ (Actions)    │  │            │ │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  └────────────┘ │
│         │                 │                 │                           │
│         └─────────────────┴─────────────────┘                           │
│                           │                                             │
│                    Session Keys                                         │
│                    (Cartridge)                                          │
└───────────────────────────┼─────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                      Релей / Валідатор                                  │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │ • Перевірка state_hash & actions_hash                            │  │
│  │ • Rate limiting (max calls/min)                                  │  │
│  │ • Gas estimation                                                 │  │
│  └──────────────────────────────────────────────────────────────────┘  │
└───────────────────────────┼─────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    STARKNET (On-Chain)                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌────────────┐ │
│  │ BaseManager  │  │ TechDAG      │  │ WaveEngine   │  │ ModuleReg  │ │
│  │              │  │              │  │              │  │            │ │
│  │ - Base config│  │ - DAG nodes  │  │ - VRF seed   │  │ - UGC reg  │ │
│  │ - Energy grid│  │ - Edges      │  │ - Proofs     │  │ - Synergy  │ │
│  │ - Modules    │  │ - Progress   │  │ - Scores     │  │ - Royalties│ │
│  └──────────────┘  └──────────────┘  └──────────────┘  └────────────┘ │
│  ┌──────────────┐  ┌──────────────┐                                    │
│  │ ProgressTrack│  │ Economy      │                                    │
│  │              │  │              │                                    │
│  │ - Achiev.    │  │ - Treasury   │                                    │
│  │ - Seasons    │  │ - Burn       │                                    │
│  │ - Leaderboard│  │ - Royalties  │                                    │
│  └──────────────┘  └──────────────┘                                    │
└───────────────────────────┼─────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         TORII Indexer                                   │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │ GraphQL Endpoint: http://localhost:8080                          │  │
│  │                                                                  │  │
│  │ Models:                                                          │  │
│  │ • WaveHistory    - Історія хвиль, scores                         │  │
│  │ • ModuleRegistry - UGC модулі, creators                          │  │
│  │ • Leaderboards   - Сезонні рейтинги                              │  │
│  │ • UGCListings    - Доступні модулі для купівлі                  │  │
│  └──────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 📦 Компоненти Системи

### 1. On-Chain Контракти (Cairo 1.0 / Dojo ECS)

| Контракт | Призначення | Ключові Функції |
|----------|-------------|-----------------|
| **BaseManager** | Конфіг бази, енергомережа, слоти | `create_base`, `install_module`, `upgrade_base` |
| **TechDAG** | Направлений ациклічний граф технологій | `unlock_tech`, `create_dependency`, `add_new_tech` |
| **WaveEngine** | Генерація хвиль, VRF, proof verification | `start_next_wave`, `submit_wave_result` |
| **ModuleRegistry** | Реєстр модулів, синергії, UGC | `register_module`, `validate_module`, `create_synergy` |
| **ProgressTracker** | Досягнення, сезонний рейтинг | `unlock_achievement`, `start_new_season` |
| **EconomyRoyalties** | Роялті, гільдії, burn mechanics | `collect_royalty`, `create_guild`, `claim_rewards` |

### 2. Off-Chain Клієнт

- **Game Loop:** Симуляція бою, pathfinding, AI ворогів
- **Batch Queue:** Накопичення дій кожні 45с
- **State Hash:** Обчислення хешу стану для proof
- **UI/UX:** Онбординг, HUD, UGC браузер

### 3. Cartridge Controller

- **Session Keys:** Газлес транзакції з лімітами
- **Policies:** Max 10 calls/min для базових дій
- **Social Login:** Email/Discord аутентифікація

### 4. Torii Indexer

- **GraphQL API:** Запити до історії гри
- **Real-time Updates:** WebSocket підписки
- **Leaderboards:** Сезонні рейтинги

---

## 🔐 Модель Безпеки

### Batched Commit Pattern

```
Клієнт → [Дії 1-50] → State Hash → Actions Hash → Релей → On-Chain
                                              ↓
                                      Верифікація:
                                      • VRF seed
                                      • Nonce
                                      • Timestamp
                                      • S_max ≤ 2.5×
```

### Session Keys Policies

```typescript
policies: [
  {
    contract: "base_manager",
    entrypoints: ["install_module", "remove_module"],
    maxCallsPerMinute: 10,
    maxFee: "0.001 ETH"
  },
  {
    contract: "wave_engine",
    entrypoints: ["submit_wave_result"],
    maxCallsPerMinute: 2,
    maxFee: "0.002 ETH"
  }
]
```

### UGC Валідація

1. **Автоматична перевірка:** DAG правила, stats/energy ratio
2. **Симуляція:** Off-chain sandbox тестування
3. **Community voting:** Після валідації - голосування гравців
4. **Reputation система:** Куратори отримують reputation бали

---

## 💰 Економічна Модель

### Параметри (з `economic_sim.py`)

| Параметр | Значення | Опис |
|----------|----------|------|
| `α_base` | 1.0× | Базова складність хвилі |
| `α_increment` | 0.15× | Приріст складності |
| `α_cap` | 10.0× | Максимальна складність |
| `S_max` | 2.5× | Максимальна синергія |
| `R_base` | 1000 | Базова винагорода |
| `η_base` | 1.0 | Базова ефективність |
| `burn_rate` | 1% | Відсоток спалювання |
| `royalty_rate` | 5% | Роялті з вторинного ринку |

### Розподіл Роялті

```
Secondary Sale (100%)
├── Platform Fee: 2.5%
├── Creator Share: 7.5%
├── Guild Share: 2.5%
└── Burned: 1%
```

---

## ⚡ Gas Оптимізація

### Стратегії

1. **Batched Actions:** 50 дій в одній транзакції
2. **Event Batching:** Емітити події раз на хвилю
3. **Hash vs Array:** `u256` замість `Array<u32>`
4. **Compact Storage:** `u8` замість `u32` де можливо
5. **Lazy Evaluation:** Не оновлювати незмінений стан

### Benchmark (очікуваний)

| Операція | Gas Units | ETH (Sepolia) |
|----------|-----------|---------------|
| Install Module | 85,000 | ~0.000085 |
| Submit Wave (batch) | 280,000 | ~0.00028 |
| Unlock Tech | 72,000 | ~0.000072 |
| Register Module | 125,000 | ~0.000125 |

---

## 🎮 Ігровий Потік

### 1. Онбординг (3 хв)

```
Social Login → Session Keys → Tutorial → First Wave
     ↓              ↓             ↓            ↓
  Cartridge    Gasless init   Interactive  Complete
  Auth         (no ETH needed) guide       wave 1
```

### 2. Геймплей Loop

```
[Start Wave] → [Off-chain Combat] → [Victory/Defeat]
     ↓                                      ↓
  VRF Seed                             Calculate Score
     ↓                                      ↓
[Enemy Spawn] ← [Deterministic RNG]    [Submit Proof]
                                            ↓
                                      [Claim Rewards]
                                            ↓
                                      [Module Drop?]
```

### 3. Сезонний Цикл

```
Season Start (Week 1)
       ↓
[Players compete → Waves → Leaderboard updates]
       ↓
Season End (Week 4)
       ↓
[Distribute rewards → Reset progress → Legacy NFTs]
       ↓
Next Season
```

---

## 📊 Torii GraphQL Схема

### Приклади Запитів

```graphql
# Отримати історію хвиль гравця
query PlayerWaveHistory($player: String!) {
  waveResults(where: { player: $player }) {
    edges {
      node {
        wave_number
        score
        timestamp
        modules_used
      }
    }
  }
}

# Отримати лідерборд сезону
query SeasonLeaderboard($seasonId: Int!) {
  playerSeasons(where: { season_id: $seasonId }) {
    edges {
      node {
        player
        total_score
        rank
        waves_completed
      }
    }
  }
}

# Отримати UGC модулі
query UGCModules {
  modules(where: { is_verified: true }) {
    edges {
      node {
        module_id
        name
        creator
        module_type
        royalty_percent
      }
    }
  }
}
```

---

## 🛠️ Інструменти Розробника

### Команди

```bash
# Ініціалізація проекту
starkzap init echofront

# Локальна розробка
./scripts/deploy.sh full-local

# Тестування
./scripts/test_integration.sh

# Економічна симуляція
cd tools && python3 economic_sim.py --plot

# UGC валідація
./scripts/ugc_validator.sh validate "Module" 1 500 75 500

# Деплой на Sepolia
export STARKNET_ACCOUNT_ADDRESS=0x...
export STARKNET_PRIVATE_KEY=0x...
./scripts/deploy.sh sepolia
```

### Конфігурація (`starkzap_config.toml`)

```toml
[project]
name = "echofront"
version = "0.1.0"

[dojo]
world_address = "" # Populated after deploy

[cartridge]
namespace = "echofront"
session_keys_enabled = true
gasless_enabled = true

[[cartridge.policies]]
contract = "base_manager"
entrypoints = ["install_module", "remove_module"]
max_calls_per_minute = 10
```

---

## 📈 Roadmap

### Phase 1: Alpha (Q1 2024)
- ✅ Core contracts deployed
- ✅ Economic balance verified
- ⏳ 500 player alpha test

### Phase 2: Beta (Q2 2024)
- ⏳ UGC marketplace launch
- ⏳ Guild system
- ⏳ Mobile responsive UI

### Phase 3: Mainnet (Q3 2024)
- ⏳ Full token economy
- ⏳ Cross-chain bridges
- ⏳ DAO governance

---

*Останнє оновлення: 2024*
*Версія документу: 1.0*
