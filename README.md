# Pierce County M365 MCP Server - Agentic Enterprise Orchestration Platform

## EXECUTIVE SUMMARY

The Pierce County M365 MCP Server is an enterprise-grade, agentic automation platform that provides secure, auditable, and self-orchestrating Microsoft 365 administration through the Model Context Protocol (MCP). This bulletproof, modular architecture delivers autonomous tool chaining, intelligent entity parsing, persistent context management, and comprehensive compliance enforcement for the Pierce County GCC tenant.

## ARCHITECTURAL OVERVIEW

### Core Principles
- **Agentic Orchestration**: Autonomous reasoning, tool selection, and workflow execution
- **Zero-Trust Security**: Comprehensive validation, audit trails, and threat detection
- **Enterprise Compliance**: GCC-compliant with SOC 2, FISMA, and NIST frameworks
- **Self-Healing**: Automatic error recovery, context correction, and performance optimization
- **Modular Design**: Plugin-based architecture for extensibility and maintainability
- **Cross-Platform Compatibility**: Operates uniformly across VS Code, Copilot Studio, and AIFoundry

### System Architecture

```
src/
├── MCPServer.ps1                    # Main MCP server entrypoint
├── Core/                           # Enterprise core modules
│   ├── OrchestrationEngine.ps1     # Agentic workflow orchestration
│   ├── EntityExtractor.ps1         # Intelligent entity parsing & normalization
│   ├── ValidationEngine.ps1        # Compliance & security validation
│   ├── ToolRegistry.ps1           # Dynamic tool discovery & execution
│   ├── Logger.ps1                 # Enterprise audit logging
│   ├── OrchestrationTypes.ps1     # Shared orchestration classes & enums
│   ├── SecurityManager.ps1        # Security enforcement & threat detection
│   ├── ContextManager.ps1         # Persistent context & relationship tracking
│   ├── VectorMemoryBank.ps1       # Advanced vector-based memory system
│   ├── InternalReasoningEngine.ps1 # Automated reasoning and resolution (legacy PowerShell)
│   ├── ../python/internal_reasoning_engine.py # Python-based reasoning engine
│   ├── ConfidenceEngine.ps1       # Statistical confidence interval engine
│   ├── CodeExecutionEngine.ps1    # Sandboxed code execution service
│   ├── WebSearchEngine.ps1        # Lightweight web search for reasoning
│   └── SemanticIndex.ps1          # Open-source semantic search & embeddings
└── Tools/                         # MCP tool implementations
    ├── Accounts/                  # Account lifecycle management
    ├── Mailboxes/                # Mailbox & permissions management
    ├── Groups/                   # Distribution lists & M365 groups
    ├── Resources/                # Calendar & resource management
    └── Administration/           # Administrative & lookup tools
```

## AGENTIC CAPABILITIES

### Autonomous Orchestration
- **Intent Recognition**: Natural language request parsing and entity extraction
- **Workflow Planning**: Multi-step automation with dependency resolution
- **Context Persistence**: Advanced vector-based memory with semantic search
- **Self-Correction**: Automatic error detection, analysis, and remediation
- **Fuzzy Entity Correction**: Misspelled users and mailboxes are automatically
  corrected using context-driven fuzzy matching
- **Internal Reasoning Engine**: Aggregates context to resolve ambiguity and errors automatically
- **Autonomous Execution**: All tools run without confirmation prompts; the reasoning engine handles corrections silently
- **Rule-Based Fallback Parsing**: Regex and dictionary extraction when AI confidence is low
- **Confidence Interval Engine**: Measures statistical confidence for every action
- **Sandboxed Code Execution**: Validate and simulate scripts in a secure sandbox
- **Performance Learning**: Continuous optimization based on execution patterns
- **Memory Intelligence**: Long-term organizational knowledge and pattern recognition
- **Checkpointing & Dynamic Routing**: Persistent checkpoints and adaptive plan optimization ensure context is never lost

### Enterprise Intelligence
- **Entity Validation**: Comprehensive Pierce County naming convention enforcement
- **Security Analysis**: Real-time threat detection and compliance verification
- **Relationship Mapping**: Dynamic organizational structure understanding
- **Predictive Optimization**: AI-driven resource management and license recovery
- **Vector Memory Bank**: Semantic search across historical operations and context
- **Pattern Analysis**: Automated detection of operational patterns and anomalies
- **Table-Driven State Machines**: Deterministic workflows with explicit transitions

