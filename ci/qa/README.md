# QA explore

Pigeon's exploratory QA: an agent uses the app in an iOS simulator through Maestro's MCP
server and writes a report; it changes no code. The workflow's header
(`.github/workflows/qa-explore.yml`) is the manual: modes, inputs, what the agent may do, and
where the report lands.

- Run one: Actions › QA explore › Run workflow (or the API's workflow dispatch), on the branch to
  test. Keep a test short (`minutes` 5–10, `max_budget_usd` a few dollars). Look at the Actions
  runs of every app first: the account's macOS runners are shared.
- Read a report: `git fetch origin refs/qa-runs/<run id>:refs/qa-runs/<run id>`, then
  `git show refs/qa-runs/<run id>:STATUS.md` and `session/report.md`; the `qa` artifact holds the
  same, `qa-video` the screen recording.
- Drive it from elsewhere (a cloud session, no secret needed): `mode: relay` and
  `python3 ci/qa/qa.py send <run id> <calls.json>` (its docstring).
- Agent mode needs the secret `ANTHROPIC_API_KEY` or `CLAUDE_CODE_OAUTH_TOKEN`.

Generated: every file in `ci/qa/` and the workflow come from one shared copy for all the apps
(painting-company row 152). Change them there and sync; an edit here is overwritten.
