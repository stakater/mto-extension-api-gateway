#!/usr/bin/env python3
"""Lab token issuers. Keys live in hack/lab/.state/ (git ignores it).

  tokens.py keys                 make the RSA keys of issuers a, b and c, if missing
  tokens.py jwks <a|b|c>         print the issuer's JWKS as one line of JSON
  tokens.py mint <a|b|c> '<json claims>'   print an RS256 token; the claims are added
                                 to iss=https://idp-<k>.lab/realms/apis, aud=apis, exp=+1h

Uses only openssl and the Python standard library.
"""
import base64, json, os, subprocess, sys, time

STATE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".state")


def b64(raw):
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def key(k):
    return os.path.join(STATE, f"key-{k}.pem")


def cmd_keys():
    os.makedirs(STATE, exist_ok=True)
    for k in "abc":
        if not os.path.exists(key(k)):
            subprocess.run(["openssl", "genrsa", "-out", key(k), "2048"], check=True, capture_output=True)


def cmd_jwks(k):
    out = subprocess.run(["openssl", "rsa", "-in", key(k), "-noout", "-modulus"],
                         capture_output=True, text=True, check=True).stdout.strip()
    n = b64(bytes.fromhex(out.split("=", 1)[1]))
    print(json.dumps({"keys": [{"kty": "RSA", "alg": "RS256", "use": "sig", "kid": f"key-{k}", "n": n, "e": "AQAB"}]},
                     separators=(",", ":")))


def cmd_mint(k, claims):
    now = int(time.time())
    payload = {"iss": f"https://idp-{k}.lab/realms/apis", "aud": "apis", "iat": now, "exp": now + 3600,
               "sub": claims.get("azp", "lab")}
    payload.update(claims)
    head = {"alg": "RS256", "typ": "JWT", "kid": f"key-{k}"}
    signing = f"{b64(json.dumps(head).encode())}.{b64(json.dumps(payload).encode())}"
    sig = subprocess.run(["openssl", "dgst", "-sha256", "-sign", key(k)], input=signing.encode(),
                         capture_output=True, check=True).stdout
    print(f"{signing}.{b64(sig)}")


if __name__ == "__main__":
    if sys.argv[1] == "keys":
        cmd_keys()
    elif sys.argv[1] == "jwks":
        cmd_jwks(sys.argv[2])
    elif sys.argv[1] == "mint":
        cmd_mint(sys.argv[2], json.loads(sys.argv[3]) if len(sys.argv) > 3 else {})
    else:
        sys.exit(__doc__)
