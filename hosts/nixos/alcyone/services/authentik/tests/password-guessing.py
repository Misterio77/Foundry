import os
import unittest
from datetime import timedelta
from pathlib import Path

import django
from django.conf import settings

settings.TEST = True
django.setup()

from django.contrib.auth.models import AnonymousUser
from django.contrib.messages.storage.fallback import FallbackStorage
from django.core.cache import cache
from django.core.management import call_command
from django.test import RequestFactory
from django.utils.timezone import now

from authentik.blueprints.models import BlueprintInstance
from authentik.blueprints.v1.importer import Importer
from authentik.core.models import User
from authentik.core.sessions import SessionStore
from authentik.flows.models import Flow, FlowStageBinding
from authentik.flows.planner import FlowPlanner
from authentik.policies.reputation.models import Reputation, reputation_expiry
from authentik.stages.deny.models import DenyStage
from authentik.stages.password import BACKEND_INBUILT
from authentik.stages.password.models import PasswordStage
from authentik.stages.password.stage import authenticate
from authentik.tenants.utils import get_current_tenant


call_command("migrate_schemas", interactive=False, verbosity=0)
blueprints = Path(os.environ["AUTHENTIK_BLUEPRINTS_DIR"])
for path in blueprints.rglob("*.yaml"):
    importer = Importer.from_string(path.read_text())
    BlueprintInstance.objects.update_or_create(
        name=importer.blueprint.metadata.name,
        defaults={"path": str(path.relative_to(blueprints))},
    )

for filename in ("password-guessing.yaml", "password-guessing.yaml"):
    importer = Importer.from_string((blueprints / filename).read_text())
    assert importer.apply(), f"Blueprint import failed: {filename}"


class PasswordGuessingTests(unittest.TestCase):
    sensitive_flows = (
        "default-password-change",
        "default-user-settings-flow",
        "default-authenticator-totp-setup",
        "default-authenticator-webauthn-setup",
        "foundry-provider-authorization-email-required",
    )

    def setUp(self):
        Reputation.objects.including_expired().delete()
        cache.clear()
        self.user, _ = User.objects.get_or_create(username="guessing-test")
        self.user.email = ""
        self.user.set_password("not-the-guessed-password")
        self.user.save()
        self.request = self.make_request()

    def make_request(self, ip="192.0.2.1", authenticated=False):
        request = RequestFactory().get("/", REMOTE_ADDR=ip)
        request.user = self.user if authenticated else AnonymousUser()
        request.tenant = get_current_tenant()
        request.session = SessionStore()
        request.session.create()
        request._messages = FallbackStorage(request)
        return request

    def first_password_stage(self, slug, request=None):
        request = request or self.request
        flow = Flow.objects.get(slug=slug)
        plan = FlowPlanner(flow).plan(request)
        if slug == "default-authentication-flow":
            self.assertEqual(plan.next(request).order, 10)
            # Simulate Identification completing; the real marker/ORM/policy engine follows.
            plan.context["pending_user"] = self.user
            plan.pop()
        binding = plan.next(request)
        return binding.stage

    def fail_password(self, request=None):
        self.assertIsNone(
            authenticate(
                request or self.request,
                [BACKEND_INBUILT],
                username=self.user.username,
                password="wrong",
            )
        )

    def test_restarts_and_new_ips_do_not_reset_username_score(self):
        for _ in range(5):
            self.assertIsInstance(
                self.first_password_stage("default-authentication-flow"), PasswordStage
            )
            self.fail_password()
        for request in (self.request, self.make_request("192.0.2.2")):
            self.assertIsInstance(
                self.first_password_stage("default-authentication-flow", request),
                DenyStage,
            )

    def test_authenticated_direct_flows_share_the_login_budget(self):
        request = self.make_request(authenticated=True)
        for slug in self.sensitive_flows:
            with self.subTest(slug=slug, blocked=False):
                self.assertIsInstance(
                    self.first_password_stage(slug, request), PasswordStage
                )
        for _ in range(5):
            self.fail_password(request)
        for slug in self.sensitive_flows:
            with self.subTest(slug=slug, blocked=True):
                self.assertIsInstance(
                    self.first_password_stage(slug, request), DenyStage
                )
        self.assertTrue(User.objects.get(pk=self.user.pk).is_active)

    def test_ip_spray_is_blocked_independently_of_username(self):
        for index in range(19):
            Reputation.objects.create(
                identifier=f"sprayed-user-{index}", ip="192.0.2.1", score=-1
            )
        self.assertIsInstance(
            self.first_password_stage("default-authentication-flow"), PasswordStage
        )
        Reputation.objects.create(
            identifier="sprayed-user-19", ip="192.0.2.1", score=-1
        )
        self.assertIsInstance(
            self.first_password_stage("default-authentication-flow"), DenyStage
        )
        self.assertIsInstance(
            self.first_password_stage(
                "default-authentication-flow", self.make_request("192.0.2.2")
            ),
            PasswordStage,
        )

    def test_expired_scores_stop_blocking_without_cleanup(self):
        expiry = reputation_expiry()
        self.assertAlmostEqual((expiry - now()).total_seconds(), 900, delta=2)
        Reputation.objects.create(
            identifier=self.user.username, ip="192.0.2.1", score=-5
        )
        self.assertIsInstance(
            self.first_password_stage("default-authentication-flow"), DenyStage
        )
        Reputation.objects.all().update(expires=now() - timedelta(seconds=1))
        self.assertIsInstance(
            self.first_password_stage("default-authentication-flow"), PasswordStage
        )

    def test_existing_email_authorization_is_not_blocked(self):
        self.user.email = "guessing-test@example.invalid"
        self.user.save()
        Reputation.objects.create(
            identifier=self.user.username, ip="192.0.2.1", score=-20
        )
        request = self.make_request(authenticated=True)
        flow = Flow.objects.get(slug="foundry-provider-authorization-email-required")
        plan = FlowPlanner(flow).plan(request)
        self.assertIsNone(plan.next(request))

    def test_import_is_idempotent_and_all_gates_are_dynamic(self):
        bindings = FlowStageBinding.objects.filter(
            stage__name="foundry-password-guessing-deny"
        )
        self.assertEqual(bindings.count(), 7)
        self.assertEqual(
            set(bindings.values_list("target__slug", flat=True)),
            {"default-authentication-flow", *self.sensitive_flows},
        )
        for binding in bindings:
            self.assertFalse(binding.evaluate_on_plan)
            self.assertTrue(binding.re_evaluate_policies)


unittest.main()
