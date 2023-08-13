// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract Betting is Ownable, AccessControl {
    using SafeMath for uint256;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    IERC20 public token;
    uint256 public gameId = 0;
    uint256 public timeToBet = 10 minutes;
    bool public gameStarted = false;
    mapping(uint256 => Game) public games;

    struct Game {
        uint256 id;
        uint256 startTime;
        uint256 bettingEndTime;
        mapping(address => uint256) betOnFighter1;
        address[] numberOfBetOnFighter1;
        uint256 totalBetOnFighter1;
        mapping(address => uint256) betOnFighter2;
        address[] numberOfBetOnFighter2;
        uint256 totalBetOnFighter2;
        mapping(address => bool) isBettor;
        uint256 totalBet;
        uint256 winner;
    }

    event GameStarted(uint256 gameId, uint256 startTime, uint256 endTime);
    event GameEnded(uint256 gameId, uint256 winner);

    constructor(address _token, address[] memory admins) {
        token = IERC20(_token);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        for (uint256 i = 0; i < admins.length; i++) {
            _setupRole(ADMIN_ROLE, admins[i]);
        }
    }

    /**
     * @dev Allows admins to set the time to bet.
     * @param _timeToBet The time to bet.
     */
    function setTimeToBet(uint256 _timeToBet) external {
        require(
            hasRole(ADMIN_ROLE, msg.sender) || msg.sender == owner(),
            "You are not an admin"
        );
        timeToBet = _timeToBet;
    }

    /**
     * @dev Allows admins to start a game.
     */
    function startGame() external {
        require(
            hasRole(ADMIN_ROLE, msg.sender) || msg.sender == owner(),
            "You are not an admin"
        );
        require(!gameStarted, "Game has already started");
        gameStarted = true;
        gameId++;
        games[gameId].id = gameId;
        games[gameId].startTime = block.timestamp;
        games[gameId].bettingEndTime = block.timestamp + timeToBet;
        games[gameId].totalBetOnFighter1 = 0;
        games[gameId].totalBetOnFighter2 = 0;
        games[gameId].totalBet = 0;
        games[gameId].winner = 0;

        emit GameStarted(gameId, block.timestamp, block.timestamp + timeToBet);
    }

    /**
     * @dev Allows admins to stop players from betting.
     * This function is used in case of an emergency.
     */
    function emergencyStopBets() external {
        require(
            hasRole(ADMIN_ROLE, msg.sender) || msg.sender == owner(),
            "You are not an admin"
        );
        require(gameStarted, "Game has not started");
        games[gameId].bettingEndTime = block.timestamp;
    }

    /**
     * @dev Allows players to place a bet on a either fighter 1 or fighter 2.
     * @param _bet The amount bet.
     * @param fighter The fighter to bet on.
     */
    function bet(uint256 _bet, uint256 fighter) external {
        require(gameStarted, "Game has not started");
        require(
            block.timestamp < games[gameId].bettingEndTime,
            "Betting has ended"
        );
        require(!games[gameId].isBettor[msg.sender], "You already bet");
        require(_bet != 0, "Amount cannot be 0");
        require(fighter == 1 || fighter == 2, "Fighter must be 1 or 2");

        uint256 allowance = token.allowance(msg.sender, address(this));
        require(
            allowance >= _bet,
            "You need to approve the token transfer first"
        );

        bool success = token.transferFrom(msg.sender, address(this), _bet);
        require(success, "Token transfer failed");

        // Convert _bet to smallest unit (wei) of the token
        uint256 betAmountWei = _bet * (10 ** 10);

        games[gameId].totalBet += betAmountWei;
        games[gameId].isBettor[msg.sender] = true;

        if (fighter == 1) {
            games[gameId].betOnFighter1[msg.sender] = betAmountWei;
            games[gameId].numberOfBetOnFighter1.push(msg.sender);
            games[gameId].totalBetOnFighter1 += betAmountWei;
        } else {
            games[gameId].betOnFighter2[msg.sender] = betAmountWei;
            games[gameId].numberOfBetOnFighter2.push(msg.sender);
            games[gameId].totalBetOnFighter2 += betAmountWei;
        }
    }

    /**
     * @dev Allows admins to end a game.
     * @param _winner The fighter who won the game.
     */
    function endGame(uint256 _winner) external {
        require(
            hasRole(ADMIN_ROLE, msg.sender) || msg.sender == owner(),
            "You are not an admin"
        );
        require(gameStarted, "Game has not started");
        require(_winner == 1 || _winner == 2, "Winner must be 1 or 2");

        if (_winner == 1) {
            for (
                uint256 i = 0;
                i < games[gameId].numberOfBetOnFighter1.length;
                i++
            ) {
                address bettor = games[gameId].numberOfBetOnFighter1[i];
                uint256 amount = games[gameId].betOnFighter1[bettor];
                uint256 winnings = (amount * games[gameId].totalBet) /
                    games[gameId].totalBetOnFighter1;
                winnings /= 10 ** 10; // Convert back to 8-decimal token
                bool success = token.transfer(bettor, winnings);
                require(success, "Token transfer failed");
            }
        } else {
            for (
                uint256 i = 0;
                i < games[gameId].numberOfBetOnFighter2.length;
                i++
            ) {
                address bettor = games[gameId].numberOfBetOnFighter2[i];
                uint256 amount = games[gameId].betOnFighter2[bettor];
                uint256 winnings = (amount * games[gameId].totalBet) /
                    games[gameId].totalBetOnFighter2;
                winnings /= 10 ** 10; // Convert back to 8-decimal token
                bool success = token.transfer(bettor, winnings);
                require(success, "Token transfer failed");
            }
        }

        games[gameId].winner = _winner;
        gameStarted = false;

        emit GameEnded(gameId, _winner);
    }

    /**
     * @dev Returns the game info.
     * @param _gameId The game id.
     */
    function getGameInfo(
        uint256 _gameId
    )
        external
        view
        returns (uint256, uint256, uint256, uint256, uint256, uint256)
    {
        return (
            games[_gameId].id,
            games[_gameId].startTime,
            games[_gameId].bettingEndTime,
            games[_gameId].totalBetOnFighter1,
            games[_gameId].totalBetOnFighter2,
            games[_gameId].totalBet
        );
    }

    /**
     * @dev Returns the last game id.
     */
    function getLastGameId() external view returns (uint256) {
        return gameId;
    }

    /**
     * @dev Returns if the user is a bettor in this game.
     * @param _bettor The bettor address.
     */
    function isBettor(
        address _bettor
    ) external view returns (bool) {
        return games[gameId].isBettor[_bettor];
    }

    /**
     * @dev Returns players who bet on fighter 1 for a specified game.
     * @param _gameId The game id.
     */
    function getBetOnFighter1(
        uint256 _gameId
    ) external view returns (address[] memory) {
        return games[_gameId].numberOfBetOnFighter1;
    }

    /**
     * @dev Returns players who bet on fighter 1 for a specified game.
     * @param _gameId The game id.
     */
    function getBetOnFighter2(
        uint256 _gameId
    ) external view returns (address[] memory) {
        return games[_gameId].numberOfBetOnFighter2;
    }

    /**
     * @dev Allows owner to withdraw a certain amount of token from the contract.
     * @param _amount The amount to withdraw.
     */
    function withdrawAmount(uint256 _amount) external onlyOwner {
        uint256 balance = token.balanceOf(address(this));
        require(balance >= _amount, "Insufficient balance");
        bool success = token.transfer(msg.sender, _amount);
        require(success, "Token transfer failed");
    }

    /**
     * @dev Allows owner to withdraw all token from the contract.
     */
    function withdraw() public onlyOwner {
        uint256 balance = token.balanceOf(address(this));
        bool success = token.transfer(msg.sender, balance);
        require(success, "Token transfer failed");
    }
}
