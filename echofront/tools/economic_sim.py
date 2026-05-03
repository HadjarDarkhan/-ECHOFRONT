#!/usr/bin/env python3
"""
ECHOFRONT - Economic Simulation Tool

Симуляція економічних кривих, sink/faucet баланс, виявлення експлойтів.
Параметри: α (складність), S_max (синергія), R_base (ресурси), η (ефективність)
"""

import numpy as np
import matplotlib.pyplot as plt
from dataclasses import dataclass
from typing import List, Tuple, Dict
import json

# ────────────────────────────────────────────────────────────────────────────
# Constants & Configuration
# ────────────────────────────────────────────────────────────────────────────

@dataclass
class EconomicConfig:
    """Економічна конфігурація гри"""
    # Difficulty scaling
    alpha_base: float = 1.0  # Базова складність
    alpha_increment: float = 0.15  # Приріст складності на хвилю
    alpha_cap: float = 10.0  # Максимальна складність (10×)
    
    # Synergy limits
    s_max: float = 2.5  # Максимальний синергічний множник
    synergy_bonus_per_module: float = 0.05  # +5% за кожен додатковий модуль
    
    # Resources
    r_base: float = 1000  # Базові ресурси на хвилю
    r_decay: float = 0.95  # Спадання ресурсів при поразці
    
    # Efficiency
    eta_base: float = 1.0  # Базова ефективність
    eta_improvement: float = 0.02  # Покращення ефективності від технологій
    
    # Economy
    credit_reward_base: int = 100
    credit_inflation_rate: float = 0.02  # 2% інфляція
    burn_rate: float = 0.01  # 1% спалювання
    royalty_rate: float = 0.05  # 5% роялті


# ────────────────────────────────────────────────────────────────────────────
# Economic Models
# ────────────────────────────────────────────────────────────────────────────

class WaveEconomy:
    """Моделювання економіки хвиль"""
    
    def __init__(self, config: EconomicConfig):
        self.config = config
        self.wave_rewards: List[float] = []
        self.difficulty_curve: List[float] = []
        self.synergy_multipliers: List[float] = []
        
    def calculate_difficulty(self, wave_number: int) -> float:
        """Розрахунок складності хвилі: α(w) = α_base + w × α_increment"""
        difficulty = self.config.alpha_base + (wave_number * self.config.alpha_increment)
        return min(difficulty, self.config.alpha_cap)
    
    def calculate_synergy_bonus(self, modules_used: int) -> float:
        """Розрахунок синергії: S = min(S_max, 1 + (n-3) × 0.05)"""
        if modules_used <= 3:
            return 1.0
        
        bonus = 1.0 + (modules_used - 3) * self.config.synergy_bonus_per_module
        return min(bonus, self.config.s_max)
    
    def calculate_wave_reward(
        self,
        wave_number: int,
        modules_used: int,
        efficiency: float = 1.0,
        is_victory: bool = True
    ) -> float:
        """
        Розрахунок винагороди за хвилю:
        R = R_base × α(w) × S × η × victory_multiplier
        """
        difficulty = self.calculate_difficulty(wave_number)
        synergy = self.calculate_synergy_bonus(modules_used)
        
        victory_multiplier = 1.0 if is_victory else self.config.r_decay
        
        reward = (
            self.config.r_base 
            * difficulty 
            * synergy 
            * efficiency 
            * victory_multiplier
        )
        
        self.wave_rewards.append(reward)
        self.difficulty_curve.append(difficulty)
        self.synergy_multipliers.append(synergy)
        
        return reward
    
    def simulate_waves(self, num_waves: int = 100) -> Dict:
        """Симуляція проходження хвиль"""
        results = {
            'waves': [],
            'rewards': [],
            'difficulty': [],
            'synergy': [],
            'cumulative_rewards': [],
        }
        
        cumulative = 0
        for wave in range(1, num_waves + 1):
            # Припускаємо оптимальну гру (4-6 модулів)
            modules = 4 + (wave % 3)  # 4, 5, 6, 4, 5, 6...
            efficiency = min(1.0 + wave * 0.001, 1.5)  # Поступове покращення
            
            reward = self.calculate_wave_reward(wave, modules, efficiency)
            cumulative += reward
            
            results['waves'].append(wave)
            results['rewards'].append(reward)
            results['difficulty'].append(self.calculate_difficulty(wave))
            results['synergy'].append(self.calculate_synergy_bonus(modules))
            results['cumulative_rewards'].append(cumulative)
        
        return results


