# Code Review: oidc-device-flow

Date: 2026-03-14
Review rounds: 3

## Round 1 Findings

### Functionality

- F1 [Critical] curl --fail in oidc_poll_token breaks RFC 8628 (HTTP 400 for authorization_pending/slow_down is expected) → RESOLVED: removed --fail, added -w '%{http_code}' status code extraction
- F2 [Critical] _OIDC_POLL_INTERVAL_OVERRIDE=0 causes infinite loop (elapsed never advances) → RESOLVED: added increment minimum 1
- F3 [Major] trap RETURN competition: oidc_get_certificate overrides ssh_with_oidc's trap → RESOLVED: manual rm -f cleanup at all return points
- F4 [Major] FORCE_OIDC path: `local oidc_exit_code=$?` resets $? to 0 → RESOLVED: separate declaration and assignment
- F5 [Major] ssh-keygen failure returns exit 2 (network) instead of exit 1 (local) → RESOLVED: return 1
- F6 [Minor] ensure_oidc_cert_dir symlink check after mkdir → RESOLVED: symlink check moved before mkdir

### Security

- S1 [Major] JSON injection in oidc_get_certificate: shell variables interpolated into JSON string → RESOLVED: jq -n --arg
- S2 [Major] Parameter injection in oidc_device_authorize: curl -d allows injection → RESOLVED: --data-urlencode

### Testing

- T1 [Critical] _OIDC_POLL_INTERVAL_OVERRIDE=0 infinite loop → Same as F2, RESOLVED
- T2 [Major] Exit code from ssh-keygen failure → Same as F5, RESOLVED
- T3 [Major] FORCE_OIDC exit code capture → Same as F4, RESOLVED

## Round 2 Findings

### Functionality

- F1 [Major] printf Authorization header missing trailing newline for curl -H @- → RESOLVED: added \n to format string
- F2 [Major] jq command failure unchecked in oidc_get_certificate → RESOLVED: added || { log_error; cleanup; return 1 }

### Security

- S1 [Major] HTTP status code not validated as numeric before arithmetic comparison → RESOLVED: regex check ^[0-9]+$
- S2 [Minor] OIDC_CERT_LIFETIME not validated as positive integer → NOT FIXED: CA server rejects invalid values; over-validation
- S3 [Minor] slow_down backoff unbounded → NOT FIXED: controlled by expires_in timeout
- S4 [Minor] OIDC_CA_PROVISIONER not validated → NOT FIXED: CA server validates; jq --arg prevents injection

### Testing

- T1 [Minor] OIDC tests not yet written → Acknowledged: separate planned task (Phase 2 Step 6)
- T2 [Minor] validate_oidc_urls edge cases → Acknowledged: will be covered in test writing task

## Round 3 Findings

No findings. All Round 2 fixes verified as correct and complete.

## Resolution Status

### Round 1

| ID | Severity | Problem | Action | File:Line |
|----|----------|---------|--------|-----------|
| F1 | Critical | curl --fail breaks RFC 8628 polling | Removed --fail, added HTTP status code extraction | smart-ssh:800-825 |
| F2 | Critical | _OIDC_POLL_INTERVAL_OVERRIDE=0 infinite loop | Added increment minimum 1 | smart-ssh:794-795 |
| F3 | Major | trap RETURN competition | Manual rm -f at all return points | smart-ssh:887-950 |
| F4 | Major | local resets $? in FORCE_OIDC path | Separate declaration and || assignment | smart-ssh:1410-1411 |
| F5 | Major | ssh-keygen failure exit 2 → 1 | Changed return 2 to return 1 | smart-ssh:892 |
| F6 | Minor | Symlink check after mkdir | Moved check before mkdir | smart-ssh:1004-1021 |
| S1 | Major | JSON injection via shell variables | jq -n --arg for JSON construction | smart-ssh:900-908 |
| S2 | Major | Parameter injection via curl -d | --data-urlencode | smart-ssh:733-734 |

### Round 2

| ID | Severity | Problem | Action | File:Line |
|----|----------|---------|--------|-----------|
| F1 | Major | Missing newline in Authorization header | Added \n to printf format | smart-ssh:914 |
| F2 | Major | jq failure unchecked | Added || error handler with cleanup | smart-ssh:904-908 |
| S1 | Major | Non-numeric http_code causes arithmetic error | Added regex validation | smart-ssh:819-822 |
