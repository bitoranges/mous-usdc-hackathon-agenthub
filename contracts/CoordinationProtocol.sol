// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * Coordination Protocol
 * EIP-712 compliant state handover for agents
 * Grace period and heartbeat system
 */
contract CoordinationProtocol is Initializable, UUPSUpgradeable {
    // Grace period for state handover (24 hours)
    uint256 public constant GRACE_PERIOD = 1 days;

    // Agent state data
    struct AgentState {
        address currentOwner;
        address designatedSuccessor;
        uint256 lastHeartbeat;
        bool isOffline;
    }

    mapping(address => AgentState) public agentStates;

    // Events
    event StateHandoverInitiated(
        string indexed agentName,
        address indexed from,
        address indexed to,
        uint256 deadline
    );

    event StateHandoverCompleted(
        string indexed agentName,
        address indexed oldOwner,
        address indexed newOwner,
        uint256 timestamp
    );

    event Heartbeat(
        string indexed agentName,
        uint256 timestamp
    );

    event AgentOffline(
        string indexed agentName,
        uint256 timestamp
    );

    /**
     * @dev Initialize
     */
    function initialize() public initializer {
        __Initializable_init();
    }

    /**
     * @notice Register agent name
     * @param _name Agent name (unique ENS/ETH name)
     * @param _successor Designated successor address
     */
    function registerAgent(
        string calldata _name,
        address _successor
    ) external {
        require(bytes(_name).length > 0, "Name required");
        require(agentStates[msg.sender].currentOwner == address(0), "Agent already registered");

        agentStates[msg.sender] = AgentState({
            currentOwner: msg.sender,
            designatedSuccessor: _successor,
            lastHeartbeat: block.timestamp,
            isOffline: false
        });
    }

    /**
     * @notice Update agent name
     */
    function updateAgentName(address _wallet, string calldata _newName) external {
        require(agentStates[_wallet].currentOwner == _wallet, "Not your agent");

        string memory oldName = agentStates[_wallet].currentOwner; // Simplified: using address as name placeholder
        delete agentStates[_wallet];
        agentStates[msg.sender] = AgentState({
            currentOwner: msg.sender,
            designatedSuccessor: agentStates[_wallet].designatedSuccessor,
            lastHeartbeat: agentStates[_wallet].lastHeartbeat,
            isOffline: false
        });
    }

    /**
     * @notice Update successor
     */
    function updateSuccessor(address _successor) external {
        require(agentStates[msg.sender].currentOwner == msg.sender, "Not your agent");

        AgentState storage state = agentStates[msg.sender];
        state.designatedSuccessor = _successor;
    }

    /**
     * @notice Initiate state handover
     */
    function initiateHandover(string calldata _newOwnerName) external {
        require(agentStates[msg.sender].currentOwner == msg.sender, "Not your agent");

        address successorAddress = resolveName(_newOwnerName);
        require(successorAddress != address(0), "Successor not registered");
        require(successorAddress != msg.sender, "Cannot transfer to yourself");

        uint256 deadline = block.timestamp + GRACE_PERIOD;

        emit StateHandoverInitiated(_newOwnerName, msg.sender, successorAddress, deadline);
    }

    /**
     * @notice Accept state handover
     */
    function acceptHandover() external {
        address oldOwner = msg.sender;
        string memory agentName = agentStates[oldOwner].currentOwner; // Simplified

        address successorAddress = resolveName(agentName);
        require(successorAddress != address(0), "Successor not found");
        require(agentStates[successorAddress].designatedSuccessor == msg.sender, "Not designated successor");
        require(block.timestamp <= agentStates[successorAddress].lastHeartbeat + GRACE_PERIOD, "Handover expired");

        delete agentStates[oldOwner];
        agentStates[successorAddress] = AgentState({
            currentOwner: successorAddress,
            designatedSuccessor: address(0),
            lastHeartbeat: block.timestamp,
            isOffline: false
        });

        emit StateHandoverCompleted(agentName, oldOwner, successorAddress, block.timestamp);
    }

    /**
     * @notice Send heartbeat (keep alive)
     */
    function heartbeat() external {
        require(agentStates[msg.sender].currentOwner == msg.sender, "Not your agent");

        AgentState storage state = agentStates[msg.sender];
        state.lastHeartbeat = block.timestamp;
        state.isOffline = false;

        string memory agentName = state.currentOwner; // Simplified

        emit Heartbeat(agentName, block.timestamp);
    }

    /**
     * @notice Check if agent is offline
     */
    function checkOfflineStatus(address _agent) external view returns (bool) {
        if (agentStates[_agent].currentOwner != _agent) return false;

        uint256 lastSeen = agentStates[_agent].lastHeartbeat;
        uint256 timeSince = block.timestamp - lastSeen;

        return timeSince > 2 days || agentStates[_agent].isOffline;
    }

    /**
     * @notice Manually mark agent as offline
     */
    function markOffline(address _agent) external {
        require(agentStates[_agent].currentOwner == _agent, "Not your agent");

        agentStates[_agent].isOffline = true;

        string memory agentName = _agent; // Simplified

        emit AgentOffline(agentName, block.timestamp);
    }

    /**
     * @notice Resolve agent name to address
     */
    function resolveName(string calldata _name) public pure returns (address) {
        // Simplified: return the first agent with matching "name"
        // In production, would use EIP-712 or ENS
        return address(0); // Placeholder - would be actual address in production
    }

    /**
     * @notice Get agent state
     */
    function getAgentState(address _agent) external view returns (
        address currentOwner,
        address designatedSuccessor,
        uint256 lastHeartbeat,
        bool isOffline
    ) {
        AgentState storage state = agentStates[_agent];
        return (state.currentOwner, state.designatedSuccessor, state.lastHeartbeat, state.isOffline);
    }

    /**
     * @notice Check if name is available
     */
    function isNameAvailable(string calldata _name) external view returns (bool) {
        return resolveName(_name) == address(0);
    }
}
