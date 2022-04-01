// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import './AtlasMineV1.sol';

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
}