## MEMORY & INTELLIGENCE SYSTEM

### Vector Memory Bank
The system includes a sophisticated, open-source vector memory bank that provides:
- **Semantic Memory Storage**: Content stored with vector embeddings for semantic similarity search
- **Conversation History**: Complete context preservation across sessions
- **Entity Intelligence**: Deep understanding of user, mailbox, and resource relationships
- **Pattern Recognition**: Automated detection of operational patterns and anomalies
- **Predictive Analytics**: AI-driven predictions for user needs and system optimization
- **Sliding Window Memory**: Low-importance context stored using a 50-item sliding window to control growth and remove duplicates

### Internal Reasoning Engine
The Internal Reasoning Engine aggregates session context, historical actions, and tool outputs to automatically analyze errors or ambiguous input. It now performs predictive plan optimization and dynamic rerouting when failures occur. All checkpoints are persisted for recovery and no workflow requires human confirmation.

The release candidate introduces an improved context aggregation routine that normalizes session data and removes ambiguity before analysis. This enhancement enables more accurate corrections and allows the engine to generate self-healing plans with minimal iteration.

The engine now performs fuzzy matching against organizational directories when validation errors occur, automatically correcting mistyped user or mailbox names whenever possible.

**Python Implementation**

To support advanced reasoning and easier integration with AI libraries, the reasoning component has been refactored into a standalone Python module located in `src/python/internal_reasoning_engine.py`. The PowerShell orchestration engine invokes this module for complex analysis, ensuring language-agnostic operation and modern extensibility.

```powershell
$issue = @{ Type = 'ValidationFailure'; ValidationResult = $result }
$resolution = $server.OrchestrationEngine.ReasoningEngine.Resolve($issue, $session)
```

### Confidence Interval Engine
The Confidence Interval Engine continuously measures statistical confidence for entity extraction, validation, tool execution, and overall workflows. It calculates Wilson score intervals using historical outcomes and logs metrics for audit. When any lower bound falls below 95%, the engine invokes the Internal Reasoning Engine to re-analyze context and apply corrective strategies.

```powershell
$metrics = $server.OrchestrationEngine.ConfidenceEngine.Evaluate('ToolExecution', 0.95)
if (-not $metrics.IsHighConfidence) {
    $server.OrchestrationEngine.ReasoningEngine.Resolve(@{ Type='LowConfidence'; Stage='ToolExecution'; Metrics=$metrics }, $session)
}
```

### Sandboxed Code Execution Engine
The Code Execution Engine executes and validates code snippets in a secure sandbox with strict timeouts and input sanitization. Use the `code/execute` API to perform dry-run syntax checks or controlled execution with full logging.

```powershell
$exec = $server.OrchestrationEngine.CodeExecutionEngine.Execute('PowerShell', $code, $params, 10, $true)
```

### Web Search Engine
The Web Search Engine integrates open search endpoints (such as DuckDuckGo) without relying on proprietary APIs. It is invoked exclusively by the Confidence Interval Engine when a low-confidence situation is detected and before the Internal Reasoning Engine is executed. Results are rate limited, parsed, and passed directly to the reasoning engine for deeper analysis.

```powershell
$search = $server.OrchestrationEngine.WebSearchEngine.Search('m365 mailbox delegation audit', 5)
```

### Memory Architecture
- **TF-IDF Vectorization**: Open-source term frequency-inverse document frequency analysis
- **Cosine Similarity**: Semantic search using mathematical similarity measurements
- **Persistent Storage**: Enterprise-grade memory persistence with automated cleanup
- **Context Correlation**: Multi-dimensional relationship mapping and analysis
- **Learning Algorithms**: Continuous improvement through pattern analysis

### Intelligence Features
- **Smart Suggestions**: Context-aware recommendations based on historical patterns
- **Anomaly Detection**: Automatic identification of unusual access patterns or requests
- **Predictive Maintenance**: Proactive identification of potential issues or optimizations
- **Behavioral Analysis**: Understanding of user and system interaction patterns
- **Knowledge Graph**: Dynamic organizational relationship mapping and traversal

## SECURITY & COMPLIANCE

