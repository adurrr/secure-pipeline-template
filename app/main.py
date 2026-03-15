import os
import logging

from flask import Flask, jsonify, request
from werkzeug.middleware.proxy_fix import ProxyFix

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger(__name__)

app = Flask(__name__)
app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1)


@app.route("/healthz")
def healthz():
    return jsonify(status="ok")


@app.route("/readyz")
def readyz():
    return jsonify(status="ready")


@app.route("/api/v1/info")
def info():
    return jsonify(
        service="secure-pipeline-template",
        version=os.getenv("APP_VERSION", "dev"),
        environment=os.getenv("APP_ENV", "local"),
    )


@app.before_request
def log_request():
    logger.info(
        "request",
        extra={
            "method": request.method,
            "path": request.path,
            "remote_addr": request.remote_addr,
        },
    )


if __name__ == "__main__":
    port = int(os.getenv("PORT", "8080"))
    app.run(host="0.0.0.0", port=port)
