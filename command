// Stage progress — set by Transfer as each stage passes; read by RTPSend's
    // HandlePaymentOutcome to write granular LIMIT/SCREENING/LEDGER history.
    // On failure they reflect how far Transfer got before failing.

    /// <summary>True once the LIMIT check has passed in Transfer.</summary>
    public bool LimitPassed { get; set; }

    /// <summary>True once the SCREENING check has passed in Transfer.</summary>
    public bool ScreeningPassed { get; set; }

    /// <summary>True once the LEDGER debit has been posted in Transfer.</summary>
    public bool LedgerPosted { get; set; }
