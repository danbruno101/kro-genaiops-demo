#!/usr/bin/env python3
"""
mock-trainer — a tiny stand-in for a real fine-tuning + evaluation job so the
second use-case runs on a CPU-only laptop with zero GPU and zero model download.

It does the whole lifecycle a real trainer would, just with fake numbers:
  1. "trains" for N epochs, printing a decreasing loss (clean stage output),
  2. writes a fake fine-tuned artifact to the mounted artifacts volume,
  3. registers the run, its metrics, and the produced model to MLflow (REST),
  4. evaluates against the dataset and, in APPROVAL_POLICY=auto, promotes the
     model for serving ONLY if eval_accuracy >= EVAL_THRESHOLD by patching this
     FineTuneModel's spec.approved=true via the in-cluster Kubernetes API.

The point of the talk is the platform abstraction (kro), not the model — this
keeps the payload boring on purpose. In gpu mode the RGD requests an accelerator
and a real platform would swap this image for a real trainer; none of the
surrounding YAML changes.

Stdlib only. No pip install, no kubectl, no mlflow client. Talks to MLflow and
the Kubernetes API over plain HTTP(S) with urllib.
"""
import json
import os
import ssl
import time
import urllib.error
import urllib.request

MODEL = os.environ.get("MODEL_NAME", "mock-model")
DATASET = os.environ.get("DATASET", "demo-dataset")
SERVICE = os.environ.get("SERVICE_NAME", "mock")
INSTANCE = os.environ.get("INSTANCE_NAME", SERVICE)
EPOCHS = int(os.environ.get("EPOCHS", "3"))
MLFLOW = os.environ.get("MLFLOW_TRACKING_URI", "http://mlflow:5000").rstrip("/")
POLICY = os.environ.get("APPROVAL_POLICY", "manual").lower()
THRESHOLD = float(os.environ.get("EVAL_THRESHOLD", "0.80"))

ARTIFACT_DIR = "/mnt/artifacts"
SA_DIR = "/var/run/secrets/kubernetes.io/serviceaccount"


def log(msg):
    print(msg, flush=True)


# --- MLflow REST helpers -----------------------------------------------------
def mlflow_post(path, payload):
    req = urllib.request.Request(
        f"{MLFLOW}/api/2.0/mlflow/{path}",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=15) as r:
        body = r.read().decode()
        return json.loads(body) if body else {}


def wait_for_mlflow(retries=30, delay=4):
    """MLflow may still be starting when the Job runs. Poll its health first."""
    for i in range(1, retries + 1):
        try:
            with urllib.request.urlopen(f"{MLFLOW}/health", timeout=5) as r:
                if r.status == 200:
                    log(f"MLflow reachable at {MLFLOW}")
                    return True
        except Exception as e:  # noqa: BLE001 - demo resilience
            log(f"waiting for MLflow... ({i}) {e}")
        time.sleep(delay)
    return False


def get_or_create_experiment(name):
    try:
        out = mlflow_post("experiments/create", {"name": name})
        return out["experiment_id"]
    except urllib.error.HTTPError as e:
        # Already exists -> look it up.
        if e.code in (400, 409):
            url = f"{MLFLOW}/api/2.0/mlflow/experiments/get-by-name?experiment_name={name}"
            with urllib.request.urlopen(url, timeout=15) as r:
                return json.load(r)["experiment"]["experiment_id"]
        raise


def register_to_mlflow(final_loss, eval_accuracy):
    exp_id = get_or_create_experiment("genaiops-finetuning")
    now = int(time.time() * 1000)
    run = mlflow_post(
        "runs/create",
        {
            "experiment_id": exp_id,
            "start_time": now,
            "tags": [
                {"key": "mlflow.runName", "value": f"{INSTANCE}-{now}"},
                {"key": "base_model", "value": MODEL},
                {"key": "dataset", "value": DATASET},
            ],
        },
    )
    run_id = run["run"]["info"]["run_id"]
    for key, value in (("loss", final_loss), ("eval_accuracy", eval_accuracy),
                       ("epochs", float(EPOCHS))):
        mlflow_post("runs/log-metric",
                    {"run_id": run_id, "key": key, "value": value,
                     "timestamp": now, "step": EPOCHS})
    mlflow_post("runs/update",
                {"run_id": run_id, "status": "FINISHED",
                 "end_time": int(time.time() * 1000)})

    # Register the produced model into the MLflow Model Registry.
    try:
        mlflow_post("registered-models/create", {"name": INSTANCE})
    except urllib.error.HTTPError as e:
        if e.code not in (400, 409):  # already exists is fine
            raise
    version = mlflow_post(
        "model-versions/create",
        {"name": INSTANCE, "source": f"{ARTIFACT_DIR}/model", "run_id": run_id},
    )
    v = version.get("model_version", {}).get("version", "?")
    log(f"MLflow: registered model '{INSTANCE}' version {v} (run {run_id})")
    return run_id


