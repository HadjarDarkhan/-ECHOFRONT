# ECHOFRONT - Contributing Guide

**Як долучитися до розробки ECHOFRONT**

---

## 🚀 Швидкий Старт для Розробників

### 1. Встановлення Залежностей

```bash
# Scarb (Cairo package manager)
curl --proto '=https' --tlsv1.2 -sSf https://docs.swmansion.com/scarb/install.sh | sh

# Dojo Engine (Sozo)
curl -L https://install.dojoengine.org | bash

# Starkli (Starknet CLI)
curl https://get.starkli.sh | sh

# Snforge (Testing framework)
curl -L https://raw.githubusercontent.com/foundry-rs/starknet-foundry/master/scripts/install.sh | sh

# Node.js (для клієнта)
nvm install 18
```

### 2. Клонувати та Налаштувати

```bash
git clone https://github.com/echofront/echofront.git
cd echofront

# Встановити залежності клієнта
cd client
npm install

# Повернутися до кореня
cd ..
```

### 3. Запуск Локального Середовища

```bash
# Запустити Katana (локальний devnet)
katana --disable-fee --allowed-origins "*" &

# Зібрати контракти
scarb build

# Деплой на локальний Katana
./scripts/deploy.sh full-local

# Запустити Torii indexer
torii --world $(cat .sozo/worlds/latest.json | jq -r '.world_address') \
      --rpc http://localhost:5050 \
      --http --http.addr 0.0.0.0 --http.port 8080 \
      --ws --ws.addr 0.0.0.0 --ws.port 9090 &

# Запустити клієнт
cd client
npm run dev
```

---

## 📝 Процес Розробки

### 1. Створення Гілки

```bash
# Feature branch
git checkout -b feature/new-module-type

# Bug fix branch
git checkout -b fix/wave-calculation-bug
```

### 2. Внесення Змін

**Структура контрактів:**
```
contracts/
├── base_manager.cairo      # Додавати функції сюди
├── tech_dag.cairo          # DAG логіка
├── wave_engine.cairo       # Хвилі, VRF, proofs
├── module_registry.cairo   # UGC, синергії
├── progress_tracker.cairo  # Досягнення, сезони
└── economy_royalties.cairo # Економіка
```

**Приклад додавання нової функції:**

```cairo
// contracts/base_manager.cairo

#[external(v0)]
fn set_module_active(
    ref self: ContractState,
    owner: ContractAddress,
    slot_id: u8,
    is_active: bool,
) {
    let config = self.bases.read(owner);
    assert(config.owner == owner, 'Not base owner');
    
    let mut slot = self.module_slots.read((owner, slot_id));
    assert(slot.module_id != 0, 'Slot empty');
    
    slot.is_active = is_active;
    self.module_slots.write((owner, slot_id), slot);
    
    // Emit event
    self.emit(BaseEvent::ModuleToggled(ModuleToggled {
        owner,
        slot_id,
        is_active,
    }));
}
```

### 3. Написання Тестів

```cairo
// contracts/tests/base_manager_test.cairo

#[cfg(test)]
mod tests {
    use super::BaseManager;
    use starknet::ContractAddress;
    
    #[test]
    fn test_create_base() {
        let admin = 0x1234.into();
        let owner = 0x5678.into();
        
        let contract = BaseManager::deploy(admin).unwrap();
        
        // Create base
        let base_id = contract.create_base(owner).unwrap();
        
        // Assert
        assert(base_id == 1, 'Wrong base ID');
        
        let config = contract.get_base_config(owner).unwrap();
        assert(config.base_level == 1, 'Wrong level');
        assert(config.max_slots == 8, 'Wrong slots');
    }
    
    #[test]
    #[should_panic(expected: 'Max bases reached')]
    fn test_max_bases_limit() {
        // ...
    }
}
```

### 4. Запуск Тестів

```bash
# Unit tests
snforge test

# Integration tests
./scripts/test_integration.sh

# Economic simulation
cd tools
python3 economic_sim.py --quick --fail-on-exploit

# UGC validation
./scripts/ugc_validator.sh validate "Test Module" 1 500 75 500
```

### 5. Форматування та Лінтинг

```bash
# Cairo formatting
scarb fmt

# Check formatting (CI)
scarb fmt --check

# Client linting
cd client
npm run lint
```

---

## 🔧 Пул-Реквести

### Checklist перед Submit

- [ ] Всі тести проходять (`snforge test`)
- [ ] Форматування корректне (`scarb fmt --check`)
- [ ] Економічна симуляція без експлойтів
- [ ] Gas usage ≤ 1.2M units на хвилю
- [ ] Додано changelog entry
- [ ] Оновлено документацію за потреби

### Структура PR

```markdown
## Description
Короткий опис змін

## Type of Change
- [ ] New feature
- [ ] Bug fix
- [ ] Breaking change
- [ ] Documentation update

## Testing
- [ ] Unit tests added/updated
- [ ] Integration tests pass
- [ ] Economic simulation verified

## Gas Impact
- Before: XXX,XXX units
- After: YYY,YYY units
- Change: ±Z%

## Security Considerations
Опис будь-яких security implications
```

