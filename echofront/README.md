# ECHOFRONT - On-Chain Core Architecture

## 📁 Структура файлів

```
echofront/
├── contracts/
│   ├── base_manager.cairo          # Конфіг бази, енергомережа, слоти
│   ├── tech_dag.cairo              # Направлений ациклічний граф технологій
│   ├── module_registry.cairo       # Реєстр модулів, синергії, UGC-валідація
│   ├── wave_engine.cairo           # Генерація хвиль, VRF, WaveResultProof
│   ├── progress_tracker.cairo      # Досягнення, сезонний рейтинг
│   └── economy_royalties.cairo     # Роялті UGC, гільдійна скарбниця
├── client/
│   ├── src/
│   │   ├── game_loop.ts            # Симуляція, batch actions, commit logic
│   │   ├── cartridge_integration.ts # Session keys, gasless actions
│   │   └── torii_client.ts         # Indexer queries
│   ├── ui/
│   │   ├── onboarding.tsx
│   │   ├── hud.tsx
│   │   └── ugc_browser.tsx
│   └── package.json
├── tools/
│   ├── starkzap_config.toml        # Скеффолд, деплой, тести
│   └── economic_sim.py             # Симуляція кривих, sink/faucet, баланс
├── scripts/
│   ├── deploy.sh
│   ├── test_integration.sh
│   └── ugc_validator.sh
├── Scarb.toml
├── dojo.toml
└── README.md
```

## 🔧 Ключові Cairo контракти

### 1. Base Manager (`base_manager.cairo`)

Управління конфігурацією бази, енергомережею та слотами модулів.

**ECS Components:**
- `BaseConfig` - рівень бази, енергія, щити
- `ModuleSlot` - слоти для модулів
- `EnergyGrid` - генерація/споживання енергії

**Key Functions:**
- `create_base(owner)` - створити нову базу
- `install_module(owner, slot_id, module_id, energy_drain)` - встановити модуль
- `remove_module(owner, slot_id)` - видалити модуль
- `upgrade_base(owner)` - покращити базу (+2 слоти, +500 енергії)
- `calculate_synergy_bonus(owner)` - розрахунок синергії (S_max = 2.5×)

### 2. Tech DAG (`tech_dag.cairo`)

Направлений ациклічний граф технологій для еволюції бази.

**ECS Components:**
- `TechNode` - вузол технології
- `TechEdge` - залежність між технологіями
- `PlayerTechProgress` - прогрес гравця

**Key Functions:**
- `unlock_tech(player, tech_id)` - відкрити технологію
- `create_dependency(from, to, level)` - створити залежність (admin)
- `add_new_tech(name, tier, cost)` - додати нову технологію (admin)
- `get_available_techs(player)` - доступні технології

### 3. Wave Engine (`wave_engine.cairo`)

Генерація хвиль, VRF-інтеграція, WaveResultProof верифікація.

**ECS Components:**
- `WaveConfig` - конфігурація хвилі
- `WaveResultProof` - доказ результату хвилі
- `PlayerWaveStats` - статистика гравця
- `ModuleDrop` - випадіння модулів

**Key Functions:**
- `start_next_wave()` - почати нову хвилю (admin/VRF)
- `submit_wave_result(player, state_hash, actions_hash, modules_used)` -提交 результат
- `_verify_proof(proof, config)` - верифікація доказу
- `_calculate_score(proof, config)` - розрахунок очок з S_max лімітом

### 4. Module Registry (`module_registry.cairo`)

Реєстр модулів, синергії, UGC-валідація.

**ECS Components:**
- `ModuleDefinition` - визначення модуля
- `SynergyRule` - правило синергії
- `UGCValidationResult` - результат валідації

**Key Functions:**
- `register_module(name, type, stats, energy, royalty)` - зареєструвати UGC
- `validate_module(module_id, score)` - валідувати модуль (admin)
- `create_synergy(module_a, module_b, bonus)` - створити синергію
- `calculate_total_synergy(modules)` - загальна синергія (cap 2.5×)

### 5. Progress Tracker (`progress_tracker.cairo`)

Досягнення, сезонний рейтинг, лідерборди.

**ECS Components:**
- `Achievement` - досягнення
- `SeasonStats` - статистика сезону
- `PlayerSeasonProgress` - прогрес сезону

