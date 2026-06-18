#!/usr/bin/env python3
"""
mock-drift — a tiny stand-in for a model-drift detector that runs alongside a
live fine-tuned model. It exposes the same /health + /metrics surface as the
serving stub, so the EXISTING Prometheus (shared platform infra) scrapes it with
zero config change once the RGD adds the standard prometheus.io/scrape
annotations and genaiops.kro.run/service label.

It emits a drifting score over time so the monitoring beat has something live to
show: a genaiops_drift_score gauge that wanders, and a
genaiops_drift_alerts_total counter that increments whenever the score crosses a
threshold (representing "data distribution has shifted, consider retraining").

The point of the talk is the platform abstraction (kro), not the detector — this
keeps the payload boring on purpose. A real platform would swap this image for a
proper drift monitor (e.g. evidently / NannyML); none of the surrounding YAML
changes.

Stdlib only. No pip install.
"""
import json
import math
import os
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SERVICE = os.environ.get("SERVICE_NAME", "mock")
TARGET = os.environ.get("TARGET", "http://localhost")
ALERT_THRESHOLD = float(os.environ.get("DRIFT_ALERT_THRESHOLD", "0.30"))
_started = time.time()
_alerts = 0
_last_alerting = False


def current_drift():
    """A slow sinusoid + baseline so the gauge visibly moves on a dashboard."""
    t = time.time() - _started
    return round(0.15 + 0.20 * (0.5 + 0.5 * math.sin(t / 30.0)), 4)


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
        global _alerts, _last_alerting
        if self.path == "/health":
            self._send(200, json.dumps({"status": "ok", "service": SERVICE,
                                        "target": TARGET}))
        elif self.path == "/metrics":
            drift = current_drift()
            alerting = drift >= ALERT_THRESHOLD
            # Count a new alert only on a rising edge across the threshold.
            if alerting and not _last_alerting:
                _alerts += 1
            _last_alerting = alerting
            metrics = (
                "# HELP genaiops_drift_score Current data/prediction drift score (0-1).\n"
                "# TYPE genaiops_drift_score gauge\n"
                f'genaiops_drift_score{{service="{SERVICE}"}} {drift}\n'
                "# HELP genaiops_drift_alerts_total Times drift crossed the alert threshold.\n"
                "# TYPE genaiops_drift_alerts_total counter\n"
                f'genaiops_drift_alerts_total{{service="{SERVICE}"}} {_alerts}\n'
                "# HELP genaiops_drift_threshold Configured drift alert threshold.\n"
                "# TYPE genaiops_drift_threshold gauge\n"
                f'genaiops_drift_threshold{{service="{SERVICE}"}} {ALERT_THRESHOLD}\n'
            )
            self._send(200, metrics, "text/plain; version=0.0.4")
        else:
            self._send(404, json.dumps({"error": "not found"}))


if __name__ == "__main__":
    print(f"mock-drift up: service={SERVICE} target={TARGET} on :8000", flush=True)
    ThreadingHTTPServer(("0.0.0.0", 8000), Handler).serve_forever()
