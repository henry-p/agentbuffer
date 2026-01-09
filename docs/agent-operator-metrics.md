# Agent Operator Metrics

This document defines a metrics suite for tracking how effectively an operator keeps agents productive while separating agent capacity limits from operator ideation and response bottlenecks. It is written to align with AgentBuffer's current data model (Codex session logs, running/idle states, idle threshold crossings) and can be implemented incrementally.

## Goals

- Measure how well you keep agents running with minimal idle time.
- Distinguish between operator bottlenecks (slow task handoffs, low task supply) and agent-side constraints (long runtimes).
- Provide decision-ready metrics that guide actions (refill tasks, reduce task size, increase agent count, or pause).
- Keep metrics interpretable with minimal instrumentation beyond existing logs.

## Definitions and Data Model

### Entities

- **Agent session**: A contiguous run of a single agent in the terminal. Identified by a session ID.
- **Task**: A unit of work assigned to an agent. In Codex logs, this is implied by a user message that starts a new work segment.
- **Running state**: Latest event in session is a user prompt (agent is actively working).
- **Idle state**: Latest event in session is an assistant completion (agent is waiting).
- **Finished event**: A transition from running to idle.
- **Assignment event**: A transition from idle to running (new user prompt).

### Timestamps

- `t_start`: time when a session first appears.
- `t_finish`: time when the latest assistant completion occurs.
- `t_assign`: time when a new user message is sent to an idle agent.

### Derived time intervals

- **Agent running interval**: from `t_assign` to `t_finish`.
- **Agent idle interval**: from `t_finish` to next `t_assign` (or current time if still idle).
- **Operator response interval**: for a given agent, from `t_finish` to next `t_assign`.

### Notes on Codex logs

- Logs only show compaction completion, not start; treat compaction events as assistant completions (idle) to avoid false running states.
- Use the latest non-bootstrap user message as the task title (already standard in AgentBuffer).

## Core Effectiveness Metrics

These should be the default KPIs.

### 1) Active Utilization

How much of total agent time is spent running tasks.

```
Active Utilization = Running agent-minutes / Total agent-minutes
```

- Compute over a time window (e.g., last hour, day, week).
- This is the single best signal for overall operator effectiveness.

### 2) Operator Response Time

How quickly you refill an agent after it finishes.

```
Operator Response Time = median(t_assign - t_finish) across assignments
```

- Use median (or p75/p90) to avoid outliers.
- High values indicate you are the bottleneck, not the agents.

### 3) Idle Share Over Threshold

How often your idle ratio exceeds a threshold (e.g., > 40% idle).

```
Idle Over Threshold = minutes(idle_ratio >= threshold) / total minutes
```

- This aligns with AgentBuffer's alerting semantics.
- Tracks periods of sustained under-utilization, not just averages.

### 4) Throughput

Tasks completed per unit time.

```
Throughput = completed tasks / time window
```

- Pair with utilization to avoid optimizing for long, low-output tasks.

## Bottleneck Separation Metrics

These help distinguish "agent capacity" vs "operator ideation" vs "task quality" problems.

### 5) Task Supply Rate

How quickly you create new tasks.

```
Task Supply Rate = assignments / time window
```

- If utilization drops while supply rate drops, the bottleneck is ideation.

### 6) Agent Demand Gap

How many agents you want running vs. how many actually are.

```
Agent Demand Gap = target_running_slots - actual_running
```

- Target slots can be static (e.g., 8) or dynamic (e.g., based on day/time).
- Negative gap means you are ahead (over-supplied with running agents).

### 7) Operator Bottleneck Index

Normalize response time by task runtime to assess your relative delay.

```
Bottleneck Index = median(response_time) / median(task_runtime)
```

- If > 0.2-0.3, operator delay is significant relative to task length.

## Quality and Efficiency Guardrails

These prevent "busy" from being mistaken as "effective".

### 8) Rework Rate

Tasks that require follow-up or re-clarification shortly after completion.