### 6. Economy Royalties (`economy_royalties.cairo`)

Роялті UGC, гільдійна скарбниця, економічний баланс.

**ECS Components:**
- `GuildTreasury` - скарбниця гільдії
- `RoyaltyConfig` - конфігурація роялті
- `EconomicMetrics` - економічні метрики

---

## 🚀 Інструкції з запуску

### 1. Ініціалізація проекту

```bash
# Встановити StarkZap CLI
curl -L https://install.starkzap.io | bash

# Ініціалізувати проект
cd echofront
starkzap init --template dojo

# Встановити залежності
scarb install
```

### 2. Локальна розробка

```bash
# Запустити Katana (локальний devnet)
katana --disable-fee --allowed-origins "*"

# Збудувати контракти
scarb build

# Деплой на локальний Katana
./scripts/deploy.sh local

# Запустити Torii indexer
./scripts/deploy.sh torii
```

### 3. Тестування

```bash
# Запустити всі тести
./scripts/test_integration.sh

# Економічна симуляція
cd tools
python3 economic_sim.py

# Валідація UGC модулів
./scripts/ugc_validator.sh validate "Laser Turret" 1 500 75 500
```

### 4. Деплой на Sepolia

```bash
# Встановити змінні оточення
export STARKNET_ACCOUNT_ADDRESS=0x...
export STARKNET_PRIVATE_KEY=0x...

# Деплой
./scripts/deploy.sh sepolia
```

### 5. Запуск клієнта

```bash
cd client

# Встановити залежності
npm install

# Запустити dev server
npm run dev

# Build для production
npm run build
```

---

## ⚙️ Параметри балансу

| Параметр | Значення | Опис |
|----------|----------|------|
| `α_base` | 1.0× | Базова складність хвилі |
| `α_increment` | 0.15× | Приріст складності на хвилю |
| `α_cap` | 10.0× | Максимальна складність |
| `S_max` | 2.5× | Максимальний синергічний множник |
| `R_base` | 1000 | Базові ресурси на хвилю |
| `η_base` | 1.0 | Базова ефективність |
| Burn Rate | 1% | Відсоток спалювання |
| Royalty Rate | 5% | Роялті з вторинного ринку |

---

## 🔐 Чекліст безпеки та оптимізації

### Безпека

- [ ] Ніякого real-time ончейн коміту - лише batched actions кожні 45с
- [ ] Усі формули відкриті та верифіковувані
- [ ] Ліміти синергії (S_max = 2.5×) запобігають інфляції
- [ ] UGC-модулі проходять автоматичну валідацію перед допуском
- [ ] Gasless лише через Cartridge session keys з обмеженнями (max calls/min)
- [ ] Admin функції захищені мультісігом (потім DAO)
- [ ] VRF seed оновлюється кожну хвилю для детермінованого RNG

### Оптимізація газу

- [ ] Batched actions замість окремих транзакцій
- [ ] Off-chain обчислення (pathfinding, combat AI) з ончейн proof submission
- [ ] Storage оптимізація: packed structs, minimal events
- [ ] View functions для читання стану (безкоштовно)
- [ ] Торгові операції з burn_rate для дефляційного тиску

### Економічний баланс

- [ ] Sink/Faucet баланс перевірено через `economic_sim.py`
- [ ] Інфляція < 10% при 1000 гравцях
- [ ] Роялті не перевищують 5% від обсягу ринку
- [ ] Difficulty cap запобігає експоненційному зростанню нагород

---

## 📊 Torii Indexing Schema

```graphql
# Entities indexed by Torii

type BaseConfig {
  owner: ContractAddress!
  base_level: u32!
  energy_capacity: u128!
  shield_integrity: u128!
}

type ModuleSlot {
  slot_id: u32!
  module_id: u32!
  energy_drain: u128!
  is_active: bool!
}

type WaveResult {
  player: ContractAddress!
  wave_number: u32!
  score: u128!
  state_hash: u256!
  timestamp: u64!
}

type UGCModule {
  module_id: u32!
  creator: ContractAddress!
  name: felt252!
  is_verified: bool!
  royalty_percent: u32!
}

type PlayerProgress {
  player: ContractAddress!
  total_waves: u32!
  best_score: u128!
  achievements_unlocked: u32!
}
```

---

## 📝 License

MIT License - See LICENSE file for details.
