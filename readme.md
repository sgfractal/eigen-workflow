# WorkflowStateMachine: Extending Hourglass for Multi-Stage AVS

## TL;DR

We've built a **WorkflowStateMachine contract** that adds complex workflow orchestration to EigenLayer's Hourglass framework **without requiring any changes to existing infrastructure**. This works entirely through the existing `TaskMailbox` interface and can be deployed today. We're sharing this with the EigenLayer team for transparency and potential collaboration opportunities.

## Why We Built This

The Hourglass framework is excellent for discrete, stateless tasks, but we needed to build multi-stage workflows with:
- **State persistence** between phases
- **Multi-party coordination** and consensus
- **Conditional execution** based on external triggers
- **Continuous monitoring** capabilities
- **Complex dependency management**

Rather than wait for framework changes, we built an **additive layer** that extends Hourglass capabilities while maintaining full compatibility.

## How It Works (No Changes Required)

### **Leverages Existing TaskMailbox Interface**
```solidity
// Our WorkflowStateMachine uses the standard TaskMailbox for simple phases
function _executeImmediatePhase(bytes32 executionId, uint256 phaseIndex) internal {
    ITaskMailbox.TaskParams memory taskParams = ITaskMailbox.TaskParams({
        refundCollector: execution.initiator,
        avsFee: 0,
        executorOperatorSet: OperatorSet({
            avs: address(this),  // WorkflowStateMachine as AVS
            id: phase.operatorSetId
        }),
        payload: phasePayload
    });
    
    bytes32 taskHash = taskMailbox.createTask(taskParams);  // Standard Hourglass call
}
```

### **Deploys as Standard AVS Contract**
The WorkflowStateMachine is simply another AVS contract that:
- Registers with the existing `TaskAVSRegistrar`
- Uses the existing `TaskMailbox` for appropriate phases
- Handles its own state management and coordination logic
- Appears as a normal AVS to all existing infrastructure

### **Extends TaskAVSRegistrar (Standard Pattern)**
```solidity
// Standard AVS extension - no framework changes needed
contract WorkflowAVSRegistrar is TaskAVSRegistrarBase {
    constructor(address avs, IAllocationManager allocationManager) 
        TaskAVSRegistrarBase(avs, allocationManager) {}
    
    // Can add workflow-specific operator validation if needed
}
```

## What We've Added (Additive Only)

### **1. Multi-Phase Execution Engine**
```solidity
enum PhaseType {
    IMMEDIATE,      // Uses existing TaskMailbox
    COORDINATION,   // New: Multi-party consensus
    CONTINUOUS,     // New: Ongoing monitoring  
    CONDITIONAL,    // New: Event-driven triggers
    AGGREGATION     // New: Multi-source combination
}
```

### **2. Workflow State Management**
```solidity
struct WorkflowExecution {
    bytes32 workflowId;
    uint256 currentPhase;
    PhaseStatus[] phaseStatuses;
    mapping(uint256 => bytes) phaseResults;    // Persistent state
    mapping(uint256 => mapping(address => bytes)) coordinationResponses;
    // ... extensive state tracking
}
```

### **3. Advanced Coordination Primitives**
```solidity
// Multi-party coordination with consensus thresholds
function submitCoordinationResponse(
    bytes32 executionId,
    uint256 phaseIndex, 
    bytes calldata response
) external {
    // Collect responses from multiple operators
    // Automatically advance when threshold reached
}
```

### **4. Conditional Trigger System**
```solidity
enum TriggerConditionType {
    PRICE_THRESHOLD,
    TIME_THRESHOLD,
    DATA_HASH,
    MULTI_SIG,
    ORACLE_VALUE
}

function triggerConditionalPhase(
    bytes32 executionId,
    uint256 phaseIndex,
    bytes memory triggerData
) external {
    // Validate trigger conditions and advance workflow
}
```

## Real-World Use Cases We're Enabling

