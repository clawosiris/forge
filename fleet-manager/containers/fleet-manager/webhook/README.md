# PR Merge Webhook

`pr-merged.js` is a standalone Node.js HTTP handler that watches GitHub
`pull_request` webhooks and resumes waiting ClawFlow runs when the matching PR
merges.

## Route

- `POST /webhook/github`

## Environment Variables

- `WEBHOOK_PORT`: listen port. Defaults to `9000`.
- `WEBHOOK_SECRET`: shared GitHub webhook secret. Required for signature
  validation.
- `FLOWS_DIR`: directory containing active flow JSON files. Defaults to
  `/app/flows/active`.
- `FLOW_CLI`: flow CLI path. Defaults to `/app/flow/flow.js`.

## GitHub Webhook Setup

1. In the GitHub repository, open Settings → Webhooks → Add webhook.
2. Set the payload URL to `http://<fleet-manager-host>:9000/webhook/github`.
3. Set content type to `application/json`.
4. Set the secret to the same value used for `WEBHOOK_SECRET`.
5. Subscribe to the `Pull requests` event.

When a merged PR matches a flow file:

- `outputs.spec_pr_url === pull_request.html_url` resumes the flow at
  `implement`
- `outputs.impl_pr_url === pull_request.html_url` resumes the flow at `review`

## Standalone Test

Start the handler:

```bash
mkdir -p /tmp/clawflow-test/active /tmp/clawflow-test/done
WEBHOOK_SECRET=test-secret \
FLOWS_DIR=/tmp/clawflow-test/active \
FLOW_CLI="$PWD/fleet-manager/flow/flow.js" \
node fleet-manager/webhook/pr-merged.js
```

Send a signed fixture:

```bash
body='{"action":"closed","pull_request":{"merged":true,"html_url":"https://github.com/clawosiris/forge/pull/123"}}'
sig=$(printf '%s' "$body" | openssl dgst -sha256 -hmac test-secret | sed 's/^.* //')
curl -i \
  -X POST http://127.0.0.1:9000/webhook/github \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: pull_request" \
  -H "X-Hub-Signature-256: sha256=$sig" \
  --data "$body"
```
