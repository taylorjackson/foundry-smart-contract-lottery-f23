// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

/**
 * @title Raffle
 * @dev Raffle contract
 * @author Taylor Jackson
 */
contract Raffle is VRFConsumerBaseV2 {
    error Raffle__NotEnoughEthToEnterError();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpKeepNotNeeded(
        uint256 currentBalance,
        uint256 numPlayers,
        uint256 state
    );

    enum RaffleState {
        OPEN,
        CLOSED,
        CALCULATING_WINNER
    }

    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    RaffleState private s_raffleState;
    uint256 private immutable i_enteranceFee;
    address payable[] private s_participants;
    uint256 private immutable i_interval;
    uint256 private s_lastWinnerTimestamp;
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callBackGasLimit;
    address private s_mostRecentWinner;

    event EnteredRaffle(address indexed player);
    event PickedWinner(address indexed winner);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callBackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinator) {
        i_enteranceFee = entranceFee;
        i_interval = interval;
        s_lastWinnerTimestamp = block.timestamp;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callBackGasLimit = callBackGasLimit;
        s_raffleState = RaffleState.OPEN;
    }

    function enterRaffle() external payable {
        if (msg.value < i_enteranceFee) {
            revert Raffle__NotEnoughEthToEnterError();
        }

        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }

        s_participants.push(payable(msg.sender));
        emit EnteredRaffle(msg.sender);
    }

    /**
     * @dev This is the function that the chainlink automation nodes call to see if it's time to perform an upkeep
     */
    function checkUpKeep(
        bytes memory /* checkData */
    ) public view returns (bool upkeepNeeded, bytes memory /* performData */) {
        bool timeHasPassed = (block.timestamp - s_lastWinnerTimestamp) >=
            i_interval;
        bool isOpen = RaffleState.OPEN == s_raffleState;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_participants.length > 0;

        upkeepNeeded = timeHasPassed && isOpen && hasBalance && hasPlayers;
        return (upkeepNeeded, bytes(""));
    }

    function performUpKeep(bytes calldata /* performData */) external {
        (bool upkeepNdeed, ) = checkUpKeep("");
        if (!upkeepNdeed) {
            revert Raffle__UpKeepNotNeeded(
                address(this).balance,
                s_participants.length,
                uint256(s_raffleState)
            );
        }

        s_raffleState = RaffleState.CALCULATING_WINNER;
        i_vrfCoordinator.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callBackGasLimit,
            NUM_WORDS
        );
    }

    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal override {
        uint256 winnerIndex = randomWords[0] % s_participants.length;
        s_mostRecentWinner = s_participants[winnerIndex];
        (bool success, ) = s_mostRecentWinner.call{
            value: address(this).balance
        }("");

        if (!success) {
            revert Raffle__TransferFailed();
        }

        s_participants = new address payable[](0);
        s_lastWinnerTimestamp = block.timestamp;
        s_raffleState = RaffleState.OPEN;

        emit PickedWinner(s_mostRecentWinner);
    }

    function getEntranceFee() external view returns (uint256) {
        return i_enteranceFee;
    }

    function getParticipants()
        external
        view
        returns (address payable[] memory)
    {
        return s_participants;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getParticipant(uint256 index) external view returns (address) {
        return s_participants[index];
    }
}
