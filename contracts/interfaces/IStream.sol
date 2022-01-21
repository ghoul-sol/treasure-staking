// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

interface IStream {
    function preRateUpdate() external;
    function postRateUpdate() external;
}
