"statusHistory": [
        {
            "stage": "RTP_API",
            "status": "RECEIVED",
            "statusDate": "2026-07-09T17:52:23.5870219Z"
        },
        {
            "stage": "ACCOUNTLOOKUP",
            "status": "COMPLETED",
            "statusDate": "2026-07-09T17:52:23.8173555Z",
            "addInfo": "PartnerLedgerLookup completed"
        },
        {
            "stage": "ACCOUNTLOOKUP",
            "status": "INITIATED",
            "statusDate": "2026-07-09T17:52:24.0179200Z",
            "addInfo": {
                "message": "Submitted to Gateway tptch/send"
            }
        },
        {
            "stage": "TABAPAY",
            "status": "COMPLETED",
            "statusDate": "2026-07-09T17:52:42.9127924Z",
            "addInfo": "{\"SC\":200,\"EC\":\"0\",\"transactionID\":\"ltZLAk0ItcbtxkjeK8fY8D\",\"network\":\"RTP\",\"networkRC\":\"000\",\"networkID\":\"20260709STUBTABA289360\",\"status\":\"COMPLETED\",\"approvalCode\":\"580522\"}"
        }




 "statusHistory": [
        {
            "stage": "RTP_API",
            "status": "RECEIVED",
            "statusDate": "2026-07-09T18:02:17.2684230Z"
        },
        {
            "stage": "ACCOUNTLOOKUP",
            "status": "COMPLETED",
            "statusDate": "2026-07-09T18:02:17.4029008Z",
            "addInfo": "PartnerLedgerLookup completed"
        },
        {
            "stage": "ACCOUNTLOOKUP",
            "status": "INITIATED",
            "statusDate": "2026-07-09T18:02:17.5209931Z",
            "addInfo": {
                "message": "Submitted to Gateway tptch/send"
            }
        },
        {
            "stage": "ACCOUNTLOOKUP",
            "status": "FAILED",
            "statusDate": "2026-07-09T18:02:17.8713530Z",
            "addInfo": {
                "message": "Pipeline failure: TransferFailed",
                "reason": "Limit denied (PerItem): Limit '9900013724 Item Limit RTP Send' exceeded."
            }
        }
    ],



   "statusHistory": [
        {
            "stage": "RTP_API",
            "status": "RECEIVED",
            "statusDate": "2026-07-09T18:00:18.8389782Z"
        },
        {
            "stage": "ACCOUNTLOOKUP",
            "status": "COMPLETED",
            "statusDate": "2026-07-09T18:00:18.9702876Z",
            "addInfo": "PartnerLedgerLookup completed"
        },
        {
            "stage": "ACCOUNTLOOKUP",
            "status": "INITIATED",
            "statusDate": "2026-07-09T18:00:19.1607550Z",
            "addInfo": {
                "message": "Submitted to Gateway tptch/send"
            }
        },
        {
            "stage": "ACCOUNTLOOKUP",
            "status": "FAILED_NSF",
            "statusDate": "2026-07-09T18:00:19.6928512Z",
            "addInfo": {
                "message": "Pipeline failure: TransferFailed",
                "reason": "Insufficient funds on account 9900013724: balance 998.96, requested 999.14"
            }
        }
