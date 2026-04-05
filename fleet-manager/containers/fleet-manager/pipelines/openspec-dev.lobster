name: openspec-dev
steps:
  - id: create_flow
    command: node /app/pipelines/openspec-dev-step.js create-flow
  - id: approve_agents
    command: node /app/pipelines/openspec-dev-step.js agent-preview
    approval: required
  - id: enter_spec
    command: node /app/pipelines/openspec-dev-step.js resume-step create_spec_pr
    stdin: $create_flow.stdout
    condition: $approve_agents.approved
  - id: wait_for_spec_merge
    command: node /app/pipelines/openspec-dev-step.js wait spec_pr_review
    stdin: $create_flow.stdout
    condition: $approve_agents.approved
  - id: enter_implement
    command: node /app/pipelines/openspec-dev-step.js resume-step implement
    stdin: $create_flow.stdout
    condition: $approve_agents.approved
  - id: wait_for_impl_merge
    command: node /app/pipelines/openspec-dev-step.js wait ci_and_review
    stdin: $create_flow.stdout
    condition: $approve_agents.approved
  - id: approve_merge
    command: node /app/pipelines/openspec-dev-step.js merge-preview
    stdin: $create_flow.stdout
    approval: required
    condition: $approve_agents.approved
  - id: enter_review
    command: node /app/pipelines/openspec-dev-step.js resume-step review
    stdin: $create_flow.stdout
    condition: $approve_merge.approved
  - id: finish_flow
    command: node /app/pipelines/openspec-dev-step.js finish
    stdin: $create_flow.stdout
    condition: $approve_merge.approved
