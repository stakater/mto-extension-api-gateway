#!/usr/bin/env python3
"""Runs inside the lab's client pods (mounted from a ConfigMap). Standard library only.

  client.py req   <url> <host> [token] [name:value ...]
                                                 one GET with extra headers; prints {"status", "url", "headers"}
  client.py burst <url> <host> <token> <n>       n GETs, a new connection each; prints the status counts
  client.py keep  <url> <host> <token> <n> <s>   n GETs every s seconds on one kept-open connection;
                                                 prints the status counts and the reconnects
  client.py plain <url>                          one GET with no Host change; prints the status or the error
The URL names the address to connect to; <host> is sent as the Host header ("-" keeps the URL's host).
"""
import collections, http.client, json, sys, time, urllib.parse


def conn(url):
    u = urllib.parse.urlsplit(url)
    cls = http.client.HTTPSConnection if u.scheme == "https" else http.client.HTTPConnection
    return cls(u.hostname, u.port or (443 if u.scheme == "https" else 80), timeout=10), (u.path or "/") + (
        "?" + u.query if u.query else "")


def get(c, path, host, token, extra=()):
    headers = dict(h.split(":", 1) for h in extra)
    if host != "-":
        headers["Host"] = host
    if token and token != "-":  # "-" or "" sends no token
        headers["Authorization"] = "Bearer " + token
    c.putrequest("GET", path, skip_host=host != "-", skip_accept_encoding=True)
    for k, v in headers.items():
        c.putheader(k, v)
    c.endheaders()
    r = c.getresponse()
    return r, r.read().decode(errors="replace")


def main():
    mode = sys.argv[1]
    if mode == "req":
        c, path = conn(sys.argv[2])
        r, body = get(c, path, sys.argv[3], sys.argv[4] if len(sys.argv) > 4 else "", sys.argv[5:])
        out = {"status": r.status}
        try:
            j = json.loads(body)
            out["url"] = j.get("url")
            out["headers"] = {k.lower(): v for k, v in (j.get("headers") or {}).items()}
        except ValueError:
            out["body"] = body[:120]
        print(json.dumps(out))
    elif mode == "burst":
        counts = collections.Counter()
        for _ in range(int(sys.argv[5])):
            c, path = conn(sys.argv[2])
            try:
                r, _ = get(c, path, sys.argv[3], sys.argv[4])
                counts[str(r.status)] += 1
            except Exception as e:  # a reset or timeout is a result too
                counts[type(e).__name__] += 1
            c.close()
        print(json.dumps(dict(counts)))
    elif mode == "keep":
        counts, reconnects = collections.Counter(), 0
        c, path = conn(sys.argv[2])
        for _ in range(int(sys.argv[5])):
            try:
                r, _ = get(c, path, sys.argv[3], sys.argv[4])
                counts[str(r.status)] += 1
                if (r.getheader("connection") or "").lower() == "close":
                    c.close(); c, path = conn(sys.argv[2]); reconnects += 1
            except Exception as e:
                counts[type(e).__name__] += 1; reconnects += 1
                c, path = conn(sys.argv[2])
            time.sleep(float(sys.argv[6]))
        print(json.dumps({"counts": dict(counts), "reconnects": reconnects}))
    elif mode == "plain":
        try:
            c, path = conn(sys.argv[2])
            c.request("GET", path)
            print(c.getresponse().status)
        except Exception as e:
            print("ERR " + type(e).__name__)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
