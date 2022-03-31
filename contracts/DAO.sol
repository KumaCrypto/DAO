//SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "./ICDAO.sol";

contract DAO is AccessControl, ReentrancyGuard {
    using Counters for Counters.Counter;
    Counters.Counter private proposalsCounter;
    Counters.Counter private activeUsers;

    bytes32 private constant CHAIRMAN_ROLE = keccak256("CHAIRMAN_ROLE");

    IERC20 private voteToken;
    uint256 private minimumQuorum;
    uint256 private debatingPeriodDuration;
    uint256 private minimumVotes;

    event Credited(address indexed user, uint256 amount);
    event TokensWithdrawn(address indexed user, uint256 amount);
    event ProposalAdded(uint256 indexed id, uint256 time);
    event Voted(address indexed user, uint256 indexed proposal, bool answer);
    event Received(address indexed sender, uint256 amount);
    event ETHWithdrawn(address indexed receiver, uint256 indexed amount);
    event Finished(
        uint256 indexed ProposalId,
        bool status,
        address indexed targetContract,
        uint256 votesAmount,
        uint256 usersVoted
    );

    struct user {
        uint256 balance;
        uint256 lastVoteEndTime;
        mapping(uint256 => bool) _isVoted;
    }

    struct Proposal {
        address targetContract;
        bytes encodedMessage;
        uint256 EndTime;
        uint256 consenting;
        uint256 dissenters;
        uint256 usersVoted;
        bool isFinished;
        string description;
    }

    mapping(address => user) private _users;
    mapping(uint256 => Proposal) private _proposals;

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
        _users[msg.sender].balance += amount;
        activeUsers.increment();
        emit Credited(msg.sender, amount);
    }

    function addProposal(
        address _targetContract,
        bytes calldata signature,
        string calldata description
    ) external onlyRole(CHAIRMAN_ROLE) nonReentrant {
        uint256 current = proposalsCounter.current();

        _proposals[current] = Proposal(
            _targetContract,
            signature,
            block.timestamp + debatingPeriodDuration,
            0,
            0,
            0,
            false,
            description
        );

        proposalsCounter.increment();
        emit ProposalAdded(current, block.timestamp);
    }

    function vote(uint256 proposalId, bool answer) external nonReentrant {
        require(_users[msg.sender].balance > 0, "DAO: No tokens on balance");
        require(
            _proposals[proposalId].EndTime > block.timestamp,
            "DAO: The voting is already over or does not exist"
        );
        require(
            _users[msg.sender]._isVoted[proposalId] == false,
            "DAO: You have already voted in this proposal"
        );

        answer
            ? _proposals[proposalId].consenting += _users[msg.sender].balance
            : _proposals[proposalId].dissenters += _users[msg.sender].balance;

        _users[msg.sender]._isVoted[proposalId] = true;
        _users[msg.sender].lastVoteEndTime = _proposals[proposalId].EndTime;
        _proposals[proposalId].usersVoted++;

        emit Voted(msg.sender, proposalId, answer);
    }

    function finishProposal(uint256 proposalId) external nonReentrant {
        Proposal storage proposal = _proposals[proposalId];

        require(
            proposal.EndTime <= block.timestamp,
            "DAO: Voting time is not over yet"
        );
        require(proposal.isFinished == false, "DAO: Voting has already ended");

        uint256 votesAmount = proposal.consenting + proposal.dissenters;
        uint256 votersPercentage = ((activeUsers.current() * 10**3) / 100) *
            minimumQuorum;

        uint256 users = proposal.usersVoted * 10**3;
        if (votesAmount >= minimumVotes && users >= votersPercentage) {
            (bool success, ) = proposal.targetContract.call{value: 0}(
                proposal.encodedMessage
            );
            require(success, "DAO: called function reverted");
            emit Finished(
                proposalId,
                true,
                proposal.targetContract,
                votesAmount,
                proposal.usersVoted
            );
        } else {
            emit Finished(
                proposalId,
                false,
                proposal.targetContract,
                votesAmount,
                proposal.usersVoted
            );
        }
        proposal.isFinished = true;
    }

    function withdrawTokens(uint256 amount) external {
        require(
            _users[msg.sender].balance >= amount,
            "DAO: Insufficient funds on the balance"
        );
        require(
            _users[msg.sender].lastVoteEndTime < block.timestamp,
            "DAO: The last vote you participated in hasn't ended yet"
        );
        _users[msg.sender].balance -= amount;

        if (_users[msg.sender].balance == 0) {
            activeUsers.decrement();
        }

        emit TokensWithdrawn(msg.sender, amount);
    }

    function withdrawETH(address payable to, uint256 amount)
        external
        onlyRole(CHAIRMAN_ROLE)
    {
        Address.sendValue(to, amount);
        emit ETHWithdrawn(to, amount);
    }

    function getProposalById(uint256 id)
        external
        view
        returns (Proposal memory)
    {
        return _proposals[id];
    }

    function getLastProposalId() external view returns (uint256) {
        return proposalsCounter.current();
    }

    function getActiveUsers() external view returns (uint256) {
        return activeUsers.current();
    }

    function isUserVoted(address voter, uint256 proposalId)
        external
        view
        returns (bool)
    {
        return _users[voter]._isVoted[proposalId];
    }

    function userLastVoteEndTime(address voter)
        external
        view
        returns (uint256)
    {
        return _users[voter].lastVoteEndTime;
    }

    function getBalance(address voter) external view returns (uint256) {
        return _users[voter].balance;
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

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }
}