class InflationAnalyzer:
    """Аналіз інфляції та балансу sink/faucet"""
    
    def __init__(self, config: EconomicConfig):
        self.config = config
        self.money_supply: List[float] = []
        self.burned: List[float] = []
        self.royalties: List[float] = []
        
    def simulate_economy(
        self,
        players: int = 1000,
        waves_per_player: int = 50,
        secondary_sales_rate: float = 0.3
    ) -> Dict:
        """
        Симуляція економіки з гравцями та вторинним ринком
        """
        wave_econ = WaveEconomy(self.config)
        
        total_credits_minted = 0
        total_credits_burned = 0
        total_royalties_collected = 0
        money_supply_history = []
        
        for player in range(players):
            player_rewards = 0
            
            for wave in range(1, waves_per_player + 1):
                reward = wave_econ.calculate_wave_reward(
                    wave_number=wave,
                    modules_used=4 + (player % 3),
                    efficiency=1.0 + player * 0.0001
                )
                player_rewards += reward
            
            # Інфляційне коригування
            inflation_adjusted = player_rewards * (1 + self.config.credit_inflation_rate) ** (player / 100)
            total_credits_minted += inflation_adjusted
            
            # Спалювання (частини транзакцій)
            transaction_volume = inflation_adjusted * 0.5  # 50% витрачається
            burned = transaction_volume * self.config.burn_rate
            total_credits_burned += burned
            
            # Роялті з вторинного ринку
            secondary_volume = inflation_adjusted * secondary_sales_rate
            royalties = secondary_volume * self.config.royalty_rate
            total_royalties_collected += royalties
            
            net_supply = total_credits_minted - total_credits_burned
            money_supply_history.append(net_supply)
            
            self.money_supply.append(net_supply)
            self.burned.append(total_credits_burned)
            self.royalties.append(total_royalties_collected)
        
        return {
            'total_minted': total_credits_minted,
            'total_burned': total_credits_burned,
            'total_royalties': total_royalties_collected,
            'net_supply': total_credits_minted - total_credits_burned,
            'money_supply_history': money_supply_history,
            'inflation_rate': (total_credits_minted - total_credits_burned) / total_credits_minted if total_credits_minted > 0 else 0,
        }


