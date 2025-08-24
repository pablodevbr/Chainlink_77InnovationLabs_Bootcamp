// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/*///////////////////////////////////
            Imports
///////////////////////////////////*/
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract ChainlinkDataFeeds is Ownable{

    /*///////////////////////////////////
                Variables
    ///////////////////////////////////*/
    enum ContractStatus{
        valid,
        paused,
        terminated
    }
    ContractStatus s_contractStatus;

    enum WorkStatus{
        working,
        endWorking
    }
    WorkStatus s_workStatus;

    ///@notice immutable variable to store the Feeds Address - DON'T DO THIS IN PRODUCTION
    AggregatorV3Interface immutable i_feed;
    ///@notice immutable variable to store employee address
    address immutable i_employee;

    ///@notice constant variable to store the Feed's heartbeat
    uint256 constant HEARTBEAT = 3600;
    ///@notice constant variable to store the minimum rate per hour value
    uint256 public constant MIN_RATE = 750_000_000; //$ 7.50 using Oracle Decimals
    ///@notice constant to store the precision multiplier
    uint256 public constant PRECISION_HELPER = 1e18;

    /**
        @notice rate per hour using oracle decimals(8)
        @dev IMPROVEMENT: for security reasons it's better to use internal instead of public for state variables
    */
    uint256 internal s_rate;
    /**
        @notice variable to store the total unpaid worked hours
        @dev IMPROVEMENT: for security reasons it's better to use internal instead of public for state variables
    */
    uint256 internal s_unpaidWorkTime;
    ///@notice variable to store the current work session
    uint256 internal s_currentWorkingSession;

    /*///////////////////////////////////
                Events
    ///////////////////////////////////*/
    ///@notice event emitted when the rate is updated
    event ChainlinkDataFeeds_RatePerHourUpdated(uint256 oldRate, uint256 newRate);
    ///@notice event emitted when the working journey start
    event ChainlinkDataFeeds_WorkingJourneyStarted(uint256 startTime);
    ///@notice event emitted when the working journey is ended
    event ChainlinkDataFeeds_WorkingJourneyFinished(uint256 endTime, uint256 timeWorked);

    /*///////////////////////////////////
                Errors
    ///////////////////////////////////*/
    ///@notice error emitted when the rate per hour is too low
    error ChainlinkDataFeeds_RatePerHourIsToLow(uint256 newRate, uint256 rateMin);
    ///@notice error emitted when the caller is not the employee
    error ChainlinkDataFeeds_IsNotEmployee(address caller, address employee);
    ///@notice error emitted when the contract is paused and the employee shouldn't start working
    error ChainlinkDataFeeds_ThisContractIsPaused(ContractStatus status);
    ///@notice error emitted when the contract was terminated
    error ChainlinkDataFeeds_ThisContractWasTerminated(ContractStatus contractStatus);
    ///@notice error emitted when the working journey was already started
    error ChainlinkDataFeeds_AlreadyStarted(WorkStatus workStatus);
    ///@notice error emitted when the price feeds answer is stale
    error ChainlinkDataFeeds_StalePrice();
    ///@notice error emitted when the employee tries to end a not started journey
    error ChainlinkDataFeeds_WorkingJourneyNotStarted(WorkStatus status);
    ///@notice error emitted when the employee salary was already paid
    error ChainlinkDataFeeds_NothingLeftToPay();
    ///@notice error emitted when the transfer fails
    error ChainlinkDataFeeds_TransferFailed(bytes data);
    ///@notice error emitted when the Feeds price is wrong
    error ChainlinkDataFeeds_WrongPrice();

    /*///////////////////////////////////
                Modifiers
    ///////////////////////////////////*/
    modifier onlyEmployee(){
        if(msg.sender != i_employee) revert ChainlinkDataFeeds_IsNotEmployee(msg.sender, i_employee);
        _;
    }

    /*///////////////////////////////////
                Functions
    ///////////////////////////////////*/
    receive() external payable{}

    /*///////////////////////////////////
                constructor
    ///////////////////////////////////*/
    constructor(
        address _feeds,
        address _owner,
        address _employee
    ) Ownable(_owner){
        i_feed = AggregatorV3Interface(_feeds);
        i_employee = _employee;
        s_workStatus = WorkStatus.endWorking;
    }

    /*///////////////////////////////////
                external
    ///////////////////////////////////*/
    /**
        *@notice Function for employee to start the working journey
        *@dev only the employee can call it
    */
    function startWork() external onlyEmployee {
        if(s_contractStatus == ContractStatus.paused) revert ChainlinkDataFeeds_ThisContractIsPaused(s_contractStatus);
        if(s_contractStatus == ContractStatus.terminated) revert ChainlinkDataFeeds_ThisContractWasTerminated(s_contractStatus);
        if(s_workStatus == WorkStatus.working) revert  ChainlinkDataFeeds_AlreadyStarted(s_workStatus);

        s_workStatus = WorkStatus.working;
        s_currentWorkingSession = block.timestamp;

        emit ChainlinkDataFeeds_WorkingJourneyStarted(block.timestamp);
    }

    /**
        *@notice Function for Employee to end the working journey
        *@dev only the employee should be able to end the journey
    */
    function endWork() external onlyEmployee {
        if(s_workStatus != WorkStatus.working) revert ChainlinkDataFeeds_WorkingJourneyNotStarted(WorkStatus.working);

        s_workStatus = WorkStatus.endWorking;

        uint256 unpaidTimeForCurrentSession = block.timestamp - s_currentWorkingSession;

        s_unpaidWorkTime = s_unpaidWorkTime + unpaidTimeForCurrentSession;

        emit ChainlinkDataFeeds_WorkingJourneyFinished(block.timestamp, unpaidTimeForCurrentSession);
    }

    /**
        *@notice administrative function to updated the employee rate perHour
        *@param _newRate the rate to calculate employee salary perHour
    */
    function setRate(uint256 _newRate) external onlyOwner{
        if(_newRate < MIN_RATE) revert ChainlinkDataFeeds_RatePerHourIsToLow(_newRate, MIN_RATE);

        uint256 oldRate = s_rate;
        s_rate = _newRate;

        emit ChainlinkDataFeeds_RatePerHourUpdated(oldRate, _newRate);
    }

    /**
        *@notice function to end and employee contract
    */
    function endContract() external onlyOwner {
        s_contractStatus = ContractStatus.terminated;
        payEmployee();
    }

    /*///////////////////////////////////
                public
    ///////////////////////////////////*/
    /**
        *@notice function to pay the employee salary
    */
    function payEmployee() public onlyOwner {
        if(s_unpaidWorkTime == 0) revert ChainlinkDataFeeds_NothingLeftToPay();

        uint256 amountToPay = _calculateSalary();
        s_unpaidWorkTime = 0;

        _transferAmount(amountToPay);
    }

    /**
        *@notice internal function to perform eth transfers
        *@param _value the amount to be transferred
    */
    function _transferAmount(uint256 _value) internal {
        (bool success, bytes memory data) = i_employee.call{value: _value}("");
        if(!success) revert ChainlinkDataFeeds_TransferFailed(data);
    }

    /**
        *@notice Function to query the most recent price for a feed
        *@return answer_ Feed's received answer
        *@dev should be only called internally
    */
    function _getFeedLastAnswer() internal view returns(int answer_){
        uint256 updatedAt;

        ///@notice handle it with a try-catch block
        (
                ,
                answer_,
                ,
                updatedAt,

        ) = i_feed.latestRoundData();
        
        ///@notice validation example
        if(block.timestamp - updatedAt > HEARTBEAT) revert ChainlinkDataFeeds_StalePrice();
        if(answer_ <= 0) revert ChainlinkDataFeeds_WrongPrice();
    }

    /*///////////////////////////////////
            View & Pure
    ///////////////////////////////////*/
    /**
        *@notice internal function to calculate the employee salary
        *@return salary_ the amount to be paid
        *@dev the returned value must be based on 18 decimals.
    */
    function _calculateSalary() internal view returns(uint256 salary_){
        uint256 workedHours = s_unpaidWorkTime * PRECISION_HELPER;

        ///@notice convert on value/hours
        uint256 totalInUSD = (workedHours * s_rate) / 3600;
        
        salary_ = totalInUSD / uint256(_getFeedLastAnswer());
    }
}