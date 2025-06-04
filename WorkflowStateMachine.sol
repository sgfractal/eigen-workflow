// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "./ITaskMailbox.sol";

/**
 * @title WorkflowStateMachine
 * @notice Advanced workflow orchestration system for complex multi-phase AVS operations
 * @dev Extends TaskMailbox capabilities with stateful, long-running workflows
 */
contract WorkflowStateMachine {
    
    enum PhaseType {
        IMMEDIATE,      // Task-like: execute now, return result
        COORDINATION,   // Multi-actor coordination with consensus
        CONTINUOUS,     // Epoch-like: ongoing monitoring with periodic updates
        CONDITIONAL,    // Event-driven: wait for external triggers
        AGGREGATION     // Collect and combine results from multiple sources
    }
    
    enum PhaseStatus {
        PENDING,
        ACTIVE,
        COMPLETED,
        FAILED,
        CONDITIONAL_WAITING,
        TIMED_OUT
    }
    
    enum TriggerConditionType {
        NONE,           // No condition
        PRICE_THRESHOLD, // Price above/below threshold
        TIME_THRESHOLD,  // Time-based trigger
        DATA_HASH,      // Specific data hash validation
        MULTI_SIG,      // Multiple signature requirement
        ORACLE_VALUE    // Oracle-provided value check
    }
    
    struct PhaseDefinition {
        string name;
        PhaseType phaseType;
        uint32 timeout;             // Max execution time in seconds
        uint32[] dependencies;      // Phase indices this depends on
        bytes triggerCondition;     // Encoded trigger condition for CONDITIONAL phases
        uint32 operatorSetId;       // Which operator set handles this phase
        bytes metadata;             // Phase-specific configuration
        uint256 requiredStake;      // Minimum stake required for operators
        uint16 consensusThreshold;  // Percentage required for coordination phases (in basis points)
    }
    
    struct WorkflowDefinition {
        string name;
        PhaseDefinition[] phases;
        address creator;
        uint256 totalStake;         // Required stake across all phases
        bool isActive;
        uint256 creationTime;
        mapping(address => bool) authorizedTriggers; // Who can trigger conditional phases
    }
    
    struct WorkflowExecution {
        bytes32 workflowId;
        bytes32 executionId;
        uint256 currentPhase;
        PhaseStatus[] phaseStatuses;
        mapping(uint256 => bytes) phaseResults;    // Results from each phase
        mapping(uint256 => uint256) phaseStartTimes;
        mapping(uint256 => uint256) phaseTimeouts;
        mapping(uint256 => mapping(address => bytes)) coordinationResponses; // For coordination phases
        mapping(uint256 => bytes[]) monitoringUpdates; // For continuous phases
        mapping(uint256 => uint256) responseCount; // Count of responses per phase
        bytes initialPayload;
        address initiator;
        bool isComplete;
        bool successful;
        uint256 completionTime;
    }
    
    struct ConditionalTrigger {
        bytes32 executionId;
        uint256 phaseIndex;
        bytes condition;
        bool triggered;
        uint256 triggerTimestamp;
        address triggerSource;
        bytes triggerData;
    }
    
    struct CoordinationPhase {
        uint256 requiredResponses;
        uint256 receivedResponses;
        mapping(address => bool) hasResponded;
        bytes aggregatedResult;
    }
    
    struct ContinuousPhase {
        uint256 updateInterval;
        uint256 lastUpdateTime;
        uint256 requiredUpdates;
        uint256 receivedUpdates;
        mapping(address => uint256) operatorLastUpdate;
    }
    
    ITaskMailbox public immutable taskMailbox;
    
    mapping(bytes32 => WorkflowDefinition) public workflows;
    mapping(bytes32 => WorkflowExecution) public executions;
    mapping(bytes32 => ConditionalTrigger) public conditionalTriggers;
    mapping(bytes32 => mapping(uint256 => CoordinationPhase)) public coordinationPhases;
    mapping(bytes32 => mapping(uint256 => ContinuousPhase)) public continuousPhases;
    
    // Access control
    mapping(address => bool) public authorizedWorkflowCreators;
    mapping(address => bool) public authorizedTriggerSources;
    mapping(bytes32 => mapping(address => bool)) public workflowOperators;
    
    // Economic parameters
    uint256 public workflowCreationFee;
    uint256 public phaseExecutionFee;
    address public feeCollector;
    
    // Constants
    uint256 private constant MAX_PHASES = 50;
    uint256 private constant MAX_DEPENDENCIES = 10;
    uint256 private constant BASIS_POINTS = 10000;
    
    // Events
    event WorkflowRegistered(bytes32 indexed workflowId, string name, uint256 phaseCount, address creator);
    event WorkflowExecutionStarted(bytes32 indexed executionId, bytes32 indexed workflowId, address initiator);
    event PhaseStarted(bytes32 indexed executionId, uint256 phaseIndex, PhaseType phaseType);
    event PhaseCompleted(bytes32 indexed executionId, uint256 phaseIndex, bytes result);
    event PhaseFailed(bytes32 indexed executionId, uint256 phaseIndex, string reason);
    event PhaseTimedOut(bytes32 indexed executionId, uint256 phaseIndex);
    event ConditionalTriggerSet(bytes32 indexed executionId, uint256 phaseIndex, bytes condition);
    event ConditionalTriggerActivated(bytes32 indexed executionId, uint256 phaseIndex, address triggerSource);
    event CoordinationPhaseStarted(bytes32 indexed executionId, uint256 phaseIndex, uint32 operatorSetId, uint256 requiredResponses);
    event CoordinationResponseReceived(bytes32 indexed executionId, uint256 phaseIndex, address operator);
    event ContinuousMonitoringStarted(bytes32 indexed executionId, uint256 phaseIndex, uint32 operatorSetId, uint256 updateInterval);
    event MonitoringUpdateReceived(bytes32 indexed executionId, uint256 phaseIndex, address operator);
    event WorkflowCompleted(bytes32 indexed executionId, bool success);
    event WorkflowCreatorAuthorized(address indexed creator);
    event TriggerSourceAuthorized(address indexed triggerSource);
    
    modifier onlyAuthorizedCreator() {
        require(authorizedWorkflowCreators[msg.sender], "Not authorized to create workflows");
        _;
    }
    
    modifier onlyAuthorizedTrigger() {
        require(authorizedTriggerSources[msg.sender], "Not authorized trigger source");
        _;
    }
    
    modifier onlyWorkflowCreator(bytes32 workflowId) {
        require(workflows[workflowId].creator == msg.sender, "Not workflow creator");
        _;
    }
    
    modifier validExecution(bytes32 executionId) {
        require(executions[executionId].executionId != bytes32(0), "Execution does not exist");
        _;
    }
    
    constructor(address _taskMailbox, address _feeCollector) {
        taskMailbox = ITaskMailbox(_taskMailbox);
        feeCollector = _feeCollector;
        workflowCreationFee = 0.01 ether;
        phaseExecutionFee = 0.001 ether;
        
        // Contract deployer is initially authorized
        authorizedWorkflowCreators[msg.sender] = true;
        authorizedTriggerSources[msg.sender] = true;
    }
    
    /**
     * @notice Register a new workflow definition
     */
    function registerWorkflow(
        string memory name,
        PhaseDefinition[] memory phases,
        address[] memory authorizedTriggers
    ) external payable onlyAuthorizedCreator returns (bytes32 workflowId) {
        require(msg.value >= workflowCreationFee, "Insufficient fee");
        require(phases.length > 0 && phases.length <= MAX_PHASES, "Invalid phase count");
        require(bytes(name).length > 0, "Name cannot be empty");
        
        workflowId = keccak256(abi.encodePacked(name, msg.sender, block.timestamp, block.number));
        
        WorkflowDefinition storage workflow = workflows[workflowId];
        workflow.name = name;
        workflow.creator = msg.sender;
        workflow.isActive = true;
        workflow.creationTime = block.timestamp;
        
        uint256 totalStake = 0;
        
        // Copy phases and validate
        for (uint i = 0; i < phases.length; i++) {
            require(phases[i].dependencies.length <= MAX_DEPENDENCIES, "Too many dependencies");
            require(phases[i].timeout > 0, "Timeout must be positive");
            
            workflow.phases.push(phases[i]);
            totalStake += phases[i].requiredStake;
            
            // Validate dependencies
            for (uint j = 0; j < phases[i].dependencies.length; j++) {
                require(phases[i].dependencies[j] < i, "Dependencies must reference earlier phases");
            }
            
            // Validate consensus threshold for coordination phases
            if (phases[i].phaseType == PhaseType.COORDINATION) {
                require(phases[i].consensusThreshold > 0 && phases[i].consensusThreshold <= BASIS_POINTS, 
                        "Invalid consensus threshold");
            }
        }
        
        workflow.totalStake = totalStake;
        
        // Set authorized triggers
        for (uint i = 0; i < authorizedTriggers.length; i++) {
            workflow.authorizedTriggers[authorizedTriggers[i]] = true;
        }
        
        // Send fee to collector
        if (msg.value > 0) {
            payable(feeCollector).transfer(msg.value);
        }
        
        emit WorkflowRegistered(workflowId, name, phases.length, msg.sender);
        return workflowId;
    }
    
    /**
     * @notice Execute a workflow
     */
    function executeWorkflow(
        bytes32 workflowId,
        bytes memory payload
    ) external payable returns (bytes32 executionId) {
        WorkflowDefinition storage workflow = workflows[workflowId];
        require(workflow.isActive, "Workflow not active");
        require(msg.value >= phaseExecutionFee, "Insufficient execution fee");
        
        executionId = keccak256(abi.encodePacked(workflowId, msg.sender, block.timestamp, block.number));
        
        WorkflowExecution storage execution = executions[executionId];
        execution.workflowId = workflowId;
        execution.executionId = executionId;
        execution.currentPhase = 0;
        execution.initialPayload = payload;
        execution.initiator = msg.sender;
        
        // Initialize phase statuses
        for (uint i = 0; i < workflow.phases.length; i++) {
            execution.phaseStatuses.push(PhaseStatus.PENDING);
        }
        
        // Send execution fee to collector
        if (msg.value > 0) {
            payable(feeCollector).transfer(msg.value);
        }
        
        emit WorkflowExecutionStarted(executionId, workflowId, msg.sender);
        
        // Start first phase if dependencies are met
        _tryAdvanceWorkflow(executionId);
        
        return executionId;
    }
    
    /**
     * @notice Advance workflow to next executable phase
     */
    function _tryAdvanceWorkflow(bytes32 executionId) internal {
        WorkflowExecution storage execution = executions[executionId];
        WorkflowDefinition storage workflow = workflows[execution.workflowId];
        
        if (execution.isComplete) return;
        
        // Find next executable phases (can execute multiple in parallel if no dependencies)
        for (uint i = 0; i < workflow.phases.length; i++) {
            if (execution.phaseStatuses[i] == PhaseStatus.PENDING) {
                if (_canExecutePhase(executionId, i)) {
                    _startPhase(executionId, i);
                }
            }
        }
        
        // Check if workflow is complete
        _checkWorkflowCompletion(executionId);
    }
    
    /**
     * @notice Check if a phase can be executed based on dependencies
     */
    function _canExecutePhase(bytes32 executionId, uint256 phaseIndex) internal view returns (bool) {
        WorkflowExecution storage execution = executions[executionId];
        WorkflowDefinition storage workflow = workflows[execution.workflowId];
        PhaseDefinition storage phase = workflow.phases[phaseIndex];
        
        // Check all dependencies are completed
        for (uint i = 0; i < phase.dependencies.length; i++) {
            uint32 depIndex = phase.dependencies[i];
            if (execution.phaseStatuses[depIndex] != PhaseStatus.COMPLETED) {
                return false;
            }
        }
        
        return true;
    }
    
    /**
     * @notice Start execution of a specific phase
     */
    function _startPhase(bytes32 executionId, uint256 phaseIndex) internal {
        WorkflowExecution storage execution = executions[executionId];
        WorkflowDefinition storage workflow = workflows[execution.workflowId];
        PhaseDefinition storage phase = workflow.phases[phaseIndex];
        
        execution.phaseStatuses[phaseIndex] = PhaseStatus.ACTIVE;
        execution.phaseStartTimes[phaseIndex] = block.timestamp;
        execution.phaseTimeouts[phaseIndex] = block.timestamp + phase.timeout;
        
        emit PhaseStarted(executionId, phaseIndex, phase.phaseType);
        
        // Route to appropriate execution strategy
        if (phase.phaseType == PhaseType.IMMEDIATE) {
            _executeImmediatePhase(executionId, phaseIndex);
        } else if (phase.phaseType == PhaseType.COORDINATION) {
            _executeCoordinationPhase(executionId, phaseIndex);
        } else if (phase.phaseType == PhaseType.CONTINUOUS) {
            _executeContinuousPhase(executionId, phaseIndex);
        } else if (phase.phaseType == PhaseType.CONDITIONAL) {
            _executeConditionalPhase(executionId, phaseIndex);
        } else if (phase.phaseType == PhaseType.AGGREGATION) {
            _executeAggregationPhase(executionId, phaseIndex);
        }
    }
    
    /**
     * @notice Execute immediate phase (task-like)
     */
    function _executeImmediatePhase(bytes32 executionId, uint256 phaseIndex) internal {
        WorkflowExecution storage execution = executions[executionId];
        WorkflowDefinition storage workflow = workflows[execution.workflowId];
        PhaseDefinition storage phase = workflow.phases[phaseIndex];
        
        // Prepare payload with context from previous phases
        bytes memory phasePayload = _buildPhasePayload(executionId, phaseIndex);
        
        // Create task in existing TaskMailbox
        ITaskMailbox.TaskParams memory taskParams = ITaskMailbox.TaskParams({
            refundCollector: execution.initiator,
            avsFee: 0,
            executorOperatorSet: OperatorSet({
                avs: address(this),
                id: phase.operatorSetId
            }),
            payload: phasePayload
        });
        
        bytes32 taskHash = taskMailbox.createTask(taskParams);
        
        // Store task hash for result retrieval
        execution.phaseResults[phaseIndex] = abi.encode(taskHash);
        
        // For demo purposes, immediately complete the phase
        // In reality, this would be completed when the task result is submitted
        _completePhase(executionId, phaseIndex, abi.encode("immediate_result"));
    }
    
    /**
     * @notice Execute coordination phase
     */
    function _executeCoordinationPhase(bytes32 executionId, uint256 phaseIndex) internal {
        WorkflowExecution storage execution = executions[executionId];
        WorkflowDefinition storage workflow = workflows[execution.workflowId];
        PhaseDefinition storage phase = workflow.phases[phaseIndex];
        
        // Calculate required responses based on consensus threshold
        // This would typically query the operator set to get the count
        uint256 totalOperators = 5; // Placeholder - should query from operator registry
        uint256 requiredResponses = (totalOperators * phase.consensusThreshold) / BASIS_POINTS;
        
        CoordinationPhase storage coordPhase = coordinationPhases[executionId][phaseIndex];
        coordPhase.requiredResponses = requiredResponses;
        coordPhase.receivedResponses = 0;
        
        emit CoordinationPhaseStarted(executionId, phaseIndex, phase.operatorSetId, requiredResponses);
    }
    
    /**
     * @notice Execute continuous monitoring phase
     */
    function _executeContinuousPhase(bytes32 executionId, uint256 phaseIndex) internal {
        WorkflowExecution storage execution = executions[executionId];
        WorkflowDefinition storage workflow = workflows[execution.workflowId];
        PhaseDefinition storage phase = workflow.phases[phaseIndex];
        
        // Decode monitoring parameters from metadata
        (uint256 updateInterval, uint256 requiredUpdates) = abi.decode(phase.metadata, (uint256, uint256));
        
        ContinuousPhase storage contPhase = continuousPhases[executionId][phaseIndex];
        contPhase.updateInterval = updateInterval;
        contPhase.lastUpdateTime = block.timestamp;
        contPhase.requiredUpdates = requiredUpdates;
        contPhase.receivedUpdates = 0;
        
        emit ContinuousMonitoringStarted(executionId, phaseIndex, phase.operatorSetId, updateInterval);
    }
    
    /**
     * @notice Execute conditional phase - waits for external trigger
     */
    function _executeConditionalPhase(bytes32 executionId, uint256 phaseIndex) internal {
        WorkflowExecution storage execution = executions[executionId];
        WorkflowDefinition storage workflow = workflows[execution.workflowId];
        PhaseDefinition storage phase = workflow.phases[phaseIndex];
        
        execution.phaseStatuses[phaseIndex] = PhaseStatus.CONDITIONAL_WAITING;
        
        bytes32 triggerId = keccak256(abi.encodePacked(executionId, phaseIndex));
        ConditionalTrigger storage trigger = conditionalTriggers[triggerId];
        trigger.executionId = executionId;
        trigger.phaseIndex = phaseIndex;
        trigger.condition = phase.triggerCondition;
        
        emit ConditionalTriggerSet(executionId, phaseIndex, trigger.condition);
    }
    
    /**
     * @notice Execute aggregation phase
     */
    function _executeAggregationPhase(bytes32 executionId, uint256 phaseIndex) internal {
        WorkflowExecution storage execution = executions[executionId];
        WorkflowDefinition storage workflow = workflows[execution.workflowId];
        PhaseDefinition storage phase = workflow.phases[phaseIndex];
        
        // Collect results from dependency phases
        bytes[] memory resultsToAggregate = new bytes[](phase.dependencies.length);
        for (uint i = 0; i < phase.dependencies.length; i++) {
            uint32 depIndex = phase.dependencies[i];
            resultsToAggregate[i] = execution.phaseResults[depIndex];
        }
        
        // Perform aggregation (simple concatenation for demo)
        bytes memory aggregatedResult = abi.encode(resultsToAggregate);
        
        _completePhase(executionId, phaseIndex, aggregatedResult);
    }
    
    /**
     * @notice Submit coordination response
     */
    function submitCoordinationResponse(
        bytes32 executionId,
        uint256 phaseIndex,
        bytes calldata response
    ) external validExecution(executionId) {
        WorkflowExecution storage execution = executions[executionId];
        require(execution.phaseStatuses[phaseIndex] == PhaseStatus.ACTIVE, "Phase not active");
        
        CoordinationPhase storage coordPhase = coordinationPhases[executionId][phaseIndex];
        require(!coordPhase.hasResponded[msg.sender], "Already responded");
        require(coordPhase.receivedResponses < coordPhase.requiredResponses, "Enough responses received");
        
        coordPhase.hasResponded[msg.sender] = true;
        coordPhase.receivedResponses++;
        execution.coordinationResponses[phaseIndex][msg.sender] = response;
        
        emit CoordinationResponseReceived(executionId, phaseIndex, msg.sender);
        
        // Check if we have enough responses
        if (coordPhase.receivedResponses >= coordPhase.requiredResponses) {
            // Aggregate responses (simple voting for demo)
            bytes memory finalResult = _aggregateCoordinationResponses(executionId, phaseIndex);
            _completePhase(executionId, phaseIndex, finalResult);
        }
    }
    
    /**
     * @notice Submit monitoring update
     */
    function submitMonitoringUpdate(
        bytes32 executionId,
        uint256 phaseIndex,
        bytes calldata update
    ) external validExecution(executionId) {
        WorkflowExecution storage execution = executions[executionId];
        require(execution.phaseStatuses[phaseIndex] == PhaseStatus.ACTIVE, "Phase not active");
        
        ContinuousPhase storage contPhase = continuousPhases[executionId][phaseIndex];
        require(block.timestamp >= contPhase.operatorLastUpdate[msg.sender] + contPhase.updateInterval, 
                "Update too frequent");
        
        contPhase.operatorLastUpdate[msg.sender] = block.timestamp;
        contPhase.receivedUpdates++;
        execution.monitoringUpdates[phaseIndex].push(update);
        
        emit MonitoringUpdateReceived(executionId, phaseIndex, msg.sender);
        
        // Check if monitoring period is complete
        if (contPhase.receivedUpdates >= contPhase.requiredUpdates) {
            bytes memory finalResult = abi.encode(execution.monitoringUpdates[phaseIndex]);
            _completePhase(executionId, phaseIndex, finalResult);
        }
    }
    
    /**
     * @notice Trigger conditional phase
     */
    function triggerConditionalPhase(
        bytes32 executionId,
        uint256 phaseIndex,
        bytes memory triggerData
    ) external validExecution(executionId) {
        bytes32 triggerId = keccak256(abi.encodePacked(executionId, phaseIndex));
        ConditionalTrigger storage trigger = conditionalTriggers[triggerId];
        
        require(!trigger.triggered, "Already triggered");
        require(_isAuthorizedTrigger(executionId, msg.sender), "Not authorized trigger");
        require(_validateTriggerCondition(trigger.condition, triggerData), "Invalid trigger condition");
        
        trigger.triggered = true;
        trigger.triggerTimestamp = block.timestamp;
        trigger.triggerSource = msg.sender;
        trigger.triggerData = triggerData;
        
        WorkflowExecution storage execution = executions[executionId];
        execution.phaseStatuses[phaseIndex] = PhaseStatus.COMPLETED;
        execution.phaseResults[phaseIndex] = triggerData;
        
        emit ConditionalTriggerActivated(executionId, phaseIndex, msg.sender);
        emit PhaseCompleted(executionId, phaseIndex, triggerData);
        
        _tryAdvanceWorkflow(executionId);
    }
    
    /**
     * @notice Check for phase timeouts
     */
    function checkPhaseTimeout(bytes32 executionId, uint256 phaseIndex) external validExecution(executionId) {
        WorkflowExecution storage execution = executions[executionId];
        require(execution.phaseTimeouts[phaseIndex] != 0, "No timeout set");
        require(block.timestamp > execution.phaseTimeouts[phaseIndex], "Not yet timed out");
        require(execution.phaseStatuses[phaseIndex] == PhaseStatus.ACTIVE || 
                execution.phaseStatuses[phaseIndex] == PhaseStatus.CONDITIONAL_WAITING, "Phase not active");
        
        execution.phaseStatuses[phaseIndex] = PhaseStatus.TIMED_OUT;
        emit PhaseTimedOut(executionId, phaseIndex);
        
        _handlePhaseFailure(executionId, phaseIndex, "Timeout");
    }
    
    /**
     * @notice Complete a phase
     */
    function _completePhase(bytes32 executionId, uint256 phaseIndex, bytes memory result) internal {
        WorkflowExecution storage execution = executions[executionId];
        execution.phaseStatuses[phaseIndex] = PhaseStatus.COMPLETED;
        execution.phaseResults[phaseIndex] = result;
        
        emit PhaseCompleted(executionId, phaseIndex, result);
        
        _tryAdvanceWorkflow(executionId);
    }
    
    /**
     * @notice Handle phase failure
     */
    function _handlePhaseFailure(bytes32 executionId, uint256 phaseIndex, string memory reason) internal {
        WorkflowExecution storage execution = executions[executionId];
        execution.phaseStatuses[phaseIndex] = PhaseStatus.FAILED;
        
        emit PhaseFailed(executionId, phaseIndex, reason);
        
        // Mark entire workflow as failed
        execution.isComplete = true;
        execution.successful = false;
        execution.completionTime = block.timestamp;
        
        emit WorkflowCompleted(executionId, false);
    }
    
    /**
     * @notice Build payload for phase including results from dependencies
     */
    function _buildPhasePayload(bytes32 executionId, uint256 phaseIndex) internal view returns (bytes memory) {
        WorkflowExecution storage execution = executions[executionId];
        WorkflowDefinition storage workflow = workflows[execution.workflowId];
        PhaseDefinition storage phase = workflow.phases[phaseIndex];
        
        // Start with initial payload
        bytes memory payload = execution.initialPayload;
        
        // Add results from dependency phases
        bytes[] memory dependencyResults = new bytes[](phase.dependencies.length);
        for (uint i = 0; i < phase.dependencies.length; i++) {
            uint32 depIndex = phase.dependencies[i];
            dependencyResults[i] = execution.phaseResults[depIndex];
        }
        
        return abi.encode(payload, dependencyResults, phase.metadata);
    }
    
    /**
     * @notice Validate trigger condition
     */
    function _validateTriggerCondition(bytes memory condition, bytes memory triggerData) internal pure returns (bool) {
        if (condition.length == 0) {
            return true; // No condition means always valid
        }
        
        (TriggerConditionType conditionType, bytes memory params) = abi.decode(condition, (TriggerConditionType, bytes));
        
        if (conditionType == TriggerConditionType.PRICE_THRESHOLD) {
            (uint256 threshold, bool isGreater) = abi.decode(params, (uint256, bool));
            uint256 price = abi.decode(triggerData, (uint256));
            return isGreater ? price >= threshold : price <= threshold;
        } else if (conditionType == TriggerConditionType.TIME_THRESHOLD) {
            uint256 targetTime = abi.decode(params, (uint256));
            return block.timestamp >= targetTime;
        } else if (conditionType == TriggerConditionType.DATA_HASH) {
            bytes32 expectedHash = abi.decode(params, (bytes32));
            return keccak256(triggerData) == expectedHash;
        } else if (conditionType == TriggerConditionType.ORACLE_VALUE) {
            (uint256 expectedValue, uint256 tolerance) = abi.decode(params, (uint256, uint256));
            uint256 actualValue = abi.decode(triggerData, (uint256));
            return actualValue >= expectedValue - tolerance && actualValue <= expectedValue + tolerance;
        }
        
        return false;
    }
    
    /**
     * @notice Check if address is authorized to trigger conditional phases
     */
    function _isAuthorizedTrigger(bytes32 executionId, address triggerer) internal view returns (bool) {
        WorkflowExecution storage execution = executions[executionId];
        WorkflowDefinition storage workflow = workflows[execution.workflowId];
        
        return authorizedTriggerSources[triggerer] || 
               workflow.authorizedTriggers[triggerer] ||
               triggerer == workflow.creator;
    }
    
    /**
     * @notice Aggregate coordination responses
     */
    function _aggregateCoordinationResponses(bytes32 executionId, uint256 phaseIndex) internal view returns (bytes memory) {
        // Simple voting mechanism - return most common response
        // In a real implementation, this would be more sophisticated
        return abi.encode("consensus_result");
    }
    
    /**
     * @notice Check if workflow is complete
     */
    function _checkWorkflowCompletion(bytes32 executionId) internal {
        WorkflowExecution storage execution = executions[executionId];
        WorkflowDefinition storage workflow = workflows[execution.workflowId];
        
        if (execution.isComplete) return;
        
        bool allCompleted = true;
        bool anyFailed = false;
        
        for (uint i = 0; i < workflow.phases.length; i++) {
            PhaseStatus status = execution.phaseStatuses[i];
            if (status == PhaseStatus.FAILED || status == PhaseStatus.TIMED_OUT) {
                anyFailed = true;
                break;
            }
            if (status != PhaseStatus.COMPLETED) {
                allCompleted = false;
            }
        }
        
        if (allCompleted || anyFailed) {
            execution.isComplete = true;
            execution.successful = allCompleted && !anyFailed;
            execution.completionTime = block.timestamp;
            emit WorkflowCompleted(executionId, execution.successful);
        }
    }
    
    // Admin functions
    function authorizeWorkflowCreator(address creator) external {
        require(msg.sender == feeCollector, "Only admin");
        authorizedWorkflowCreators[creator] = true;
        emit WorkflowCreatorAuthorized(creator);
    }
    
    function authorizeTriggerSource(address triggerSource) external {
        require(msg.sender == feeCollector, "Only admin");
        authorizedTriggerSources[triggerSource] = true;
        emit TriggerSourceAuthorized(triggerSource);
    }
    
    function setFees(uint256 _workflowCreationFee, uint256 _phaseExecutionFee) external {
        require(msg.sender == feeCollector, "Only admin");
        workflowCreationFee = _workflowCreationFee;
        phaseExecutionFee = _phaseExecutionFee;
    }
    
    // View functions
    function getWorkflow(bytes32 workflowId) external view returns (
        string memory name,
        address creator,
        uint256 phaseCount,
        bool isActive,
        uint256 totalStake
    ) {
        WorkflowDefinition storage workflow = workflows[workflowId];
        return (workflow.name, workflow.creator, workflow.phases.length, workflow.isActive, workflow.totalStake);
    }
    
    function getExecution(bytes32 executionId) external view returns (
        bytes32 workflowId,
        address initiator,
        bool isComplete,
        bool successful,
        uint256 completionTime
    ) {
        WorkflowExecution storage execution = executions[executionId];
        return (execution.workflowId, execution.initiator, execution.isComplete, execution.successful, execution.completionTime);
    }
    
    function getPhaseStatus(bytes32 executionId, uint256 phaseIndex) external view returns (PhaseStatus) {
        return executions[executionId].phaseStatuses[phaseIndex];
    }
    
    function getPhaseResult(bytes32 executionId, uint256 phaseIndex) external view returns (bytes memory) {
        return executions[executionId].phaseResults[phaseIndex];
    }
}