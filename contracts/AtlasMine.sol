// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import './AtlasMineV1.sol';

/// @notice Contract is using an admin role to manage its configuration. Admin role is assigned to a multi-sig
/// wallet controlled by trusted team members. Admin role aka ATLAS_MINE_ADMIN_ROLE, as initialized during init()
/// to msg.sender can:
/// • Add/Remove addresses to excludedAddresses, which impacts the utilization calculation, by calling
///   addExcludedAddress() and removeExcludedAddress(), respectively.
/// • Set/Unset an arbitrary override value for the value returned by utilization(), by calling
///   setUtilizationOverride().
/// • Change at any time the magic token address, which is set during init(), to an arbitrary one, by calling
///   setMagicToken().
/// • Set treasure to an arbitrary address (including address(0), in which case treasure staking/unstaking is
///   disabled), by calling setTreasure().
/// • Set legion to an arbitrary address (including address(0), in which case legion staking/unstaking is disabled),
///   by calling setLegion().
/// • Set legionMetadataStore to an arbitrary address (used for legion 1:1 checking and legion nft boost computation),
///   by calling setLegionMetadataStore().
/// • Re-set the legionBoostMatrix array to arbitrary values, by calling setLegionBoostMatrix().
/// • Set/Unset the emergency unlockAll state, by calling toggleUnlockAll().
/// • Withdraw all undistributed rewards to an arbitrary address, by calling withdrawUndistributedRewards().
contract AtlasMine is AtlasMineV1 {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function calcualteVestedPrincipal(address _user, uint256 _depositId)
        public
        view
        virtual
        override
        returns (uint256 amount)
    {
        UserInfo storage user = userInfo[_user][_depositId];
        Lock _lock = user.lock;
        uint256 originalDepositAmount = user.originalDepositAmount;

        uint256 vestingEnd = user.lockedUntil + getVestingTime(_lock);
        uint256 vestingBegin = user.lockedUntil;

        if (block.timestamp >= vestingEnd || unlockAll) {
            amount = user.depositAmount;
        } else if (block.timestamp > vestingBegin) {
            uint256 amountVested = originalDepositAmount * (block.timestamp - vestingBegin) / (vestingEnd - vestingBegin);
            uint256 amountWithdrawn = originalDepositAmount - user.depositAmount;
            if (amountWithdrawn < amountVested) {
                amount = amountVested - amountWithdrawn;
            }
        }
    }

    function isLegion1_1(uint256 _tokenId) public view virtual override returns (bool) {
        ILegionMetadataStore.LegionMetadata memory metadata =
            ILegionMetadataStore(legionMetadataStore).metadataForLegion(_tokenId);
        return
            metadata.legionGeneration == ILegionMetadataStore.LegionGeneration.GENESIS
            && metadata.legionRarity == ILegionMetadataStore.LegionRarity.LEGENDARY;
    }
}
