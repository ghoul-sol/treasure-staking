// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.11;
//
// import '@openzeppelin/contracts/access/AccessControlEnumerable.sol';
//
// import '../../interfaces/ILegionMetadataStore.sol';
// import '../../interfaces/IStakingRules.sol';
//
// import "../HarvesterError.sol";
//
// contract ExtractorStakingRules is IStakingRules, AccessControlEnumerable {
//     bytes32 public constant STAKING_RULES_ADMIN_ROLE = keccak256("STAKING_RULES_ADMIN_ROLE");
//
//     uint256 public staked;
//     uint256 public maxStakeable;
//     uint256 public lifetime;
//
//     event MaxStakeableUpdate(uint256 maxStakeable);
//
//     constructor(address _admin) {
//         // TODO: setup roles
//         _setRoleAdmin(STAKING_RULES_ADMIN_ROLE, STAKING_RULES_ADMIN_ROLE);
//         _grantRole(STAKING_RULES_ADMIN_ROLE, _admin);
//     }
//
//     function canStake(address, address, uint256, uint256)
//         external
//         override
//         onlyRole(STAKING_RULES_ADMIN_ROLE)
//     {
//         staked++;
//
//         if (staked > maxStakeable) revert MaxStakeable();
//     }
//
//     function canUnstake(address, address, uint256, uint256) external pure override {}
//
//     function getBoost(address, address, uint256, uint256) external pure override returns (uint256) {
//         return 0;
//     }
//
//     // ADMIN
//
//     function setMaxStakeable(uint256 _maxStakeable) external onlyRole(STAKING_RULES_ADMIN_ROLE) {
//         maxStakeable = _maxStakeable;
//         emit MaxStakeableUpdate(_maxStakeable);
//     }
// }