---

## 🎨 Coding Standards

### Cairo Style Guide

1. **Naming Conventions:**
   ```cairo
   struct PlayerStats { }      // PascalCase для структур
   fn calculate_score() { }    // snake_case для функцій
   const MAX_PLAYERS = 1000;   // SCREAMING_SNAKE для констант
   ```

2. **Error Handling:**
   ```cairo
   // Використовувати assert з зрозумілими повідомленнями
   assert(balance >= amount, 'Insufficient balance');
   
   // Уникати panic! без повідомлення
   ```

3. **Gas Optimization:**
   ```cairo
   // Використовувати u8/u16 замість u32 де можливо
   struct ModuleSlot {
       slot_id: u8,    // Max 255 slots
       module_id: u16, // Max 65535 modules
   }
   
   // Уникати динамічних циклів
   // Використовувати Felt252Dict для великих колекцій
   ```

4. **Events:**
   ```cairo
   // Емітити події після змін стану
   self.bases.write(owner, config);
   self.emit(BaseEvent::BaseUpgraded(BaseUpgraded {
       base_id,
       old_level,
       new_level,
   }));
   ```

### TypeScript Style Guide

```typescript
// Strict typing
interface GameState {
  baseConfig: BaseConfig;
  modules: ModuleSlot[];
  currentWave: number;
}

// Async/await замість promise chains
async function commitActions(): Promise<void> {
  await this.account.execute(calls);
}

// Error handling with try/catch
try {
  await gameLoop.completeWave(score, modules);
} catch (error) {
  console.error('Wave submission failed:', error);
}
```

---

## 🧪 Тестування

### Типи Тестів

1. **Unit Tests (snforge):**
   ```bash
   snforge test
   snforge test --filter test_create_base
   snforge coverage
   ```

2. **Integration Tests:**
   ```bash
   ./scripts/test_integration.sh
   ```

3. **Economic Simulation:**
   ```bash
   cd tools
   python3 economic_sim.py --iterations 20000 --plot --strict
   ```

4. **UGC Validation:**
   ```bash
   ./scripts/ugc_validator.sh batch test_modules.json
   ```

### Writing Good Tests

```cairo
#[test]
fn test_synergy_cap_enforcement() {
    // Arrange
    let modules = array![1, 2, 3, 4, 5, 6];
    
    // Act
    let total_synergy = registry.calculate_total_synergy(modules).unwrap();
    
    // Assert
    let max_synergy: u128 = SYNERGY_SCALE * 25 / 10; // 2.5×
    assert(total_synergy <= max_synergy, 'Synergy exceeds S_max');
}

#[test]
#[should_panic(expected: 'Insufficient energy')]
fn test_install_module_without_energy() {
    // Test should panic with specific message
}
```

---

## 📚 Документація

### Оновлення Docs

1. **AUDIT_REPORT.md:** Оновлювати після security review
2. **ARCHITECTURE.md:** Оновлювати при зміні архітектури
3. **README.md:** Оновлювати quick start секцію

### Code Comments

```cairo
// ────────────────────────────────────────────────────────────────────────
// External Functions
// ────────────────────────────────────────────────────────────────────────

/// Install a module into a base slot
/// 
/// # Arguments
/// * `owner` - Base owner address
/// * `slot_id` - Slot index (0-7)
/// * `module_id` - Module to install
/// * `energy_drain` - Energy consumption per wave
/// 
/// # Events
/// Emits `ModuleInstalled` on success
/// 
/// # Gas Cost
/// ~85,000 units
#[external(v0)]
fn install_module(...) {
    // ...
}
```

---

## 🚨 Troubleshooting

### Common Issues

**Problem:** `scarb build` fails with dependency errors
```bash
# Solution: Clean and rebuild
scarb clean
rm -rf target
scarb build
```

**Problem:** Tests fail with "Transaction reverted"
```bash
# Solution: Check panic messages
snforge test --verbose
# Look for the specific assert that failed
```

**Problem:** Katana won't start
```bash
# Solution: Kill existing processes
pkill -f katana
katana --disable-fee --allowed-origins "*" &
```

**Problem:** Torii can't connect to world
```bash
# Solution: Verify world address
cat .sozo/worlds/latest.json | jq '.world_address'
# Restart Torii with correct address
```

---

## 💡 Contribution Ideas

### Good First Issues

1. Add new achievement types to `progress_tracker.cairo`
2. Optimize gas usage in `wave_engine.cairo`
3. Add more validation rules to `ugc_validator.sh`
4. Improve economic simulation graphs
5. Add TypeScript types for all contracts

### Advanced Contributions

1. Implement full DFS cycle detection in `tech_dag.cairo`
2. Add multisig support for admin functions
3. Integrate Starknet VRF oracle
4. Create Godot WebGL client
5. Build UGC reputation system

---

## 📞 Community

- **Discord:** [link]
- **Twitter:** @echofront
- **GitHub Discussions:** [link]

---

*Дякуємо за внесок у розвиток ECHOFRONT! 🎮*