class ExploitDetector:
    """Виявлення потенційних експлойтів та дисбалансів"""
    
    def __init__(self, config: EconomicConfig):
        self.config = config
        self.issues: List[Dict] = []
        
    def check_synergy_cap(self):
        """Перевірка ліміту синергії S_max"""
        max_modules = 8  # Максимум слотів
        max_synergy = 1.0 + (max_modules - 3) * self.config.synergy_bonus_per_module
        
        if max_synergy > self.config.s_max:
            self.issues.append({
                'severity': 'HIGH',
                'type': 'SYNERGY_CAP_BREACH',
                'description': f'Максимальна синергія ({max_synergy:.2f}×) перевищує S_max ({self.config.s_max}×)',
                'recommendation': f'Зменшити synergy_bonus_per_module або збільшити s_max',
            })
        else:
            print(f'✅ Synergy cap OK: {max_synergy:.2f}× <= {self.config.s_max}×')
    
    def check_difficulty_scaling(self, max_wave: int = 100):
        """Перевірка масштабування складності"""
        final_difficulty = self.config.alpha_base + (max_wave * self.config.alpha_increment)
        
        if final_difficulty > self.config.alpha_cap:
            print(f'⚠️ Difficulty capped at wave {int((self.config.alpha_cap - self.config.alpha_base) / self.config.alpha_increment)}')
        else:
            print(f'✅ Difficulty scaling OK: {final_difficulty:.2f}× at wave {max_wave}')
    
    def check_resource_inflation(
        self,
        players: int = 1000,
        acceptable_inflation: float = 0.1
    ):
        """Перевірка інфляції ресурсів"""
        analyzer = InflationAnalyzer(self.config)
        results = analyzer.simulate_economy(players=players)
        
        inflation_rate = results['inflation_rate']
        
        if inflation_rate > acceptable_inflation:
            self.issues.append({
                'severity': 'MEDIUM',
                'type': 'HIGH_INFLATION',
                'description': f'Інфляція {inflation_rate:.1%} перевищує допустиму {acceptable_inflation:.1%}',
                'recommendation': 'Збільшити burn_rate або зменшити credit_reward_base',
            })
        else:
            print(f'✅ Inflation OK: {inflation_rate:.1%} <= {acceptable_inflation:.1%}')
    
    def check_royalty_sustainability(
        self,
        secondary_market_ratio: float = 0.3
    ):
        """Перевірка сталості роялті"""
        # Роялті мають бути < 10% від загального обсягу
        effective_royalty = self.config.royalty_rate * secondary_market_ratio
        
        if effective_royalty > 0.05:
            self.issues.append({
                'severity': 'LOW',
                'type': 'HIGH_ROYALTY_BURDEN',
                'description': f'Ефективне роялті {effective_royalty:.1%} може гальмувати ринок',
                'recommendation': 'Розглянути зниження royalty_rate для стимулювання торгівлі',
            })
        else:
            print(f'✅ Royalty burden OK: {effective_royalty:.1%}')
    
    def run_all_checks(self):
        """Запуск всіх перевірок"""
        print('\n🔍 Running exploit detection checks...\n')
        self.check_synergy_cap()
        self.check_difficulty_scaling()
        self.check_resource_inflation()
        self.check_royalty_sustainability()
        
        if self.issues:
            print(f'\n⚠️ Found {len(self.issues)} potential issues:\n')
            for issue in self.issues:
                print(f"[{issue['severity']}] {issue['type']}")
                print(f"  {issue['description']}")
                print(f"  💡 {issue['recommendation']}\n")
        else:
            print('\n✅ No critical issues found!\n')
        
        return self.issues


# ────────────────────────────────────────────────────────────────────────────
# Visualization
# ────────────────────────────────────────────────────────────────────────────

def plot_economic_curves(config: EconomicConfig):
    """Візуалізація економічних кривих"""
    wave_econ = WaveEconomy(config)
    results = wave_econ.simulate_waves(num_waves=100)
    
    fig, axes = plt.subplots(2, 2, figsize=(14, 10))
    fig.suptitle('ECHOFRONT - Економічні Криві', fontsize=16)
    
    # 1. Difficulty curve
    axes[0, 0].plot(results['waves'], results['difficulty'], 'r-', linewidth=2)
    axes[0, 0].axhline(y=config.alpha_cap, color='r', linestyle='--', alpha=0.5, label=f'Cap: {config.alpha_cap}×')
    axes[0, 0].set_xlabel('Хвиля')
    axes[0, 0].set_ylabel('Складність (α)')
    axes[0, 0].set_title('Крива складності')
    axes[0, 0].grid(True, alpha=0.3)
    axes[0, 0].legend()
    
    # 2. Rewards per wave
    axes[0, 1].plot(results['waves'], results['rewards'], 'g-', linewidth=2)
    axes[0, 1].set_xlabel('Хвиля')
    axes[0, 1].set_ylabel('Винагорода')
    axes[0, 1].set_title('Винагорода за хвилю')
    axes[0, 1].grid(True, alpha=0.3)
    
    # 3. Cumulative rewards
    axes[1, 0].plot(results['waves'], results['cumulative_rewards'], 'b-', linewidth=2)
    axes[1, 0].set_xlabel('Хвиля')
    axes[1, 0].set_ylabel('Сукупна винагорода')
    axes[1, 0].set_title('Накопичена винагорода')
    axes[1, 0].grid(True, alpha=0.3)
    
    # 4. Synergy multiplier distribution
    synergy_counts = {}
    for s in results['synergy']:
        synergy_counts[s] = synergy_counts.get(s, 0) + 1
    
    axes[1, 1].bar(synergy_counts.keys(), synergy_counts.values(), color='purple', alpha=0.7)
    axes[1, 1].axvline(x=config.s_max, color='red', linestyle='--', alpha=0.7, label=f'S_max: {config.s_max}×')
    axes[1, 1].set_xlabel('Синергічний множник')
    axes[1, 1].set_ylabel('Кількість хвиль')
    axes[1, 1].set_title('Розподіл синергії')
    axes[1, 1].grid(True, alpha=0.3)
    axes[1, 1].legend()
    
    plt.tight_layout()
    plt.savefig('/workspace/echofront/tools/economic_curves.png', dpi=150)
    print('📊 Графік збережено: economic_curves.png')
    plt.close()


