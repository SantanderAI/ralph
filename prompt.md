# Example prompt

This file is the prompt sent to the agent on every iteration. Replace its
contents with your own task. Because each iteration starts a fresh session,
write the prompt so the agent rebuilds context from the workspace every time.

A good loop prompt typically tells the agent to:

1. Read the current plan / notes / TODO in this repository.
2. Make the smallest useful increment of progress toward the goal.
3. Run the tests and record what changed.
4. Create a `stop.md` file when the work is complete so the loop exits cleanly.
