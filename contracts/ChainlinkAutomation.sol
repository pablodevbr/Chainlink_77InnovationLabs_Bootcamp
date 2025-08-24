// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/*///////////////////////////////////
            Imports
///////////////////////////////////*/
import { AutomationCompatibleInterface } from "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
    *@title Chainlink Automation contract example
    *@notice A balance monitor contract leveraging Chainlink Automation to monitor and fund an Ethereum address
*/
contract ChainlinkAutomation is AutomationCompatibleInterface, Ownable {

    /*///////////////////////////////////
                variables
    ///////////////////////////////////*/
    ///@notice magic number removal
    uint56 constant MIN_BALANCE = 1*10**16;
    uint64 constant AMOUNT_TO_TRANSFER = 1*10**17;

    ///@notice storage variable to store the Chainlink's forwarder address
    address internal s_forwarderAddress;
    ///@notice storage variable to store the address to be funded
    address internal s_fundingTarget;

    /*///////////////////////////////////
                Events
    ///////////////////////////////////*/
    ///@notice event emitted when the forwarder address is updated
    event ChainlinkAutomation_ForwarderAddressUpdated(address newForwarderAddress);
    ///@notice event emitted when funds are received by the contract
    event ChainlinkAutomation_FundsAdded(uint256 amount, uint256 contractBalance, address sender);
    ///@notice event emitted when the target is updated
    event ChainlinkAutomation_TargetAddressUpdated(address fundingTarget);
    ///@notice event emitted when contract funds are withdrawn
    event ChainlinkAutomation_FundsWithdrawn(uint256 amount, address receiver);
    ///@notice event emitted when the target is funded
    event ChainlinkAutomation_TopUpSucceeded(uint256 valueTransferred, uint256 contractBalance, uint256 targetBalance);

    /*///////////////////////////////////
                Errors
    ///////////////////////////////////*/
    ///@notice error emitted when an invalid address is used
    error ChainlinkAutomation_InvalidAddress(address newAddress);
    ///@notice error emitted when an unallowed address tries to perform upkeep
    error ChainlinkAutomation_OnlyForwarder();
    ///@notice error emitted when the funding process fails
    error ChainlinkAutomation_TopUpFailed(bytes data);

    /*///////////////////////////////////
                Modifiers
    ///////////////////////////////////*/
    modifier onlyForwarder() {
        if (msg.sender != s_forwarderAddress) {
            revert ChainlinkAutomation_OnlyForwarder();
        }
        _;
    }

    /*///////////////////////////////////
                constructor
    ///////////////////////////////////*/
    constructor(address _target, address _owner) Ownable(_owner){
        s_fundingTarget = _target;
    }

    /*///////////////////////////////////
            Receive&Fallback
    ///////////////////////////////////*/
    /**
     * @notice Function to receive funds
     */
    receive() external payable {
        emit ChainlinkAutomation_FundsAdded(msg.value, address(this).balance, msg.sender);
    }

    /*///////////////////////////////////
                external
    ///////////////////////////////////*/
    /**
     * @notice Get a list of addresses that are underfunded and return a payload compatible with the Chainlink Automation Network
     * @return upkeepNeeded_ signals if upkeep is needed
     * @return performData_ is an ABI-encoded list of addresses that need funds
     * @dev onlyForwarder removed to automation execution
     */
    function checkUpkeep(bytes calldata) external view override returns(bool upkeepNeeded_, bytes memory performData_){
        if(s_fundingTarget.balance < MIN_BALANCE){
            upkeepNeeded_ = true;
            ///IMPROVEMENT encode isn't necessary in this example
            performData_ = abi.encode(s_fundingTarget);
        }
    }

    /**
     * @notice Called by Chainlink Automation Node to send funds to underfunded addresses
     */
    function performUpkeep( bytes calldata /*_performData*/) external override onlyForwarder  {
        ///IMPROVEMENT decode isn't necessary in this example
        // address target = abi.decode(_performData, (address));
        _topUp();
    }
    
    /**
     * @notice Withdraws the contract balance
     * @param _amount The amount of eth (in wei) to withdraw
     * @param _receiver The address to pay
     * @dev controlled input that allows the usage of .transfer
     */
    function withdraw(uint256 _amount, address payable _receiver) external onlyOwner {
        if(_receiver == address(0)) revert ChainlinkAutomation_InvalidAddress(_receiver);

        emit ChainlinkAutomation_FundsWithdrawn(_amount, _receiver);

        _receiver.transfer(_amount);
    }

    /**
     * @notice Sets the upkeep's unique forwarder address
     * for upkeeps in Automation versions 2.0 and later
     * @param _forwarderAddress the Chainlink Automation provided address
     */
    function setForwarderAddress(address _forwarderAddress) external onlyOwner {
        if(_forwarderAddress == address(0)) revert ChainlinkAutomation_InvalidAddress(_forwarderAddress);

        emit ChainlinkAutomation_ForwarderAddressUpdated(_forwarderAddress);

        s_forwarderAddress = _forwarderAddress;
    }

    /**
        *@notice Set the target to be funded
        *@param _fundingTarget the target address
    */
    function setFundingTarget(address _fundingTarget) external onlyOwner{
        if(_fundingTarget == address(0)) revert ChainlinkAutomation_InvalidAddress(_fundingTarget);

        emit ChainlinkAutomation_TargetAddressUpdated(_fundingTarget);

        s_fundingTarget = _fundingTarget;
    }

    /*///////////////////////////////////
                   internal
    ///////////////////////////////////*/
    /**
     * @notice Send funds to the addresses provided
     */
    function _topUp() internal {
        ///IMPROVEMENT best practice CEI alter this event bofore the call 
        emit ChainlinkAutomation_TopUpSucceeded(AMOUNT_TO_TRANSFER, address(this).balance, s_fundingTarget.balance);

        (bool success, bytes memory data) = s_fundingTarget.call{value: AMOUNT_TO_TRANSFER}("");
        if(!success) revert ChainlinkAutomation_TopUpFailed(data);
    }
}