def plot_inflation_analysis(config: EconomicConfig, players: int = 1000):
    """Візуалізація аналізу інфляції"""
    analyzer = InflationAnalyzer(config)
    results = analyzer.simulate_economy(players=players, waves_per_player=50)
    
    fig, axes = plt.subplots(1, 2, figsize=(14, 5))
    fig.suptitle('ECHOFRONT - Аналіз Інфляції', fontsize=16)
    
    # 1. Money supply over time
    axes[0].plot(range(len(results['money_supply_history'])), results['money_supply_history'], 'b-', linewidth=2)
    axes[0].set_xlabel('Гравець')
    axes[0].set_ylabel('Грошова маса')
    axes[0].set_title('Динаміка грошової маси')
    axes[0].grid(True, alpha=0.3)
    
    # 2. Pie chart of distribution
    categories = ['Burned', 'Royalties', 'Circulating']
    values = [
        results['total_burned'],
        results['total_royalties'],
        results['net_supply'] - results['total_royalties']
    ]
    
    colors = ['orange', 'green', 'blue']
    axes[1].pie(values, labels=categories, colors=colors, autopct='%1.1f%%', startangle=90)
    axes[1].set_title(f'Розподіл кредитів (інфляція: {results["inflation_rate"]:.1%})')
    
    plt.tight_layout()
    plt.savefig('/workspace/echofront/tools/inflation_analysis.png', dpi=150)
    print('📊 Графік збережено: inflation_analysis.png')
    plt.close()


# ────────────────────────────────────────────────────────────────────────────
# Main Execution
# ────────────────────────────────────────────────────────────────────────────

def main():
    """Головна функція симуляції"""
    print('=' * 70)
    print('ECHOFRONT - Economic Simulation Tool')
    print('=' * 70)
    
    # Initialize configuration
    config = EconomicConfig()
    
    print(f'\n📋 Конфігурація:')
    print(f'  α_base = {config.alpha_base}×')
    print(f'  α_increment = {config.alpha_increment}× per wave')
    print(f'  α_cap = {config.alpha_cap}×')
    print(f'  S_max = {config.s_max}×')
    print(f'  R_base = {config.r_base}')
    print(f'  η_base = {config.eta_base}')
    print(f'  Burn rate = {config.burn_rate:.1%}')
    print(f'  Royalty rate = {config.royalty_rate:.1%}')
    
    # Run exploit detection
    detector = ExploitDetector(config)
    issues = detector.run_all_checks()
    
    # Generate visualizations
    print('\n📈 Генерація графіків...')
    plot_economic_curves(config)
    plot_inflation_analysis(config, players=500)
    
    # Export results to JSON
    wave_econ = WaveEconomy(config)
    simulation_results = wave_econ.simulate_waves(100)
    
    with open('/workspace/echofront/tools/simulation_results.json', 'w') as f:
        json.dump({
            'config': {
                'alpha_base': config.alpha_base,
                'alpha_increment': config.alpha_increment,
                'alpha_cap': config.alpha_cap,
                's_max': config.s_max,
                'r_base': config.r_base,
                'burn_rate': config.burn_rate,
                'royalty_rate': config.royalty_rate,
            },
            'simulation': {
                'final_wave': simulation_results['waves'][-1],
                'final_reward': simulation_results['rewards'][-1],
                'cumulative_reward': simulation_results['cumulative_rewards'][-1],
                'avg_difficulty': np.mean(simulation_results['difficulty']),
                'avg_synergy': np.mean(simulation_results['synergy']),
            },
            'issues_found': len(issues),
        }, f, indent=2)
    
    print('📄 Результати збережено: simulation_results.json')
    
    print('\n' + '=' * 70)
    print('✅ Симуляцію завершено!')
    print('=' * 70)


if __name__ == '__main__':
    main()
