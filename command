"statusHistory": [
        {
            "stage": "RTP_API",
            "status": "RECEIVED",
            "statusDate": "2026-07-09T19:28:46.8716822Z"
        },
        {
            "stage": "ACCOUNTLOOKUP",
            "status": "COMPLETED",
            "statusDate": "2026-07-09T19:28:47.0085931Z",
            "addInfo": "PartnerLedgerLookup completed"
        },
        {
            "stage": "ACCOUNTLOOKUP",
            "status": "INITIATED",
            "statusDate": "2026-07-09T19:28:47.1351108Z",
            "addInfo": {
                "message": "Submitted to Gateway tptch/send"
            }
        },
        {
            "stage": "ACCOUNTLOOKUP",
            "status": "COMPLETED",
            "statusDate": "2026-07-09T19:28:47.1548146Z",
            "addInfo": {
                "message": "Screening and limits passed"
            }
        },
        {
            "stage": "ACCOUNTLOOKUP",
            "status": "FAILED",
            "statusDate": "2026-07-09T19:28:47.6904994Z",
            "addInfo": {
                "message": "Pipeline failure: TransferFailed",
                "reason": "Keyword screening matched remittance information: 'scuba gear'"
            }
        }
    ],
