# HTTP Security Headers — Reference

All headers are configured in Apache on hostA. This document explains what each
header does and why it is required for Luna Bags' e-commerce environment.

## Headers Implemented

### Strict-Transport-Security (HSTS)
```
Strict-Transport-Security: max-age=31536000; includeSubDomains; preload
```
Tells browsers to always use HTTPS for this domain for the next 365 days.
Prevents SSL stripping attacks where an attacker downgrades the connection to HTTP.
`preload` allows inclusion in browser HSTS preload lists for additional protection.

### X-Frame-Options
```
X-Frame-Options: DENY
```
Prevents the Luna Bags website from being embedded in an iframe on another site.
Blocks clickjacking attacks where an attacker overlays invisible frames to trick
customers into clicking malicious elements while appearing to interact with Luna Bags.

### X-Content-Type-Options
```
X-Content-Type-Options: nosniff
```
Prevents browsers from MIME-sniffing the content type. Without this, a browser
might execute a JavaScript file served as `text/plain`. Required to prevent
content-type confusion attacks.

### X-XSS-Protection
```
X-XSS-Protection: 1; mode=block
```
Activates the browser's built-in XSS filter and tells it to block the page rather
than attempt to sanitize it. Provides a secondary layer of XSS protection for
browsers that support it (older IE/Edge). Modern browsers rely on CSP instead.

### Referrer-Policy
```
Referrer-Policy: strict-origin-when-cross-origin
```
Controls how much referrer information is included in requests. This setting sends
the full URL for same-origin requests, but only the origin (no path) for
cross-origin requests. Prevents leaking internal URL structures or customer
session tokens to third-party services.

### Content-Security-Policy (CSP)
```
Content-Security-Policy: default-src 'self'
```
Tells browsers to only load resources (scripts, styles, images, fonts) from the
Luna Bags server itself. Blocks inline scripts and external resource loading.
The strongest practical defense against XSS — even if an attacker injects a
script tag, the browser will refuse to execute it.

## Apache Configuration

All headers are set in the Apache virtual host configuration:

```apache
Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
Header always set X-Frame-Options "DENY"
Header always set X-Content-Type-Options "nosniff"
Header always set X-XSS-Protection "1; mode=block"
Header always set Referrer-Policy "strict-origin-when-cross-origin"
Header always set Content-Security-Policy "default-src 'self'"
```

The `always` keyword ensures headers are sent even for error responses (403, 404, 500).
Without `always`, headers are only sent with 200 OK responses.

## Verification

To verify headers are present:
```bash
curl -I -k https://10.9.0.5
```

Expected output includes all 6 headers listed above.
