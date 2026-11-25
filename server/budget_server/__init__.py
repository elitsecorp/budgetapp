"""Flask application factory for the Budget App server."""
from __future__ import annotations

import os
import secrets

from flask import Flask, redirect, url_for


def create_app(test_config=None) -> Flask:
    app = Flask(__name__, instance_relative_config=True)
    os.makedirs(app.instance_path, exist_ok=True)

    app.config.from_mapping(
        # Sessions + CSRF tokens. Overridable for reproducible deployments.
        SECRET_KEY=os.environ.get("SECRET_KEY") or secrets.token_hex(32),
        DATABASE=os.environ.get("BUDGET_DB")
        or os.path.join(app.instance_path, "budget.db"),
        # Admin console credentials — change these before hosting.
        ADMIN_USERNAME=os.environ.get("ADMIN_USERNAME", "admin"),
        ADMIN_PASSWORD=os.environ.get("ADMIN_PASSWORD", "admin"),
        # Shared secret the APK sends in X-API-Key. Empty = auth disabled (dev).
        API_KEY=os.environ.get("API_KEY", ""),
        MAX_CONTENT_LENGTH=8 * 1024 * 1024,  # 8 MB sync payloads
    )
    if test_config:
        app.config.update(test_config)

    if app.config["ADMIN_PASSWORD"] == "admin":
        app.logger.warning(
            "Admin console is using the default password 'admin' — "
            "set ADMIN_PASSWORD before exposing this server."
        )
    if not app.config["API_KEY"]:
        app.logger.warning("API_KEY is not set — /api/sync accepts unauthenticated writes.")

    from . import db

    db.init_app(app)

    from . import admin, api, auth

    app.register_blueprint(auth.bp)
    app.register_blueprint(admin.bp)
    app.register_blueprint(api.bp)

    # Template globals used by the forms.
    app.jinja_env.globals["csrf_token"] = auth.csrf_token

    @app.route("/")
    def index():
        return redirect(url_for("admin.dashboard"))

    return app