```
Rework Rate = reworked tasks / total tasks
```

- Requires a simple heuristic: a follow-up task with same session and similar title within X minutes.
- High rework suggests unclear or over-scoped tasks.

### 9) Task Fragmentation

How often tasks are split into multiple smaller prompts within the same session.

```
Fragmentation = prompts per task
```

- High fragmentation can be healthy (iterative work) or a sign of poor initial prompts.
- Track as a diagnostic, not a headline KPI.

### 10) Long-Tail Runtime

How much time is spent in the slowest tasks.

```
Long-Tail Runtime = p90(task_runtime)
```

- If p90 grows while throughput declines, task sizing may be off.

## Recommended KPI Dashboard

If you only show a few metrics, show these:

- **Active Utilization** (last hour, last day)
- **Operator Response Time** (median + p90)
- **Idle Over Threshold** (minutes above threshold)
- **Throughput** (tasks/day)
- **Bottleneck Index**

## Visualization Suggestions

- **Time-series band**: running vs idle ratio over the last 24h.
- **Histogram**: operator response time distribution (bin by minutes).
- **Sparkline**: utilization per day across last 14 days.
- **Stacked bar**: runtime vs idle per day.
- **Small multiples**: per-agent runtime to find persistent stragglers.

## Suggested Targets (Starting Points)

These are intentionally conservative and should be tuned per workflow.

- **Active Utilization**: 70-85% (higher is better, but watch for burnout).
- **Operator Response Time**: p50 < 10 minutes, p90 < 45 minutes.
- **Idle Over Threshold**: < 10% of time above threshold.
- **Bottleneck Index**: < 0.25.

## Implementation Notes (AgentBuffer)

### Data already available

- Session ID, last user message timestamp, last assistant message timestamp.
- Running/idle state transitions.
- History of finished sessions.

### Data you may add later (optional)

- Manual task tags or priority (from UI).
- Explicit "task complete" markers (if agent supports it).
- Task size estimates (small/medium/large) as a quick input.

### Windowing and Aggregation

- Use rolling windows (last 60 minutes, last 24 hours, last 7 days).
- For longer horizons, show daily aggregates to smooth volatility.

### Edge cases

- A session with no user message should not count as running.
- A session that ends without a terminal completion should be excluded or marked unknown.
- Compaction events should not be treated as running; only as completions.

## Metric Computation Examples

### Utilization from event streams

```
For each minute in window:
  running = count(sessions where last_event == user)
  total = count(active sessions)
  utilization_minute = running / max(total, 1)
Overall utilization = average(utilization_minute)
```

### Operator response time

```
For each session:
  for each finish event:
    find next assignment event
    response_time = next_assign - finish
Median across response_time values
```

## Interpreting Signals

- **Utilization down + response time up**: operator bottleneck (refill faster).
- **Utilization down + supply rate down**: ideation bottleneck (create task bank).
- **Utilization steady + throughput down + runtime up**: tasks too large or ambiguous.
- **Rework up**: task spec clarity issue; invest in better prompts.

## Quick Actions Tied to Metrics

- **Response time spikes**: set a fixed "refill interval" or batch task creation.
- **Supply rate drops**: maintain a backlog list of task ideas.
- **Long-tail runtime**: split tasks or add acceptance criteria.
- **Idle over threshold**: reduce agent count temporarily or schedule refill blocks.

## Privacy and Safety

- Avoid storing raw task titles if you prefer privacy; hash titles and keep only stats.
- Metrics should remain aggregate and not store full content or PII.

## Next Implementation Step (Low Effort)

1. Start computing utilization, response time, and idle threshold minutes.
2. Add daily aggregates for throughput and response time distribution.
3. Visualize in a small "Operator" section in the popover or settings.

---

This metrics set is designed to be simple to compute, hard to misinterpret, and directly tied to operational choices. It should give you a reliable read on whether the limiting factor is agent capacity or your own ability to supply and refill tasks.
