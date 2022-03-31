//SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./ICDAO.sol";

contract DAO is AccessControl, ReentrancyGuard {
    using Counters for Counters.Counter;
    Counters.Counter private proposalsCounter;

    bytes32 private constant CHAIRMAN_ROLE = keccak256("CHAIRMAN_ROLE");

    IERC20 private voteToken;
    uint256 private minimumQuorum;
    uint256 private debatingPeriodDuration;
    uint256 private minimumVotes;

    event credited(address indexed user, uint256 amount);
    event withdrawn(address indexed user, uint256 amount);
    event proposalAdded(uint256 indexed id, uint256 time);
    event voted(address indexed user, uint256 indexed proposal, bool answer);

    mapping(address => uint256) private _balances;
    mapping(uint256 => Proposal) private _proposals;
    mapping(address => uint256) private _userToEndTime;
    mapping(address => mapping(uint256 => bool)) private _isVoted;

    struct Proposal {
        address targetContract;
        bytes encodedMessage;
        uint256 EndTime;
        uint256 consenting;
        uint256 dissenters;
        uint256 usersVoted;
        uint256 isFinished; // 0 - Not finished, 1 - finished
        string description;
    }

    constructor(
        address _voteToken,
        uint256 _minimumQuorum,
        uint256 _debatingPeriodDuration,
        uint256 _minimumVotes
    ) {
        _grantRole(CHAIRMAN_ROLE, msg.sender);
        voteToken = IERC20(_voteToken);
        minimumQuorum = _minimumQuorum;
        debatingPeriodDuration = _debatingPeriodDuration;
        minimumVotes = _minimumVotes;
    }

    function deposit(uint256 amount) external {
        voteToken.transferFrom(msg.sender, address(this), amount);
        _balances[msg.sender] += amount;
        emit credited(msg.sender, amount);
    }

    function addProposal(
        address _targetContract,
        bytes calldata signature,
        string calldata description
    ) external onlyRole(CHAIRMAN_ROLE) {
        uint256 current = proposalsCounter.current();
        _proposals[current] = Proposal(
            _targetContract,
            signature,
            block.timestamp + debatingPeriodDuration,
            0,
            0,
            0,
            0,
            description
        );
        proposalsCounter.increment();
        emit proposalAdded(current, block.timestamp);
    }

    function vote(uint256 proposalId, bool answer) external nonReentrant {
        require(
            _proposals[proposalId].EndTime < block.timestamp,
            "DAO: The voting is already over"
        );
        require(
            _isVoted[msg.sender][proposalId] == false,
            "DAO: You have already voted in this proposal"
        );

        answer
            ? _proposals[proposalId].consenting += _balances[msg.sender]
            : _proposals[proposalId].dissenters += _balances[msg.sender];

        _isVoted[msg.sender][proposalId] = true;
        _userToEndTime[msg.sender] = _proposals[proposalId].EndTime;

        emit voted(msg.sender, proposalId, answer);
    }

    function withdraw(uint256 amount) external {
        require(
            _balances[msg.sender] >= amount,
            "DAO: Insufficient funds on the balance"
        );
        require(
            _userToEndTime[msg.sender] < block.timestamp,
            "DAO: The last vote you participated in hasn't ended yet"
        );
        _balances[msg.sender] -= amount;
        emit withdrawn(msg.sender, amount);
    }

    function getProposalById(uint256 id)
        external
        view
        returns (Proposal memory)
    {
        return _proposals[id];
    }

    function getToken() external view returns (address) {
        return address(voteToken);
    }

    function getMinQuorum() external view returns (uint256) {
        return minimumQuorum;
    }

    function getDebatePeriod() external view returns (uint256) {
        return debatingPeriodDuration;
    }

    function getMinVotes() external view returns (uint256) {
        return minimumVotes;
    }

    function getBalance(address user) external view returns (uint256) {
        return _balances[user];
    }
}
