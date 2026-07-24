import os
import json
import uuid

from locust import HttpUser, task, constant_throughput, events

# =============================================================================
# PaymentServices RTPSend — full-pipeline load test (QA) — Locust
#
# Each request sends a UNIQUE paymentReference (CreatePayment dedupes on it via
# Cosmos 409), so every request exercises the full async pipeline:
#   CreatePayment -> ProcessPayment -> Gateway -> AccountResolution
#   -> Transfer (ledger debit + limits + screening) -> RTPSend outcome -> TabaPay
#
# TPS model in Locust:
#   Throughput = (number of users) x (tasks per second per user)
#   constant_throughput(1) => each user fires 1 request/sec.
#   So: set the USER COUNT (in the Azure Load Testing "Load" config) equal to
#   your target TPS. e.g. 2 users => ~2 TPS, 20 users => ~20 TPS.
#   Set spawn rate high enough to ramp users quickly (e.g. equal to user count).
#
# Config via environment variables (set in Azure Load Testing parameters):
#   BASE_URL      e.g. https://fa-pmtsvc-rtpsend-qa-centralus.azurewebsites.net
#   FUNCTION_KEY  the CreatePayment function key (x-functions-key)
#   AMOUNT        per-payment amount (default 0.90)
# =============================================================================

BASE_URL = os.environ.get("BASE_URL", "")
FUNCTION_KEY = os.environ.get("FUNCTION_KEY", "")
AMOUNT = os.environ.get("AMOUNT", "0.90")

# CreatePayment requires these three auth headers; the next check after the
# header presence test looks up apiUserConfig by (clientId, merchantId,
# subscriptionKey), so they must be VALID values (same as a working request).
CLIENT_ID = os.environ.get("CLIENT_ID", "")
MERCHANT_ID = os.environ.get("MERCHANT_ID", "")
SUBSCRIPTION_KEY = os.environ.get("SUBSCRIPTION_KEY", "")


class CreatePaymentUser(HttpUser):
    # Each user attempts to keep a steady 1 request/sec. Target TPS = user count.
    wait_time = constant_throughput(1)

    # host can come from BASE_URL env var or the Azure Load Testing UI "host" field
    host = BASE_URL or None

    def on_start(self):
        self.headers = {"Content-Type": "application/json"}
        if FUNCTION_KEY:
            self.headers["x-functions-key"] = FUNCTION_KEY
        # Required by CreatePayment's header presence check + apiUserConfig lookup.
        self.headers["x-client-id"] = CLIENT_ID
        self.headers["x-merchant-id"] = MERCHANT_ID
        self.headers["ocp-apim-subscription-key"] = SUBSCRIPTION_KEY

    @task
    def create_payment(self):
        ref = str(uuid.uuid4())

        body = {
            "paymentReference": ref,
            "sourceAccountId": None,
            "sourceAccount": {
                "accountNumber": "9010010000000001",
                "name": {"company": None, "first": "Earnin", "last": "Merchant"},
                "address": None,
                "routingNumber": "084009593",
                "accountType": "S",
                "debtorBankMemberID": None,
                "debtorIdOther": None,
            },
            "destinationAccountId": None,
            "destinationAccount": {
                "accountNumber": "900397187386253",
                "name": {"company": None, "first": "Sarah", "last": "Robinson"},
                "routingNumber": "101115315",
                "accountType": "C",
                "address": {
                    "addressLines": ["123 First Street"],
                    "city": "Omaha",
                    "county": None,
                    "countryISOCode": "840",
                    "postalCode": "",
                    "stateCode": "NE",
                },
                "phoneNumber": "4022221144",
                "creditorAgentTCHMemberID": None,
                "creditorIdOther": None,
            },
            "amount": AMOUNT,
            "ultimateDebtor": {"name": "ultimate"},
            "sourceCurrency": None,
            "paymentCurrency": None,
            "softDescriptor": None,
        }

        with self.client.post(
            "/api/CreatePayment",
            data=json.dumps(body),
            headers=self.headers,
            name="CreatePayment",
            catch_response=True,
        ) as resp:
            if resp.status_code in (200, 202):
                resp.success()
            elif resp.status_code == 400:
                resp.failure("400 validation — check the 3 auth headers are present")
            elif resp.status_code == 403:
                resp.failure("403 forbidden — client/merchant/subscription values don't match apiUserConfig")
            elif resp.status_code == 409:
                resp.failure("Unexpected dedupe (409) — paymentReference collision")
            else:
                resp.failure(f"HTTP {resp.status_code}: {resp.text[:200]}")
