# Lambda Pinger
Lambda Function that will ping a targeted address.

Invoke this lambda through the Lambda Console.

## Parameters
The event object should be of this format:
```json
{
  "address": "127.0.0.1",
  "port": 80,
  "attempts": 5,
  "timeout": 5000
}
```

### Address
Required. Can be an IP or Domain Name.

### Port
Optional. Defaults to `80`

### Attempts
Optional. Defaults to `10`.

### Timeout
Optional. In milliseconds. Defaults to `5000` (5 seconds).
