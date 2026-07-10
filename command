 "statusHistory": [
        {
            "stage": "RTP_API",
            "status": "RECEIVED",
            "statusDate": "2026-07-10T03:37:51.5483616Z"
        },
        {
            "stage": "ACCOUNTLOOKUP",
            "status": "COMPLETED",
            "statusDate": "2026-07-10T03:37:52.4150846Z",
            "addInfo": "PartnerLedgerLookup completed"
        },
        {
            "stage": "ACCOUNTLOOKUP",
            "status": "INITIATED",
            "statusDate": "2026-07-10T03:37:52.7849392Z",
            "addInfo": {
                "message": "Submitted to Gateway tptch/send"
            }
        },
        {
            "stage": "LIMIT",
            "status": "COMPLETED",
            "statusDate": "2026-07-10T03:38:16.8841840Z",
            "addInfo": {
                "message": "LIMIT passed"
            }
        },
        {
            "stage": "SCREENING",
            "status": "FAILED",
            "statusDate": "2026-07-10T03:38:17.0618816Z",
            "addInfo": {
                "message": "SCREENING failed",
                "reason": "Keyword screening matched remittance information: 'scuba gear'"
            }
        },
        {
            "stage": "SCREENING",
            "status": "FAILED",
            "statusDate": "2026-07-10T03:38:19.5932281Z",
            "addInfo": {
                "message": "Pipeline failure: TransferFailed",
                "reason": "Keyword screening matched remittance information: 'scuba gear'"
            }
        }
    ],