### Security Framework
- **Zero-Trust Architecture**: Every operation validated and authenticated
- **Principle of Least Privilege**: Granular permission enforcement
- **Comprehensive Audit Trails**: Full operation logging for compliance
- **Threat Detection**: Real-time security monitoring and alerting
- **Data Protection**: Sensitive information masking and secure storage

### GCC Compliance
- **FISMA Moderate**: Federal security controls implementation
- **SOC 2 Type II**: Annual compliance certification
- **NIST Cybersecurity Framework**: Risk management alignment
- **Pierce County IT Standards**: Local policy enforcement

## ENTERPRISE FEATURES

### Operational Excellence
- **High Availability**: Fault-tolerant design with automatic failover
- **Scalability**: Horizontal scaling for enterprise workloads
- **Performance Monitoring**: Real-time metrics and alerting
- **Watchdog & Health Checks**: Automated service monitoring and self-healing routines
- **Disaster Recovery**: Automated backup and restoration capabilities
- **Change Management**: Version control and rollback procedures

### Integration Capabilities
- **Microsoft Graph API**: Full M365 service integration
- **Exchange Online PowerShell**: Advanced mailbox management
- **Azure Active Directory**: Identity and access management
- **Power Platform**: Custom workflow integration
- **ServiceNow**: ITSM integration for ticket management

## INSTALLATION & DEPLOYMENT

### Prerequisites
- PowerShell 7.0 or later
- Microsoft Graph PowerShell SDK
- Exchange Online PowerShell V3
- Appropriate M365 administrative permissions
- Visual Studio Code (for MCP integration)
- Copilot Studio or AIFoundry compatible environment
- Python 3.10+ (for the internal reasoning engine)
- `requests` library for Python

### Quick Start
1. Clone the repository to your local machine
2. Configure the MCP server using `.vscode/mcp.json` (works in VS Code, Copilot Studio, or AIFoundry)
3. Initialize the tool registry with your organizational parameters
4. Install Python dependencies with `pip install -r requirements.txt`
5. Begin issuing natural language automation requests
6. For a very simple overview, read `docs/HOW-TO-USE.md`
7. Validate the installation by running `./scripts/test-core-modules.ps1`. This
   script loads core modules in dependency order starting with `Logger.ps1` and
   the new `OrchestrationTypes.ps1` definitions.

### Configurable AI Model Providers
AI providers are defined in `mcp.config.json`. Each provider entry includes an endpoint, model name, authentication, and timeout. Example:

```json
{
  "DefaultAIProvider": "OllamaLocal",
  "AIProviders": [
    {
      "Name": "OllamaLocal",
      "Type": "REST",
      "Endpoint": "http://localhost:11434/api/generate",
      "Model": "llama2",
      "TimeoutSec": 30
    }
  ]
}
```

Swap providers or add new ones by editing this file and restarting the server. No code changes are required.

### Autostart Service
Use `scripts/install-autostart.ps1` to register the watchdog service that keeps
the MCP server running. The script detects Windows or Linux and installs either
a Windows service or a systemd unit which launches `watchdog.ps1`. Run the
script with administrative privileges so the server starts automatically and
recovers from failures.

### Enterprise Deployment
For production environments, refer to the deployment guide in `/docs/deployment/` for:
- Service account configuration
- Network security requirements
- Monitoring and alerting setup
- Disaster recovery procedures

## USAGE EXAMPLES

### Account Lifecycle Management
```
"Deprovision john.smith@piercecountywa.gov and transfer mailbox to manager@piercecountywa.gov"
```

### Permission Management
```
"Grant Karen Carston and Mike Johnson access to the Facilities Division calendar with reviewer permissions"
```

### Resource Creation
```
"Create a shared mailbox for Public Works Fleet Management with fleet.pw@piercecountywa.gov"
```

### Bulk Operations
```
"Remove all distribution list memberships for departing employees in the July 2024 termination report"
```

### Code Execution Validation
```
"Test the script 'Get-Mailbox -Identity user@domain' in dry-run mode"
```

## API REFERENCE

### Core Tools
- `deprovision_account`: Complete account deprovisioning workflow
- `add_mailbox_permissions`: Granular mailbox access management
- `new_shared_mailbox`: Automated shared mailbox provisioning
- `set_calendar_permissions`: Calendar access control
- `department_lookup`: Organizational structure queries

