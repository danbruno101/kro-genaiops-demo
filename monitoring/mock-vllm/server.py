#!/usr/bin/env python3
"""
mock-vllm — a tiny OpenAI-compatible stub that stands in for a real vLLM server
so the demo runs on a CPU-only laptop with zero GPU and zero model download.

It exposes the three endpoints the demo touches:
  GET  /health                  -> readiness probe target
  GET  /metrics                 -> Prometheus exposition (so monitoring lights up)
  POST /v1/chat/completions     -> OpenAI-shaped response (so a curl looks real)

The point of the talk is portability, not the model — this keeps the payload
boring on purpose so KRO is the star. In gpu mode the RGD swaps this image for
vllm/vllm-openai and none of the surrounding YAML changes.

Stdlib only. No pip install. Build: see Dockerfile in this directory.
"""
import json, os, time, random
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MODEL = os.environ.get("MODEL_NAME", "mock-model")
SERVICE = os.environ.get("SERVICE_NAME", "mock")
_started = time.time()
_requests = 0
_tokens = 0


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="application/json"):
        data = body.encode() if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *a):  # quiet logs for a clean stage terminal
        pass

    def do_GET(self):
        global _requests
        if self.path == "/health":
            self._send(200, json.dumps({"status": "ok", "model": MODEL}))
        elif self.path == "/metrics":
            uptime = time.time() - _started
            metrics = (
                "# HELP genaiops_requests_total Total chat completion requests.\n"
                "# TYPE genaiops_requests_total counter\n"
                f'genaiops_requests_total{{service="{SERVICE}",model="{MODEL}"}} {_requests}\n'
                "# HELP genaiops_tokens_total Total tokens generated.\n"
                "# TYPE genaiops_tokens_total counter\n"
                f'genaiops_tokens_total{{service="{SERVICE}"}} {_tokens}\n'
                "# HELP genaiops_uptime_seconds Process uptime.\n"
                "# TYPE genaiops_uptime_seconds gauge\n"
                f'genaiops_uptime_seconds{{service="{SERVICE}"}} {uptime:.0f}\n'
            )
            self._send(200, metrics, "text/plain; version=0.0.4")
        else:
            self._send(404, json.dumps({"error": "not found"}))

    def do_POST(self):
        global _requests, _tokens
        if self.path == "/v1/chat/completions":
            _requests += 1
            n = random.randint(12, 48)
            _tokens += n
            resp = {
                "id": f"chatcmpl-mock-{_requests}",
                "object": "chat.completion",
                "model": MODEL,
                "choices": [{
                    "index": 0,
                    "message": {"role": "assistant",
                                "content": f"[mock:{SERVICE}] served by KRO-managed pod."},
                    "finish_reason": "stop",
                }],
                "usage": {"prompt_tokens": 8, "completion_tokens": n,
                          "total_tokens": 8 + n},
            }
            self._send(200, json.dumps(resp))
        else:
            self._send(404, json.dumps({"error": "not found"}))


if __name__ == "__main__":
    print(f"mock-vllm up: model={MODEL} service={SERVICE} on :8000", flush=True)
    ThreadingHTTPServer(("0.0.0.0", 8000), Handler).serve_forever()