# --- Kubernetes self-approval (auto mode) ------------------------------------
def read_sa(name):
    with open(os.path.join(SA_DIR, name)) as f:
        return f.read().strip()


def self_approve(retries=8, delay=3):
    """PATCH spec.approved=true on this FineTuneModel via the in-cluster API.

    Retries on transient 403s: the RoleBinding granting this ServiceAccount
    patch access is created by kro alongside the Job, so it may not have
    propagated yet when the run reaches this point.
    """
    token = read_sa("token")
    namespace = read_sa("namespace")
    host = os.environ["KUBERNETES_SERVICE_HOST"]
    port = os.environ.get("KUBERNETES_SERVICE_PORT_HTTPS", "443")
    url = (f"https://{host}:{port}/apis/kro.run/v1alpha1/namespaces/"
           f"{namespace}/finetunemodels/{INSTANCE}")
    ctx = ssl.create_default_context(cafile=os.path.join(SA_DIR, "ca.crt"))
    for attempt in range(1, retries + 1):
        req = urllib.request.Request(
            url,
            data=json.dumps({"spec": {"approved": True}}).encode(),
            headers={
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/merge-patch+json",
            },
            method="PATCH",
        )
        try:
            with urllib.request.urlopen(req, context=ctx, timeout=15) as r:
                if r.status in (200, 201):
                    log(f"GATE: auto-approved '{INSTANCE}' -> serving will scale up.")
                    return
        except urllib.error.HTTPError as e:
            if e.code in (401, 403) and attempt < retries:
                log(f"self-approval not authorized yet (RBAC propagating), "
                    f"retry {attempt}/{retries}...")
                time.sleep(delay)
                continue
            raise


# --- The "training" run ------------------------------------------------------
def main():
    log(f"mock-trainer: fine-tuning {MODEL} on dataset '{DATASET}' "
        f"for {EPOCHS} epochs (policy={POLICY}, threshold={THRESHOLD})")

    loss = 1.0
    for epoch in range(1, EPOCHS + 1):
        loss = round(1.0 / (epoch + 1) + 0.05, 4)
        log(f"  epoch {epoch}/{EPOCHS}  loss={loss}")
        time.sleep(1)

    # Write a fake fine-tuned artifact so serving has something to mount.
    os.makedirs(f"{ARTIFACT_DIR}/model", exist_ok=True)
    with open(f"{ARTIFACT_DIR}/model/config.json", "w") as f:
        json.dump({"base_model": MODEL, "dataset": DATASET,
                   "epochs": EPOCHS, "final_loss": loss}, f)
    log(f"  wrote fine-tuned artifact to {ARTIFACT_DIR}/model")

    # Evaluate against the eval dataset (mock score, deterministic-ish > 0.8).
    eval_accuracy = round(0.80 + (1.0 - loss) * 0.15, 4)
    log(f"  evaluation: eval_accuracy={eval_accuracy}")

    if wait_for_mlflow():
        # Registration stays best-effort (a registry hiccup must never fail the
        # training run), but retry transient failures: CI asserts the model is
        # registered, so a single dropped POST shouldn't silently lose it.
        registered = False
        for attempt in range(1, 6):
            try:
                register_to_mlflow(loss, eval_accuracy)
                registered = True
                break
            except Exception as e:  # noqa: BLE001 - never fail the run on registry hiccup
                log(f"WARN: MLflow registration attempt {attempt}/5 failed: {e}")
                time.sleep(3)
        if not registered:
            log("WARN: MLflow registration did not succeed after retries.")
    else:
        log("WARN: MLflow not reachable; skipping registration.")

    # The approval gate.
    if POLICY == "auto" and eval_accuracy >= THRESHOLD:
        log(f"GATE: auto policy and eval_accuracy {eval_accuracy} >= "
            f"{THRESHOLD} -> promoting.")
        try:
            self_approve()
        except Exception as e:  # noqa: BLE001
            log(f"ERROR: self-approval failed: {e}")
    elif POLICY == "auto":
        log(f"GATE: auto policy but eval_accuracy {eval_accuracy} < "
            f"{THRESHOLD} -> BLOCKED, model NOT promoted.")
    else:
        log("GATE: manual policy -> pending data-scientist approval "
            "(review metrics in MLflow, then set spec.approved=true).")

    log("mock-trainer: done.")


if __name__ == "__main__":
    main()