### Administrative Tools
- `dynamic_admin_script`: AI-generated PowerShell automation
- `get_ad_object_attributes`: Active Directory queries
- `get_entra_object_attributes`: Azure AD object inspection
- `code_execution`: Secure sandboxed script execution and validation
- `pr_suggestion`: Automatic draft and submission of pull requests with full test logs

### Asynchronous Execution
Use `tools/callAsync` to submit a request without waiting for completion. The server returns a `jobId` that can be polled with `tools/result` to retrieve the final output when ready.

## MONITORING & TELEMETRY

### Performance Metrics
- Request processing latency
- Tool execution success rates
- Security validation effectiveness
- Context accuracy measurements
- Confidence interval measurements
- Resource utilization patterns
- Server health status

### Audit Capabilities
- Complete operation trail logging
- Security event correlation
- Compliance reporting automation
- Performance analytics dashboards
- Predictive maintenance alerts

## TROUBLESHOOTING

### Common Issues
- **Authentication Failures**: Verify service account permissions
- **Tool Execution Errors**: Check PowerShell execution policies
- **Performance Degradation**: Review resource allocation and scaling
- **Compliance Violations**: Validate organizational standards alignment

### Support Resources
- Internal documentation: `/docs/`
- Issue tracking: Jira ITSM integration
- Emergency contacts: Pierce County CoE
- Knowledge base: SharePoint team site

## GOVERNANCE & MAINTENANCE

### Version Control
- Git-based source control with branch protection
- Automated testing and validation pipelines
- Change approval workflows through ServiceNow
- Documentation synchronization with code changes
- **Internal PR Suggestion Tool**: Automatically drafts and submits pull requests for
  all code changes, attaches test logs, and notifies maintainers. No change is merged
  without human review and approval.

### Continuous Improvement
- Monthly performance reviews and optimization
- Quarterly security assessments and updates
- Annual compliance audits and certifications
- User feedback integration and feature development

### Using the PR Suggestion Tool
The `PRSuggestionEngine` module automates code change packaging into pull requests. Example:

```powershell
$engine = [PRSuggestionEngine]::new('C:\Repo')
$tests = @('.\scripts\test-core-modules.ps1', '.\scripts\test-syntax.ps1')
$engine.SuggestPullRequest('Update validation logic', $tests)
```

The engine commits local changes to a dedicated branch, runs the provided tests, creates
a pull request via `gh`, logs the activity, and sends a Teams notification.

## TECHNICAL SPECIFICATIONS

### System Requirements
- **CPU**: 4+ cores recommended for production
- **Memory**: 8GB RAM minimum, 16GB recommended
- **Storage**: 50GB available space for logs and cache
- **Network**: Persistent internet connectivity to Microsoft 365
- **Operating System**: Windows 10/11 or Windows Server 2019+

### Performance Characteristics
- **Concurrent Users**: Up to 100 simultaneous operations
- **Response Time**: Sub-second for simple operations
- **Throughput**: 1000+ operations per hour sustained
- **Availability**: 99.9% uptime SLA with proper deployment

### System Resource Management
- Sliding window cleanup keeps memory usage stable and prevents duplicate low-priority entries

## CHANGELOG

### Version 2.1.0-rc (Current)
- Complete architectural overhaul to agentic orchestration
- Enhanced security and compliance framework
- Modular core engine implementation
- Persistent context and relationship management
- Advanced entity extraction and validation
- Rule-based parsing fallback for low-confidence scenarios
- Table-driven state machines for deterministic workflows

### Version 1.0.1 (Legacy)
- Basic MCP server implementation
- Core M365 administrative tools
- PowerShell 5.1 compatibility
- Foundation security features

## LICENSE

Copyright (c) 2024 Pierce County Washington
Licensed under the Pierce County IT Standards and Governance Framework

This software is for internal Pierce County use only and may not be distributed, modified, or used outside of the authorized Pierce County technology environment without explicit written permission from Pierce County IT Solutions Architecture.

## SUPPORT CONTACTS

- **Architecture Lead**: Pierce County IT Solutions Architecture
- **Operations Support**: Pierce County IT Operations Center
- **Security Escalation**: Pierce County Information Security Office
- **Compliance Questions**: Pierce County IT Governance Office

---

*Last Updated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss") UTC*
*Version: 2.1.0-rc*
*Build: $(Get-Random)*
