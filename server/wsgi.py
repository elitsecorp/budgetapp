"""WSGI entry point for production servers (gunicorn, uvicorn, Render...).

    gunicorn --bind 0.0.0.0:$PORT wsgi:app
"""
from budget_server import create_app

app = create_app()
