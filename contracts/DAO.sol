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

    event Received(address indexed sender, uint256 amount);
    event ETHWithdrawn(address indexed receiver, uint256 indexed amount);

    event Credited(address indexed user, uint256 amount);
    event TokensWithdrawn(address indexed user, uint256 amount);

    event ProposalAdded(uint256 indexed id, uint256 time);
    event Voted(address indexed user, uint256 indexed proposal, bool answer);
    event FinishedEmergency(uint indexed proposalId);
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
        string description;
        bool isFinished;
        uint256 EndTime;
        uint256 consenting;
        uint256 dissenters;
        uint256 usersVoted;
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

    modifier endProposalCondition(uint256 proposalId) {
        require(
            _proposals[proposalId].EndTime <= block.timestamp,
            "DAO: Voting time is not over yet"
        );
        require(
            _proposals[proposalId].isFinished == false,
            "DAO: Voting has already ended"
        );
        _;
    }

    function deposit(uint256 amount) external {
        voteToken.transferFrom(msg.sender, address(this), amount);
        _users[msg.sender].balance += amount;
        activeUsers.increment();
        emit Credited(msg.sender, amount);
    }

    // Signature param - encoded function with args.
    function addProposal(
        address _targetContract,
        bytes calldata signature,
        string calldata description
    ) external onlyRole(CHAIRMAN_ROLE) nonReentrant {
        uint256 current = proposalsCounter.current();

        _proposals[current] = Proposal(
            _targetContract,
            signature,
            description,
            false,
            block.timestamp + debatingPeriodDuration,
            0,
            0,
            0
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

    function finishProposal(uint256 proposalId)
        external
        endProposalCondition(proposalId)
        nonReentrant
    {
        Proposal storage proposal = _proposals[proposalId];

        uint256 votesAmount = proposal.consenting + proposal.dissenters;

        // The number of users is multiplied by 10 to the 3rd power
        // to eliminate errors, provided that users are less than 10 / 100
        uint256 votersPercentage = CalculateVotersPercentage();
        uint256 users = proposal.usersVoted * 10**3;

        if (votesAmount >= minimumVotes && users >= votersPercentage) {
            (bool success, bytes memory returnedData) = proposal
                .targetContract
                .call{value: 0}(proposal.encodedMessage);
            require(success, string(returnedData));

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

    // A function that can be called by proposal voting to end the voting urgently.
    function endProposal(uint256 proposalId)
        external
        endProposalCondition(proposalId)
    {
        require(
            msg.sender == address(this),
            "Only a contract can end proposal"
        );
        _proposals[proposalId].isFinished = true;
        emit FinishedEmergency(proposalId);
    }

    function CalculateVotersPercentage() private view returns (uint256) {
        return ((activeUsers.current() * 10**3) / 100) * minimumQuorum;
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

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    function getProposalById(uint256 id)
        external
        view
        returns (Proposal memory)
    {
        return _proposals[id];
    }

    // Getters associated with counters
    function getLastProposalId() external view returns (uint256) {
        return proposalsCounter.current();
    }

    function getActiveUsers() external view returns (uint256) {
        return activeUsers.current();
    }

    // Getters associated with user
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
    
    // Getters associated with condition constants
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
}
