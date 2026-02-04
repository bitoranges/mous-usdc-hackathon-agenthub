// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * Agent Registry Contract
 * Manages agent identities and capabilities
 * EIP-712 compliant agent name resolution
 */
contract AgentRegistry is Initializable, UUPSUpgradeable {
    // Agent capability flags
    uint256 public constant CAPABILITY_TRADING = 1 << 0;
    uint256 public constant CAPABILITY_RESEARCH = 1 << 1;
    uint256 public constant CAPABILITY_CONTENT = 1 << 2;
    uint256 public constant CAPABILITY_DEV = 1 << 3;
    uint256 public constant CAPABILITY_ORACLE = 1 << 4;
    uint256 public constant CAPABILITY_AUTOMATION = 1 << 5;

    // USDC token on Base
    IERC20 public immutable usdc;

    // Agent data structures
    struct Agent {
        address wallet;
        uint256 capabilities;
        uint256 activityScore;
        uint256 createdAt;
        string metadata;
    }

    mapping(address => Agent) public agents;
    address[] public agentList;
    uint256 public agentCount;

    // Events
    event AgentRegistered(
        address indexed agent,
        uint256 capabilities,
        uint256 activityScore,
        string metadata
    );

    event AgentUpdated(
        address indexed agent,
        uint256 oldCapabilities,
        uint256 newCapabilities,
        uint256 oldScore,
        uint256 newScore
    );

    /**
     * @dev Initialize contract
     */
    function initialize(address _usdc) public initializer {
        __Initializable_init();
        usdc = IERC20(_usdc);
    }

    /**
     * @notice Register a new agent
     * @param _capabilities Bitmask of capabilities
     * @param _metadata IPFS hash or metadata URI
     */
    function registerAgent(
        uint256 _capabilities,
        string calldata _metadata
    ) external {
        require(agents[msg.sender].wallet == address(0), "Agent already registered");

        uint256 score = 0;

        if (_capabilities & CAPABILITY_TRADING) score += 30;
        if (_capabilities & CAPABILITY_RESEARCH) score += 20;
        if (_capabilities & CAPABILITY_CONTENT) score += 15;
        if (_capabilities & CAPABILITY_DEV) score += 25;
        if (_capabilities & CAPABILITY_ORACLE) score += 10;
        if (_capabilities & CAPABILITY_AUTOMATION) score += 20;

        agents[msg.sender] = Agent({
            wallet: msg.sender,
            capabilities: _capabilities,
            activityScore: score,
            createdAt: block.timestamp,
            metadata: _metadata
        });

        agentList.push(msg.sender);
        agentCount++;

        emit AgentRegistered(msg.sender, _capabilities, score, score, _metadata);
    }

    /**
     * @notice Update agent capabilities
     * @param _agent Agent wallet address
     * @param _newCapabilities New capability bitmask
     */
    function updateCapabilities(
        address _agent,
        uint256 _newCapabilities
    ) external {
        require(agents[_agent].wallet == _agent, "Agent not found");

        Agent storage agent = agents[_agent];

        uint256 oldCapabilities = agent.capabilities;
        uint256 oldScore = agent.activityScore;

        uint256 newScore = 0;
        if (_newCapabilities & CAPABILITY_TRADING) newScore += 30;
        if (_newCapabilities & CAPABILITY_RESEARCH) newScore += 20;
        if (_newCapabilities & CAPABILITY_CONTENT) newScore += 15;
        if (_newCapabilities & CAPABILITY_DEV) newScore += 25;
        if (_newCapabilities & CAPABILITY_ORACLE) newScore += 10;
        if (_newCapabilities & CAPABILITY_AUTOMATION) newScore += 20;

        agent.capabilities = _newCapabilities;
        agent.activityScore = newScore;

        emit AgentUpdated(_agent, oldCapabilities, _newCapabilities, oldScore, newScore);
    }

    /**
     * @notice Update agent activity score
     * @param _agent Agent wallet address
     * @param _delta Score change (positive or negative)
     */
    function updateActivityScore(
        address _agent,
        int256 _delta
    ) external {
        require(agents[_agent].wallet == _agent, "Agent not found");

        Agent storage agent = agents[_agent];
        int256 oldScore = int256(agent.activityScore);
        agent.activityScore = uint256(int256(oldScore) + _delta);

        emit AgentUpdated(_agent, agent.capabilities, agent.capabilities, oldScore, agent.activityScore);
    }

    /**
     * @notice Get agent info
     */
    function getAgent(address _agent) external view returns (
        address wallet,
        uint256 capabilities,
        uint256 activityScore,
        string memory metadata
    ) {
        Agent storage agent = agents[_agent];
        return (agent.wallet, agent.capabilities, agent.activityScore, agent.metadata);
    }

    /**
     * @notice Get all agents
     */
    function getAllAgents() external view returns (address[] memory) {
        return agentList;
    }

    /**
     * @notice Search agents by capability
     */
    function searchByCapability(uint256 _capability) external view returns (address[] memory) {
        address[] memory result = new address[](agentCount);
        uint256 count;

        for (uint256 i = 0; i < agentCount; i++) {
            if (agents[agentList[i]].capabilities & _capability) {
                result[count] = agentList[i];
                count++;
            }
        }

        address[] memory trimmed = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            trimmed[i] = result[i];
        }

        return trimmed;
    }

    /**
     * @notice Get top agents by activity score
     */
    function getTopAgents(uint256 _limit) external view returns (address[] memory) {
        address[] memory topAgents = new address[](_limit);
        address[] memory sorted = getAllAgents();

        // Sort agents by activity score
        for (uint256 i = 0; i < sorted.length - 1; i++) {
            for (uint256 j = i + 1; j < sorted.length; j++) {
                if (agents[sorted[i]].activityScore < agents[sorted[j]].activityScore) {
                    // Swap
                    address temp = sorted[i];
                    sorted[i] = sorted[j];
                    sorted[j] = temp;
                }
            }
        }

        for (uint256 i = 0; i < _limit && i < sorted.length; i++) {
            topAgents[i] = sorted[i];
        }

        return topAgents;
    }
}
