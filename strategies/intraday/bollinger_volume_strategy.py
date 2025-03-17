import pandas as pd
from datetime import time
from strategies.base_strategy import BaseStrategy

class BollingerVolumeStrategy(BaseStrategy):
    def __init__(self,
                 session_start: time = time(0, 0),  # 24/7 trading for crypto
                 session_end: time = time(23, 59),
                 volume_threshold: float = 1.5):
        
        super().__init__(session_start, session_end)
        self.volume_threshold = volume_threshold
        self.name = "Bollinger Volume Strategy"
    
    def generate_signals(self, df: pd.DataFrame) -> pd.Series:
        """Generate trading signals based on Bollinger Bands and volume."""
        # Volume condition
        volume_condition = df['volume'] > df['Volume_SMA_20'] * self.volume_threshold
        
        # Crossover conditions
        lower_cross_down = (df['close'] < df['Bollinger_Lower_20_2']) & (df['close'].shift(1) >= df['Bollinger_Lower_20_2'].shift(1))
        upper_cross_up = (df['close'] > df['Bollinger_Upper_20_2']) & (df['close'].shift(1) <= df['Bollinger_Upper_20_2'].shift(1))
        
        # Exit conditions
        cross_back_above_lower = df['close'] > df['Bollinger_Lower_20_2']
        cross_back_below_upper = df['close'] < df['Bollinger_Upper_20_2']
        
        # Initialize signals
        signals = pd.Series(0, index=df.index)
        
        # Generate entry signals with volume condition
        signals = pd.Series(0, index=df.index)
        signals.loc[lower_cross_down & volume_condition] = 1
        signals.loc[upper_cross_up & volume_condition] = -1
        
        # Forward fill positions between entry and exit
        position = signals.copy()
        position = position.replace(0, pd.NA).fillna(method='ffill')
        
        # Apply exit conditions
        position.loc[(position == 1) & cross_back_above_lower] = 0
        position.loc[(position == -1) & cross_back_below_upper] = 0
        
        # Fill remaining NAs with 0
        position = position.fillna(0)
        
        return position 