### **Cross-Chain DeFi Protocol**
```solidity
// Example workflow definition
PhaseDefinition[] memory phases = new PhaseDefinition[](5);

phases[0] = PhaseDefinition({
    name: "Validate Collateral",
    phaseType: PhaseType.IMMEDIATE,    // Uses TaskMailbox
    timeout: 300,
    dependencies: new uint32[](0)
});

phases[1] = PhaseDefinition({
    name: "Multi-Sig Approval", 
    phaseType: PhaseType.COORDINATION,  // New capability
    consensusThreshold: 6667, // 66.67%
    dependencies: [0]
});

phases[2] = PhaseDefinition({
    name: "Wait for Bridge Confirmation",
    phaseType: PhaseType.CONDITIONAL,   // New capability
    triggerCondition: abi.encode(TriggerConditionType.DATA_HASH, expectedHash)
});
```

### **Decentralized Auditing Pipeline**
```solidity
// Continuous monitoring with multi-party coordination
phases[3] = PhaseDefinition({
    name: "Security Monitoring",
    phaseType: PhaseType.CONTINUOUS,    // New capability
    metadata: abi.encode(3600, 24)      // 1hr intervals, 24 updates
});
```

## Deployment Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│  Existing       │    │  Our             │    │  Existing       │
│  TaskMailbox    │◄───┤  WorkflowStateMachine │───►│  TaskAVSRegistrar│
└─────────────────┘    └──────────────────┘    └─────────────────┘
        ▲                        │                        ▲
        │                        │                        │
        ▼                        ▼                        ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│  Existing       │    │  New Workflow    │    │  Existing       │
│  Aggregator     │    │  Coordination    │    │  Executor       │
│  (no changes)   │    │  Logic           │    │  (no changes)   │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## Benefits for EigenLayer Ecosystem

### **Demonstrates Platform Extensibility**
- Shows how developers can build sophisticated applications on Hourglass
- Proves the framework's flexibility without requiring core changes
- Creates reference implementation for other complex AVS builders

### **Expands Use Case Coverage**
- **Current**: Simple computational tasks
- **With Workflows**: Complex business processes, cross-chain coordination, real-time monitoring

### **Zero Risk Integration**
- No changes to existing infrastructure
- Doesn't affect other AVS applications
- Can be deployed, tested, and iterated independently

## Technical Implementation Details

### **Workflow Registration**
```solidity
function registerWorkflow(
    string memory name,
    PhaseDefinition[] memory phases,
    address[] memory authorizedTriggers
) external payable returns (bytes32 workflowId) {
    // Validate phases and dependencies
    // Store workflow definition
    // Return unique workflow ID
}
```

### **Execution Management**
```solidity
function executeWorkflow(
    bytes32 workflowId,
    bytes memory payload
) external payable returns (bytes32 executionId) {
    // Create new execution instance
    // Initialize phase statuses
    // Start first eligible phases
}
```

### **Hybrid Phase Execution**
```solidity
function _startPhase(bytes32 executionId, uint256 phaseIndex) internal {
    PhaseType phaseType = workflow.phases[phaseIndex].phaseType;
    
    if (phaseType == PhaseType.IMMEDIATE) {
        _executeImmediatePhase(executionId, phaseIndex);      // Uses TaskMailbox
    } else if (phaseType == PhaseType.COORDINATION) {
        _executeCoordinationPhase(executionId, phaseIndex);   // New logic
    } else if (phaseType == PhaseType.CONTINUOUS) {
        _executeContinuousPhase(executionId, phaseIndex);     // New logic
    }
    // ... handle other phase types
}
```

## Current Status & Next Steps

### **✅ Completed**
- Core workflow engine implementation
- Integration with TaskMailbox interface
- Basic coordination and conditional execution
- Dependency management system

### **🚧 In Progress**
- Advanced trigger condition validation
- Cross-chain coordination primitives
- Performance optimizations
- Comprehensive testing suite

### **📋 Planned**
- Developer tools and documentation
- Reference implementations for common patterns
- Integration examples with popular DeFi protocols
