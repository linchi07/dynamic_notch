#!/usr/bin/env python3
"""Upload a release artifact (e.g. DMG) to Backblaze B2 bucket via native B2 REST API.

Zero third-party dependencies - runs directly on Python 3 standard library.

Required credentials (can be passed via arguments or environment variables):
    B2_APPLICATION_KEY_ID   (or --key-id)
    B2_APPLICATION_KEY      (or --app-key)
    B2_BUCKET_NAME          (or --bucket)

Usage:
    python3 scripts/upload_b2.py \\
        --file path/to/DynamicNotch-1.2.dmg \\
        --bucket my-b2-bucket \\
        --key-id 004xxxx \\
        --app-key K004xxxx

Exit codes: 0 = success, 1 = upload failed.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


def die(message: str) -> "NoReturn":  # noqa: F821
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


class B2Uploader:
    """Manages authentication and file uploads to Backblaze B2."""

    def __init__(self, key_id: str, app_key: str, bucket_name: str) -> None:
        self.key_id = key_id
        self.app_key = app_key
        self.bucket_name = bucket_name
        self.api_url: str = ""
        self.auth_token: str = ""
        self.account_id: str = ""
        self.bucket_id: str = ""

    def authorize(self) -> None:
        """Authenticate against B2 and retrieve apiUrl and account tokens."""
        auth_header = base64.b64encode(f"{self.key_id}:{self.app_key}".encode("utf-8")).decode("utf-8")
        req = urllib.request.Request(
            "https://api.backblazeb2.com/b2api/v3/b2_authorize_account",
            headers={"Authorization": f"Basic {auth_header}"},
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            err_body = exc.read().decode("utf-8", errors="replace")
            die(f"B2 authorization failed (HTTP {exc.code}): {err_body}")
        except Exception as exc:
            die(f"B2 authorization network failure: {exc}")

        self.api_url = data["apiUrl"]
        self.auth_token = data["authorizationToken"]
        self.account_id = data["accountId"]

        # Check if the key is restricted to a specific bucket
        allowed = data.get("allowed", {})
        if allowed.get("bucketId"):
            self.bucket_id = allowed["bucketId"]
            if allowed.get("bucketName") and allowed["bucketName"] != self.bucket_name:
                die(
                    f"Application key is restricted to bucket '{allowed['bucketName']}', "
                    f"but requested bucket is '{self.bucket_name}'."
                )

    def resolve_bucket_id(self) -> str:
        """Look up bucketId by bucketName if not already obtained from authorize."""
        if self.bucket_id:
            return self.bucket_id

        url = f"{self.api_url}/b2api/v3/b2_list_buckets"
        payload = json.dumps({"accountId": self.account_id, "bucketName": self.bucket_name}).encode("utf-8")
        req = urllib.request.Request(
            url,
            data=payload,
            headers={
                "Authorization": self.auth_token,
                "Content-Type": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = json.loads(resp.read().decode("utf-8"))
        except Exception as exc:
            die(f"failed to query B2 bucket '{self.bucket_name}': {exc}")

        buckets = data.get("buckets", [])
        for b in buckets:
            if b.get("bucketName") == self.bucket_name:
                self.bucket_id = b["bucketId"]
                return self.bucket_id

        die(f"bucket '{self.bucket_name}' not found under B2 account {self.account_id}")

    def get_upload_url(self) -> tuple[str, str]:
        """Request a dedicated uploadUrl and uploadAuthorizationToken for the bucket."""
        url = f"{self.api_url}/b2api/v3/b2_get_upload_url"
        payload = json.dumps({"bucketId": self.bucket_id}).encode("utf-8")
        req = urllib.request.Request(
            url,
            data=payload,
            headers={
                "Authorization": self.auth_token,
                "Content-Type": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = json.loads(resp.read().decode("utf-8"))
        except Exception as exc:
            die(f"failed to obtain B2 upload URL: {exc}")

        return data["uploadUrl"], data["authorizationToken"]

    def upload_file(self, file_path: str, remote_filename: str | None = None, max_retries: int = 3) -> dict:
        """Upload local file to B2 with SHA1 verification and retries."""
        if not os.path.isfile(file_path):
            die(f"local file does not exist: {file_path}")

        file_size = os.path.getsize(file_path)
        dest_name = remote_filename or os.path.basename(file_path)

        print(f"Hashing {file_path} ({file_size} bytes)...")
        sha1_hasher = hashlib.sha1()
        with open(file_path, "rb") as fh:
            while chunk := fh.read(1024 * 1024):
                sha1_hasher.update(chunk)
        file_sha1 = sha1_hasher.hexdigest()

        print(f"Uploading '{dest_name}' to B2 bucket '{self.bucket_name}'...")
        encoded_name = urllib.parse.quote(dest_name, safe="/")

        for attempt in range(1, max_retries + 1):
            upload_url, upload_token = self.get_upload_url()
            req = urllib.request.Request(
                upload_url,
                headers={
                    "Authorization": upload_token,
                    "X-Bz-File-Name": encoded_name,
                    "Content-Type": "application/octet-stream",
                    "Content-Length": str(file_size),
                    "X-Bz-Content-Sha1": file_sha1,
                },
            )

            try:
                with open(file_path, "rb") as fh:
                    req.data = fh.read()
                with urllib.request.urlopen(req, timeout=300) as resp:
                    resp_data = json.loads(resp.read().decode("utf-8"))
                    print(
                        f"Successfully uploaded '{dest_name}' (fileId: {resp_data.get('fileId')}) "
                        f"to B2 bucket '{self.bucket_name}'."
                    )
                    return resp_data
            except urllib.error.HTTPError as exc:
                err_content = exc.read().decode("utf-8", errors="replace")
                print(f"Upload attempt {attempt} failed (HTTP {exc.code}): {err_content}", file=sys.stderr)
                if attempt < max_retries and exc.code in (408, 500, 503):
                    time.sleep(2 * attempt)
                    continue
                die(f"B2 upload failed permanently: {err_content}")
            except Exception as exc:
                print(f"Upload attempt {attempt} encountered network error: {exc}", file=sys.stderr)
                if attempt < max_retries:
                    time.sleep(2 * attempt)
                    continue
                die(f"B2 upload network error: {exc}")

        die(f"failed to upload {file_path} after {max_retries} attempts")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--file", required=True, help="local file path to upload")
    parser.add_argument("--destination", help="remote filename in bucket (default: same as local basename)")
    parser.add_argument(
        "--bucket",
        default=os.getenv("B2_BUCKET_NAME"),
        help="B2 bucket name (default: B2_BUCKET_NAME env var)",
    )
    parser.add_argument(
        "--key-id",
        default=os.getenv("B2_APPLICATION_KEY_ID"),
        help="B2 application key ID (default: B2_APPLICATION_KEY_ID env var)",
    )
    parser.add_argument(
        "--app-key",
        default=os.getenv("B2_APPLICATION_KEY"),
        help="B2 application key (default: B2_APPLICATION_KEY env var)",
    )

    args = parser.parse_args(argv)

    if not args.bucket:
        die("need B2 bucket name (set B2_BUCKET_NAME or pass --bucket)")
    if not args.key_id:
        die("need B2 application key ID (set B2_APPLICATION_KEY_ID or pass --key-id)")
    if not args.app_key:
        die("need B2 application key (set B2_APPLICATION_KEY or pass --app-key)")

    uploader = B2Uploader(key_id=args.key_id, app_key=args.app_key, bucket_name=args.bucket)
    uploader.authorize()
    uploader.resolve_bucket_id()
    uploader.upload_file(file_path=args.file, remote_filename=args.destination)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
