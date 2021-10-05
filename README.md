# ERC20 & ERC721 farming pools

User stakes ERC20 for 2 weeks, 1 month, or 3 months. The longer the stake, higher the returns. When mine ends, all deposits are unlocked.
- 2 week: 20% weighting boost
- 1 month: 50% boost
- 3 month: 200% boost

The mine works like this.
-When less than 20% of the total ERC20 supply is being staked on the mine, the mine is off.
-When 20% of the total supply is staked on the mine, it operates at 50% capacity (each block reward is 50% of what the max block reward is)
-30% staking --> 60% capacity
-40% --> 80%
-50% --> 90%
-60% and above --> 100% capacity

- Mine is funded with fixed amount of reward token upfront and works for 3 months. After 3 months, whatever reward token is left in the pool is burnt or stays locked forever.
- Mine has a kill switch that allows owner to stop the mine and withdraw unearned reward token.
- Each time someone claims the reward, 10% is sent to treasure holders pool and distributed between current stakers of erc721 in treasure pool.
- Treasure pool stakers can get boosted depending on rarity of erc721 token staked

This is done with two staking contracts, one constantly supplying token to the other.
`TreasuryMine` accepts ERC20 stake and distributes rewards to stakers and to the `TreasuryStake`. `TreasuryStake` accepts ERC721 stake and distributes rewards every time it receives it from `TreasuryMine` to current stakers.
