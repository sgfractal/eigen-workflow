# Updated Hourglass Architecture

## Layer 1: Application Layer
```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Simple Apps   │    │  Complex Apps   │    │  DeFi Protocols │
│                 │    │                 │    │                 │
│ • Quick tasks   │    │ • Multi-step    │    │ • Liquidations  │
│ • Validations   │    │ • Orchestration │    │ • Settlements   │
│ • Computations  │    │ • Workflows     │    │ • Risk mgmt     │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         │                       │                       │
         ▼                       ▼                       ▼
```

## Layer 2: Coordination Layer
```
┌─────────────────────────────────────────────────────────────────┐
│                   WORKFLOW STATE MACHINE                        │
│                                                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│  │ IMMEDIATE   │  │COORDINATION │  │ CONTINUOUS  │            │
│  │             │  │             │  │             │            │
│  │ • Task-like │  │ • Multi-sig │  │ • Monitoring│            │
│  │ • Quick ops │  │ • Consensus │  │ • Streaming │            │
│  └─────────────┘  └─────────────┘  └─────────────┘            │
│                                                                 │
│  ┌─────────────┐  ┌─────────────┐                              │
│  │CONDITIONAL  │  │AGGREGATION  │                              │
│  │             │  │             │                              │
│  │ • Triggers  │  │ • Combine   │                              │
│  │ • Events    │  │ • Summarize │                              │
│  └─────────────┘  └─────────────┘                              │
└─────────────────────────────────────────────────────────────────┘
         │                       │                       │
         │                       │                       │
         ▼                       ▼                       ▼
```

## Layer 3: Execution Layer (Existing Hourglass)
```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   TaskMailbox   │    │ TaskAVSRegistrar│    │  AVSTaskHook    │
│                 │    │                 │    │                 │
│ • Task mgmt     │    │ • Operator reg  │    │ • Validation    │
│ • Result verify │    │ • BLS keys      │    │ • Fee markets   │
│ • State tracking│    │ • Endpoints     │    │ • Hooks         │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         │                       │                       │
         ▼                       ▼                       ▼
```

## Layer 4: Operator Layer
```
┌─────────────────┐                      ┌─────────────────┐
│   Aggregator    │◄────────────────────►│    Executor     │
│                 │                      │                 │
│ • Task distrib  │                      │ • Run performers│
│ • Result aggr   │                      │ • Sign results  │
│ • BLS threshold │                      │ • Container mgmt│
└─────────────────┘                      └─────────────────┘
         │                                        │
         │                                        │
         ▼                                        ▼
┌─────────────────────────────────────────────────────────────────┐
│                         Performer                               │
│                      (AVS Logic)                               │
└─────────────────────────────────────────────────────────────────┘
```

## Integration Points

### 1. WorkflowStateMachine → TaskMailbox
- IMMEDIATE phases create traditional tasks
- Leverages existing operator infrastructure
- Maintains compatibility with simple AVSs

### 2. WorkflowStateMachine → Operator Sets  
- Uses same operator registration system
- Extends with workflow-specific coordination
- Adds new consensus mechanisms

### 3. Enhanced Capabilities
- **State Persistence**: Long-running workflows
- **Complex Dependencies**: Multi-phase orchestration  
- **Conditional Logic**: Event-driven execution
- **Multi-Actor Coordination**: Consensus mechanisms
- **Temporal Operations**: Time-based triggers
