"""Opt-in, proxy-only identities for Foundry's browser deployment."""

from uuid import UUID
from secrets import token_urlsafe

from flask import abort, g, request
from sqlalchemy import Column, Integer, MetaData, String, Table, select
from sqlalchemy.exc import IntegrityError
from werkzeug.security import generate_password_hash

metadata = MetaData()
identities = Table(
    "foundry_proxy_identity", metadata,
    Column("subject", String(36), primary_key=True),
    Column("user_id", Integer, unique=True, nullable=False),
)


def provision(session, User, constants, subject):
    subject = str(UUID(subject))
    user_id = session.execute(
        select(identities.c.user_id).where(identities.c.subject == subject)
    ).scalar_one_or_none()
    if user_id is not None:
        user = session.get(User, user_id)
        if user is None:
            raise ValueError("Proxy identity refers to a deleted user")
        return user

    # Never link existing users by mutable names or email, including on collision.
    user = User(
        name="ak-" + UUID(subject).hex,
        email=UUID(subject).hex + "@authentik.invalid",
        password=generate_password_hash(token_urlsafe(48)),
        role=constants.ROLE_DOWNLOAD | constants.ROLE_VIEWER,
        sidebar_view=constants.SIDEBAR_RECENT | constants.SIDEBAR_AUTHOR
        | constants.SIDEBAR_SERIES | constants.SIDEBAR_READ_AND_UNREAD,
    )
    try:
        session.add(user)
        session.flush()
        session.execute(identities.insert().values(subject=subject, user_id=user.id))
        session.commit()
        return user
    except IntegrityError:
        session.rollback()
        # A concurrent first request may have provisioned the same identity.
        user_id = session.execute(
            select(identities.c.user_id).where(identities.c.subject == subject)
        ).scalar_one_or_none()
        if user_id is None:
            raise ValueError("Proxy account collides with an existing local account")
        user = session.get(User, user_id)
        if user is None:
            raise ValueError("Proxy identity refers to a deleted user")
        return user


def install(app, ub, constants):
    metadata.create_all(ub.session.get_bind())

    @app.before_request
    def authenticate():
        # Do not trust forwarded client IPs, browser sessions, or local passwords.
        if request.remote_addr not in ("127.0.0.1", "::1"):
            abort(403)
        subject = request.headers.get("X-Foundry-Books-Subject", "")
        try:
            user = provision(ub.session, ub.User, constants, subject)
        except (ValueError, AttributeError):
            abort(403)
        g.flask_httpauth_user = user
        g._login_user = user
