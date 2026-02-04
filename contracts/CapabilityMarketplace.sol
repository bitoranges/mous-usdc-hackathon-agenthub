// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * Capability Marketplace Contract
 * Agent task marketplace with USDC payments
 */
contract CapabilityMarketplace is Initializable, UUPSUpgradeable, ReentrancyGuard {
    IERC20 public immutable usdc;

    // Task status
    uint256 public constant STATUS_OPEN = 0;
    uint256 public constant STATUS_ASSIGNED = 1;
    uint256 public constant STATUS_COMPLETED = 2;
    uint256 public constant STATUS_CANCELLED = 3;

    // Task types
    uint256 public constant TYPE_FIXED_PRICE = 0;
    uint256 public constant TYPE_AUCTION = 1;

    // Task struct
    struct Task {
        uint256 id;
        address creator;
        uint256 capabilityRequired;
        string title;
        string description;
        uint256 price;                  // USDC (fixed) or 0 for auction
        uint256 bid;                   // Current highest bid (for auctions)
        address assignedAgent;
        uint256 status;
        uint256 createdAt;
        uint256 deadline;
        uint256 completedAt;
        bytes32 resultHash;           // IPFS hash of deliverables
    }

    // Bid struct (for auctions)
    struct Bid {
        address bidder;
        uint256 amount;
        uint256 timestamp;
    }

    mapping(uint256 => Task) public tasks;
    uint256 public taskCount;
    uint256 public nextTaskId;

    mapping(uint256 => Task => mapping(address => Bid)) public bids;
    uint256 public marketplaceFeePercentage = 500;  // 5% fee (500 basis points)

    // Events
    event TaskCreated(
        uint256 indexed taskId,
        address indexed creator,
        uint256 capabilityRequired,
        uint256 price,
        uint256 deadline
    );

    event TaskAssigned(
        uint256 indexed taskId,
        address indexed creator,
        address indexed assignedAgent
    );

    event BidPlaced(
        uint256 indexed taskId,
        address indexed bidder,
        uint256 amount
    );

    event TaskCompleted(
        uint256 indexed taskId,
        address indexed creator,
        address indexed assignedAgent,
        uint256 payment,
        bytes32 resultHash
    );

    /**
     * @dev Initialize contract
     */
    function initialize(address _usdc) public initializer {
        __Initializable_init();
        usdc = IERC20(_usdc);
    }

    /**
     * @notice Create a new task
     * @param _capabilityRequired Required agent capability (from AgentRegistry)
     * @param _title Task title
     * @param _description Task description
     * @param _price Fixed price (0 for auction)
     * @param _deadline Task deadline (timestamp)
     */
    function createTask(
        uint256 _capabilityRequired,
        string calldata _title,
        string calldata _description,
        uint256 _price,
        uint256 _deadline
    ) external payable {
        require(_deadline > block.timestamp, "Deadline must be in future");
        require(_price == 0 || msg.value > 0, "Invalid payment");

        tasks[nextTaskId] = Task({
            id: nextTaskId,
            creator: msg.sender,
            capabilityRequired: _capabilityRequired,
            title: _title,
            description: _description,
            price: _price,
            bid: 0,
            assignedAgent: address(0),
            status: STATUS_OPEN,
            createdAt: block.timestamp,
            deadline: _deadline,
            completedAt: 0,
            resultHash: bytes32(0)
        });

        // For fixed price tasks, lock the payment upfront
        if (_price > 0) {
            require(
                usdc.transferFrom(msg.sender, address(this), _price),
                "USDC payment failed"
            );
        }

        emit TaskCreated(nextTaskId, msg.sender, _capabilityRequired, _price, _deadline);
        nextTaskId++;
        taskCount++;
    }

    /**
     * @notice Accept a task (fixed price)
     * @param _taskId Task ID
     */
    function acceptTask(uint256 _taskId) external {
        Task storage task = tasks[_taskId];
        require(task.status == STATUS_OPEN, "Task not available");
        require(task.assignedAgent == address(0), "Task already assigned");
        require(msg.sender != task.creator, "Creator cannot accept own task");

        task.assignedAgent = msg.sender;
        task.status = STATUS_ASSIGNED;

        emit TaskAssigned(_taskId, task.creator, msg.sender);
    }

    /**
     * @notice Place a bid on auction task
     * @param _taskId Task ID
     * @param _amount Bid amount
     */
    function placeBid(uint256 _taskId) external payable {
        Task storage task = tasks[_taskId];
        require(task.price == 0, "Not an auction task");
        require(task.status == STATUS_OPEN, "Task not open");
        require(msg.value > task.bid, "Bid too low");
        require(block.timestamp < task.deadline, "Auction ended");

        bids[_taskId][msg.sender] = Bid({
            bidder: msg.sender,
            amount: msg.value,
            timestamp: block.timestamp
        });

        task.bid = msg.value;

        emit BidPlaced(_taskId, msg.sender, msg.value);
    }

    /**
     * @notice Assign task to agent (for creator)
     * @param _taskId Task ID
     * @param _agent Agent to assign
     */
    function assignAgent(uint256 _taskId, address _agent) external {
        Task storage task = tasks[_taskId];
        require(msg.sender == task.creator, "Only creator");
        require(task.status == STATUS_OPEN, "Task not open");
        require(task.assignedAgent == address(0), "Task already assigned");
        require(task.price > 0, "Cannot assign auction tasks");

        task.assignedAgent = _agent;
        task.status = STATUS_ASSIGNED;

        emit TaskAssigned(_taskId, msg.sender, _agent);
    }

    /**
     * @notice Complete a task
     * @param _taskId Task ID
     * @param _resultHash IPFS hash of deliverables
     */
    function completeTask(uint256 _taskId, bytes32 _resultHash) external nonReentrant {
        Task storage task = tasks[_taskId];
        require(msg.sender == task.assignedAgent, "Only assigned agent");
        require(task.status == STATUS_ASSIGNED, "Task not assigned");
        require(block.timestamp <= task.deadline, "Task expired");

        task.status = STATUS_COMPLETED;
        task.completedAt = block.timestamp;
        task.resultHash = _resultHash;

        // Calculate payment
        uint256 payment;

        if (task.price > 0) {
            payment = task.price;
        } else {
            payment = task.bid;
        }

        // Calculate marketplace fee
        uint256 fee = (payment * marketplaceFeePercentage) / 10000;
        uint256 agentPayment = payment - fee;

        // Transfer to agent
        require(
            usdc.transferFrom(address(this), msg.sender, agentPayment),
            "USDC transfer failed"
        );

        // Transfer fee to marketplace
        usdc.transferFrom(address(this), address(this), fee);

        emit TaskCompleted(_taskId, task.creator, msg.sender, agentPayment, _resultHash);

        // Allow creator to reclaim fixed-price escrow after completion
        if (task.price > 0) {
            usdc.transfer(address(this), msg.sender, task.price);
        }
    }

    /**
     * @notice Cancel a task
     */
    function cancelTask(uint256 _taskId) external {
        Task storage task = tasks[_taskId];
        require(msg.sender == task.creator, "Only creator");
        require(task.status == STATUS_OPEN || task.status == STATUS_ASSIGNED, "Task already completed");

        task.status = STATUS_CANCELLED;

        // Refund payment if fixed price
        if (task.price > 0) {
            usdc.transfer(address(this), msg.sender, task.price);
        }

        // Return bids if auction
        if (task.price == 0) {
            mapping(address => Bid) storage taskBids = bids[_taskId];
            uint256 count;

            for (uint256 i = 0; i < storage.length; i++) {
                usdc.transferFrom(address(this), taskBids[i].bidder, taskBids[i].amount);
                count++;
            }
        }
    }

    /**
     * @notice Update marketplace fee
     */
    function updateMarketplaceFee(uint256 _newFeePercentage) external onlyOwner {
        require(_newFeePercentage <= 1000, "Fee too high");  // Max 10%
        marketplaceFeePercentage = _newFeePercentage;
    }

    /**
     * @notice Get task details
     */
    function getTask(uint256 _taskId) external view returns (Task memory) {
        return tasks[_taskId];
    }

    /**
     * @notice Get tasks by capability
     */
    function getTasksByCapability(uint256 _capability) external view returns (uint256[] memory) {
        uint256[] memory result = new uint256[](taskCount);
        uint256 count;

        for (uint256 i = 1; i <= taskCount; i++) {
            if (tasks[i].capabilityRequired == _capability && tasks[i].status != STATUS_CANCELLED) {
                result[count] = i;
                count++;
            }
        }

        // Resize to count
        uint256[] memory trimmed = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            trimmed[i] = result[i];
        }

        return trimmed;
    }

    /**
     * @notice Get open tasks
     */
    function getOpenTasks() external view returns (uint256[] memory) {
        uint256[] memory result = new uint256[](taskCount);
        uint256 count;

        for (uint256 i = 1; i <= taskCount; i++) {
            if (tasks[i].status == STATUS_OPEN) {
                result[count] = i;
                count++;
            }
        }

        uint256[] memory trimmed = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            trimmed[i] = result[i];
        }

        return trimmed;
    }
}
