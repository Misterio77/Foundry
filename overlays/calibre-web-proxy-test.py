import ast
import importlib.util
import pathlib
import sys
import unittest
from types import SimpleNamespace
from uuid import uuid4

import sqlalchemy as sa
from flask import Flask, g
from sqlalchemy.orm import declarative_base, sessionmaker

source = pathlib.Path(sys.argv.pop(1))


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


proxy = load("foundry_proxy", source / "foundry_proxy.py")
constants = load("constants", source / "constants.py")
Base = declarative_base()
# Use upstream's actual columns/defaults without starting its global application.
user_ast = next(n for n in ast.parse((source / "ub.py").read_text()).body
                if isinstance(n, ast.ClassDef) and n.name == "User")
user_ast.bases = [ast.Name(id="Base", ctx=ast.Load())]
user_ast.body = [n for n in user_ast.body if isinstance(n, ast.Assign)
                 and (not isinstance(n.value, ast.Call)
                      or isinstance(n.value.func, ast.Name) and n.value.func.id == "Column")]
namespace = {**vars(sa), "Base": Base, "constants": constants}
exec(compile(ast.fix_missing_locations(ast.Module(body=[user_ast], type_ignores=[])),
             "ub.User", "exec"), namespace)
User = namespace["User"]


class ProxyTests(unittest.TestCase):
    def setUp(self):
        self.engine = sa.create_engine("sqlite://")
        Base.metadata.create_all(self.engine)
        self.session = sessionmaker(bind=self.engine)()
        self.app = Flask(__name__)
        self.app.secret_key = "test-only"
        proxy.install(self.app, SimpleNamespace(session=self.session, User=User), constants)

        @self.app.get("/")
        def index():
            self.assertIs(g._login_user, g.flask_httpauth_user)
            return {"id": g._login_user.id, "role": g._login_user.role}

        self.client = self.app.test_client()
        self.subject = str(uuid4())

    def tearDown(self):
        self.session.close()
        self.engine.dispose()

    def get(self, subject=None, **kwargs):
        return self.client.get("/", headers={"X-Foundry-Books-Subject": subject or self.subject}, **kwargs)

    def test_first_login_and_repeat(self):
        first = self.get()
        self.assertEqual(first.status_code, 200)
        self.assertEqual(first.json["role"], constants.ROLE_DOWNLOAD | constants.ROLE_VIEWER)
        self.assertEqual(first.json, self.get().json)
        self.assertEqual(self.session.query(User).count(), 1)
        self.assertNotEqual(first.json["id"], self.get(str(uuid4())).json["id"])

    def test_invalid_or_missing_subject(self):
        for subject in ("admin", "guest", "", "123", self.subject + ",admin"):
            response = self.client.get("/", headers={"X-Foundry-Books-Subject": subject})
            self.assertEqual(response.status_code, 403)
        self.assertEqual(self.client.get("/").status_code, 403)
        self.assertEqual(self.session.query(User).count(), 0)

    def test_untrusted_peer_even_with_forwarded_loopback(self):
        response = self.client.get("/", headers={
            "X-Foundry-Books-Subject": self.subject,
            "X-Forwarded-For": "127.0.0.1",
        }, environ_overrides={"REMOTE_ADDR": "192.0.2.1"})
        self.assertEqual(response.status_code, 403)
        self.assertEqual(self.session.query(User).count(), 0)

    def test_existing_account_collision_is_not_linked(self):
        self.session.add(User(name="ak-" + self.subject.replace("-", ""),
                              email="admin@example.org", role=constants.ROLE_ADMIN))
        self.session.commit()
        self.assertEqual(self.get().status_code, 403)
        self.assertEqual(self.session.query(User).count(), 1)
        self.assertEqual(self.session.execute(sa.select(proxy.identities)).all(), [])

    def test_stale_browser_session_cannot_select_another_user(self):
        self.session.add(User(name="admin", email="admin@example.org", role=constants.ROLE_ADMIN))
        self.session.commit()
        with self.client.session_transaction() as session:
            session["_user_id"] = "1"
        response = self.get()
        self.assertNotEqual(response.json["id"], 1)
        self.assertFalse(response.json["role"] & constants.ROLE_ADMIN)
        self.assertEqual(self.client.get("/").status_code, 403)

    def test_renames_and_permissions_are_preserved(self):
        user_id = self.get().json["id"]
        user = self.session.get(User, user_id)
        user.name = "renamed-locally"
        user.email = "changed@example.org"
        user.role = constants.ROLE_VIEWER
        self.session.commit()
        self.assertEqual(self.get().json, {"id": user_id, "role": constants.ROLE_VIEWER})

    def test_deleted_account_fails_closed(self):
        user_id = self.get().json["id"]
        self.session.delete(self.session.get(User, user_id))
        self.session.commit()
        self.assertEqual(self.get().status_code, 403)


unittest.main()
